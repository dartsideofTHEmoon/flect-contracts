// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol"; // Use exactly the same version of math lib as Token.

import "./Token.sol";
import "./utils/SafeMathInt.sol";
import "./utils/UInt256Lib.sol";
import "./ChainSwap.sol";
import "./IOracle.sol";

/**
 * @title StabToken Monetary Supply Policy
 * @dev This is an implementation of the StabToken Index Fund protocol.
 *      StabToken operates symmetrically on expansion and contraction. It will both split and
 *      combine coins to maintain a stable unit price.
 *
 *      This component regulates the token supply of the StabToken ERC20 token in response to
 *      market oracles.
 */
contract TokenMonetaryPolicy is Context, AccessControl, ChainSwap {
    using SafeMathUpgradeable for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        uint256 targetRate,
        uint256 mcap,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec,
        bool reverted
    );

    Token public STAB;
    Token public rSTAB;

    // Provides the current market cap, as an 18 decimal fixed point number.
    IOracle public mcapOracle;

    // Market oracle provides the STAB/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 STAB is trading for $1.50.
    IOracle public tokenPriceOracle;

    // Market oracle provides the rSTAB/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 STAB is trading for $1.50.
    IOracle public tokenRevPriceOracle;

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
    address public orchestrator; // Address of main orchestrator, using Access Control more can be added manually by admin.
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE"); // 0xe098e2e7d2d4d3ca0e3877ceaaf3cdfbd47483f6699688ad12b1d6732deef10b

    address private whiteListedSigner;
    string private chainName;

    /**
     * @dev ZOS upgradable contract initialization method.
     *      It is called at the time of contract creation to invoke parent class initializers and
     *      initialize the contract's state variables.
     */
    constructor(Token STAB_, Token rSTAB_, uint256 startMcap_, string memory chainName_) {
        rebaseLag = 1;
        minRebaseTimeIntervalSec = 1 days;
        rebaseWindowOffsetSec = 79200;
        // 10PM UTC
        rebaseWindowLengthSec = 60 minutes;
        lastRebaseTimestampSec = 0;
        epoch = 1;

        previousMcap = startMcap_;

        STAB = STAB_;
        rSTAB = rSTAB_;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ORCHESTRATOR_ROLE, _msgSender());
        whiteListedSigner = address(_msgSender());
        chainName = chainName_;

        // amount * _feeMultiplier / _feeDivisor;
        _feeMultiplier = 1;
        _feeDivisor = 1;
    }

    /**
    * @notice Function checks if caller is an admin.
    */
    function requireAdmin() internal view {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Restricted to admins.");
    }

    /**
    * @notice Modifier allowing only admin role.
    */
    modifier onlyAdmin() {
        requireAdmin();
        _;
    }

    /**
    * @notice Modifier allowing only orchestrator role.
    */
    modifier onlyOrchestrator() {
        require(hasRole(ORCHESTRATOR_ROLE, _msgSender()), "Restricted to orchestrator.");
        _;
    }

    /**
    * @notice Sets token (long) instance.
    */
    function setStabToken(address _STAB) public onlyAdmin
    {
        STAB = Token(_STAB);
    }

    /**
    * @notice Sets reverse (short) token instance.
    */
    function setRevStabToken(address _STAB) public onlyAdmin
    {
        rSTAB = Token(_STAB);
    }

    /**
    * @notice Change white listed signer.
    */
    function setWhiteListedSigner(address newSigner) public onlyAdmin
    {
        whiteListedSigner = newSigner;
    }

    /**
    * @notice Change fee paid on chain swap.
    */
    function setFeeParams(uint256 multiplier, uint256 divisor) public onlyAdmin
    {
        require(multiplier <= divisor, "Really? Bonus for chain swap? xD");

        _feeMultiplier = multiplier;
        _feeDivisor = divisor;
    }

    /**
    * @notice Block or unblock claim for message hash.
    */
    function setClaimed(uint256 id, address sendTo, uint256 amount, string memory chainName_, uint256 epoch_, bool toValue) public onlyAdmin {
        return _setClaimed(id, sendTo, amount, chainName_, epoch_, toValue);
    }

    /**
    * @notice Perform part of rebase (for one coin).
    */
    function partRebase(Token stab_, uint256 mcap, bool reversed) internal {
        int256 beforeSupply = stab_.totalSupply().toInt256Safe();
        uint256 targetRate;
        uint256 tokenPrice;
        (targetRate, tokenPrice) = reversed ? getRevRebaseParams(mcap) : getRebaseParams(mcap);
        uint256 newSupply = stab_.rebase(tokenPrice, targetRate, rebaseLag);
        emit LogRebase(epoch, tokenPrice, targetRate, mcap, beforeSupply.sub(newSupply.toInt256Safe()), block.timestamp, reversed);
    }

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     *
     * @dev The supply adjustment equals (_totalSupply * DeviationFromTargetRate) / rebaseLag
     *      Where DeviationFromTargetRate is (TokenPriceOracleRate - targetPrice) / targetPrice
     *      and targetPrice is McapOracleRate / baseMcap
     */
    function rebase() external onlyOrchestrator {
        require(inRebaseWindow(), "the rebase window is closed");

        // This comparison also ensures there is no reentrancy.
        require(lastRebaseTimestampSec.add(minRebaseTimeIntervalSec) < block.timestamp, "cannot rebase yet");

        // Snap the rebase time to the start of this window.
        lastRebaseTimestampSec = block.timestamp.sub(block.timestamp.mod(minRebaseTimeIntervalSec)).add(rebaseWindowOffsetSec);

        uint256 mcap = getMcap();

        partRebase(STAB, mcap, false);
        partRebase(rSTAB, mcap, true);

        previousMcap = mcap;
        epoch = epoch.add(1);
    }

    function getMcap() public view returns(uint256) {
        uint256 mcap;
        bool mcapValid;
        (mcap, mcapValid) = mcapOracle.getData();
        require(mcapValid, "invalid mcap");

        return mcap;
    }

    /**
    * @notice Calculates rebase parameters.
    */
    function getRebaseParams(uint256 mcap) public view returns (uint256, uint256) {
        uint256 tokenPrice;
        bool tokenPriceValid;
        (tokenPrice, tokenPriceValid) = tokenPriceOracle.getData();
        require(tokenPriceValid, "invalid token price");

        uint256 targetRate = mcap.mul(UNIT).div(previousMcap);

        if (tokenPrice > MAX_RATE) {
            tokenPrice = MAX_RATE;
        }

        return (targetRate, tokenPrice);
    }

    /**
    * @notice Calculates rebase parameters for reverted STAB.
    */
    function getRevRebaseParams(uint256 mcap) public view returns (uint256, uint256) {
        uint256 tokenPrice;
        bool tokenPriceValid;
        (tokenPrice, tokenPriceValid) = tokenRevPriceOracle.getData();
        require(tokenPriceValid, "invalid token price");

        uint256 targetRate = previousMcap.mul(UNIT).div(mcap);

        if (tokenPrice > MAX_RATE) {
            tokenPrice = MAX_RATE;
        }

        return (targetRate, tokenPrice);
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
     * @notice Sets the reference to the reverted token price oracle.
     * @param tokenRevPriceOracle_ The address of the token price oracle contract.
     */
    function setRevTokenPriceOracle(IOracle tokenRevPriceOracle_) external onlyAdmin
    {
        tokenRevPriceOracle = tokenRevPriceOracle_;
    }

    /**
     * @notice Sets the reference to the orchestrator.
     * @param orchestrator_ The address of the orchestrator contract.
     */
    function setOrchestrator(address orchestrator_) external onlyAdmin
    {
        revokeRole(ORCHESTRATOR_ROLE, orchestrator);
        orchestrator = orchestrator_;
        grantRole(ORCHESTRATOR_ROLE, orchestrator);
    }

    /**
     * @notice Sets the rebase lag parameter.
               It is used to dampen the applied supply adjustment by 1 / rebaseLag
               If the rebase lag R, equals 1, the smallest value for R, then the full supply
               correction is applied on each rebase cycle.
               If it is greater than 1, then a correction of 1/R of is applied on each rebase.
               When rebase is lower than 0, then actually it is a multiplier instead of 'lag'.
     * @param rebaseLag_ The new rebase lag parameter.
     */
    function setRebaseLag(int256 rebaseLag_) external onlyAdmin
    {
        require(rebaseLag_ != 0, "rebase lag cannot be 0");
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

    /**
    * @return Amount of time left to next rebase window.
    */
    function getTimeLeftToRebaseWindow() public view returns (uint256) {
        if (rebaseWindowOffsetSec <= block.timestamp.mod(minRebaseTimeIntervalSec)) {
            return 0; // in rebase window already;
        }
        return rebaseWindowOffsetSec.sub(block.timestamp.mod(minRebaseTimeIntervalSec));
    }

    /**
     * @notice First stage - creates migration request.
     It might be required to allow monetary policy to make transfer of particular amount of tokens before this call.
     * @param amount - Value of transfer to other chain.
     * @param toNetwork - Name of a new available chain.
     * @param toAddress - Users address on a new chain (it is of string type to support different than ETH address formats).
     * @param timeForUnlock - Maximum time for unlock on new chain, after that chain rollback without password will be possible.
     */
    function migrateToOtherChain(uint256 amount, string memory toNetwork, string memory toAddress,
        uint256 timeForUnlock, bool reversed) public
    {
        _migrateToOtherChain(reversed ? rSTAB : STAB, amount, toNetwork, toAddress, timeForUnlock, epoch);
    }

    /**
    * @notice Second stage - claims moved funds to a new owner on a new chain.
    * @param sendTo - user address on a new chain.
    * @param amount - STAB amount to send.
    */
    function claimFromOtherChain(uint64 id, address sendTo, uint256 amount, bytes memory signature, bool reversed) public onlyOrchestrator {
        _claimFromOtherChain(reversed ? rSTAB : STAB, id, sendTo, amount, chainName, epoch, signature, whiteListedSigner);
    }
}
