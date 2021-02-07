pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/GSN/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "./Token.sol";
import "./utils/SafeMathInt.sol";
import "./utils/UInt256Lib.sol";

interface IOracle {
    function getData() external view returns (uint256, bool);
}

/**
 * @title StabToken Monetary Supply Policy
 * @dev This is an implementation of the StabToken Index Fund protocol.
 *      StabToken operates symmetrically on expansion and contraction. It will both split and
 *      combine coins to maintain a stable unit price.
 *
 *      This component regulates the token supply of the StabToken ERC20 token in response to
 *      market oracles.
 */
contract TokenMonetaryPolicy is Initializable, ContextUpgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        uint256 mcap,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec
    );

    Token public STAB;

    // Provides the current market cap, as an 18 decimal fixed point number.
    IOracle public mcapOracle;

    // Market oracle provides the token/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 STAB is trading for $1.50.
    IOracle public tokenPriceOracle;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // The rebase lag parameter, used to dampen the applied supply adjustment by 1 / rebaseLag
    // Check setRebaseLag comments for more details.
    // Natural number, no decimal places.
    int256 public rebaseLag;

    // More than this much time must pass between rebase operations.
    uint256 public minRebaseTimeIntervalSec;

    // Block timestamp of last rebase operation
    uint256 public lastRebaseTimestampSec;

    // The rebase window begins this many seconds into the minRebaseTimeInterval period.
    // For example if minRebaseTimeInterval is 24hrs, it represents the time of day in seconds.
    uint256 public rebaseWindowOffsetSec;

    // The length of the time window where a rebase operation is allowed to execute, in seconds.
    uint256 public rebaseWindowLengthSec;

    // The number of rebase cycles since inception
    uint256 public epoch;

    uint256 private constant DECIMALS = 9;

    uint256 private constant UNIT = 10 ** DECIMALS;

    uint256 private previousMcap;

    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 10 ** 6 * 10 ** DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = ~(uint256(1) << 255) / MAX_RATE;

    // This module orchestrates the rebase execution and downstream notification.
    address public orchestrator;

    address[] private charityRecipients;
    mapping(address => bool)    private charityExists;
    mapping(address => uint256) private charityIndex;
    mapping(address => uint256) private charityPercentOnExpansion;
    mapping(address => uint256) private charityPercentOnContraction;
    uint256 private totalCharityPercentOnExpansion;
    uint256 private totalCharityPercentOnContraction;

    /**
     * @dev ZOS upgradable contract initialization method.
     *      It is called at the time of contract creation to invoke parent class initializers and
     *      initialize the contract's state variables.
     */
    function initialize(Token STAB_, uint256 startMcap) public initializer
    {
        __Context_init();
        __AccessControl_init();

        deviationThreshold = 0;
        rebaseLag = 1;
        minRebaseTimeIntervalSec = 1 days;
        rebaseWindowOffsetSec = 79200;
        // 10PM UTC
        rebaseWindowLengthSec = 60 minutes;
        lastRebaseTimestampSec = 0;
        epoch = 1;

        previousMcap = startMcap;

        STAB = STAB_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
    * @notice Modifier allowing only admin role.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Restricted to admins.");
        _;
    }

    /**
    * @notice Sets token instance.
    */
    function setStabToken(address _STAB) public onlyAdmin
    {
        STAB = Token(_STAB);
    }

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     *
     * @dev The supply adjustment equals (_totalSupply * DeviationFromTargetRate) / rebaseLag
     *      Where DeviationFromTargetRate is (TokenPriceOracleRate - targetPrice) / targetPrice
     *      and targetPrice is McapOracleRate / baseMcap
     */
    function rebase() external {
        require(_msgSender() == orchestrator, "you are not the orchestrator");
        require(inRebaseWindow(), "the rebase window is closed");

        // This comparison also ensures there is no reentrancy.
        require(lastRebaseTimestampSec.add(minRebaseTimeIntervalSec) < block.timestamp, "cannot rebase yet");

        // Snap the rebase time to the start of this window.
        lastRebaseTimestampSec = block.timestamp.sub(block.timestamp.mod(minRebaseTimeIntervalSec)).add(rebaseWindowOffsetSec);

        int256 beforeSupply = STAB.totalSupply().toInt256Safe();
        uint256 mcap;
        uint256 targetRate;
        uint256 tokenPrice;
        (mcap, targetRate, tokenPrice) = getRebaseParams();

        uint256 newSupply = STAB.rebase(tokenPrice, targetRate, rebaseLag);
        emit LogRebase(epoch, tokenPrice, mcap, beforeSupply.sub(newSupply.toInt256Safe()), block.timestamp);

        previousMcap = mcap;
        epoch = epoch.add(1);
    }

    /**
    * @notice Calculates rebase parameters.
    */
    function getRebaseParams() public view returns (uint256 mcap, uint256 targetRate, uint256 tokenPrice)
    {
        uint256 mcap;
        bool mcapValid;
        (mcap, mcapValid) = mcapOracle.getData();
        require(mcapValid, "invalid mcap");

        uint256 tokenPrice;
        bool tokenPriceValid;
        (tokenPrice, tokenPriceValid) = tokenPriceOracle.getData();
        require(tokenPriceValid, "invalid token price");

        uint256 targetRate = mcap.mul(UNIT);
        targetRate = targetRate.div(previousMcap);

        if (tokenPrice > MAX_RATE) {
            tokenPrice = MAX_RATE;
        }

        return (mcap, targetRate, tokenPrice);
    }

    /**
     * @notice Sets the reference to the market cap oracle.
     * @param mcapOracle_ The address of the mcap oracle contract.
     */
    function setMcapOracle(IOracle mcapOracle_) external onlyAdmin
    {
        mcapOracle = mcapOracle_;
    }

    /**
     * @notice Sets the reference to the token price oracle.
     * @param tokenPriceOracle_ The address of the token price oracle contract.
     */
    function setTokenPriceOracle(IOracle tokenPriceOracle_) external onlyAdmin
    {
        tokenPriceOracle = tokenPriceOracle_;
    }

    /**
     * @notice Sets the reference to the orchestrator.
     * @param orchestrator_ The address of the orchestrator contract.
     */
    function setOrchestrator(address orchestrator_) external onlyAdmin
    {
        orchestrator = orchestrator_;
    }

    /**
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_) external onlyAdmin
    {
        deviationThreshold = deviationThreshold_;
    }

    /**
     * @notice Sets the rebase lag parameter.
               It is used to dampen the applied supply adjustment by 1 / rebaseLag
               If the rebase lag R, equals 1, the smallest value for R, then the full supply
               correction is applied on each rebase cycle.
               If it is greater than 1, then a correction of 1/R of is applied on each rebase.
               When rebase is lower than 0, then actually it is multiplier.
     * @param rebaseLag_ The new rebase lag parameter.
     */
    function setRebaseLag(int256 rebaseLag_) external onlyAdmin
    {
        require(rebaseLag_ > 0);
        rebaseLag = rebaseLag_;
    }

    /**
     * @notice Sets the parameters which control the timing and frequency of
     *         rebase operations.
     *         a) the minimum time period that must elapse between rebase cycles.
     *         b) the rebase window offset parameter.
     *         c) the rebase window length parameter.
     * @param minRebaseTimeIntervalSec_ More than this much time must pass between rebase
     *        operations, in seconds.
     * @param rebaseWindowOffsetSec_ The number of seconds from the beginning of
              the rebase interval, where the rebase window begins.
     * @param rebaseWindowLengthSec_ The length of the rebase window in seconds.
     */
    function setRebaseTimingParameters(
        uint256 minRebaseTimeIntervalSec_,
        uint256 rebaseWindowOffsetSec_,
        uint256 rebaseWindowLengthSec_) external onlyAdmin
    {
        require(minRebaseTimeIntervalSec_ > 0, "minRebaseTimeIntervalSec cannot be 0");
        require(rebaseWindowOffsetSec_ < minRebaseTimeIntervalSec_, "rebaseWindowOffsetSec_ >= minRebaseTimeIntervalSec_");

        minRebaseTimeIntervalSec = minRebaseTimeIntervalSec_;
        rebaseWindowOffsetSec = rebaseWindowOffsetSec_;
        rebaseWindowLengthSec = rebaseWindowLengthSec_;
    }

    /**
     * @return If the latest block timestamp is within the rebase time window it, returns true.
     *         Otherwise, returns false.
     */
    function inRebaseWindow() public view returns (bool) {
        return (
        block.timestamp.mod(minRebaseTimeIntervalSec) >= rebaseWindowOffsetSec &&
        block.timestamp.mod(minRebaseTimeIntervalSec) < (rebaseWindowOffsetSec.add(rebaseWindowLengthSec))
        );
    }
}
