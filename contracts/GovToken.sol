// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "./Token.sol";
import "./GovERC20Upgradeable.sol";
import "./IOracle.sol";

contract GovToken is Initializable, GovERC20Upgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;

    uint256 private UNIT; // = 10 ** _decimals
    uint256 internal _feeMultiplier;
    uint256 internal _feeDivisor;

    // Market oracle provides the gSTAB/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 gSTAB is trading for $1.50.
    IOracle public govTokenPriceOracle;

    // Keeps a list of tokens which are mintable for 1$ worth of gSTAB.
    mapping(address => bool) private _allowedTokens;

    function initialize() public initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained("gov.stableflect.finance", "gSTAB");

        UNIT = 10 ** 9;

        address owner = _msgSender();
        _mint(owner, UNIT.mul(100000000)); // 100 mln tokens.
        _setupRole(DEFAULT_ADMIN_ROLE, owner);

        setFeeParams(995, 1000); // 0.5% fee.
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only admins");
        _;
    }

    /**
     * @dev Add STAB tokens which can be claimed for 1$ worth of gSTAB.
     */
    function addTokenAddresses(address token) public onlyAdmin {
        require(_allowedTokens[token] == false, "This token is already governed.");
        require(address(0) != token, "Cannot add a zero address.");
        _allowedTokens[token] = true;
    }

    /**
     * @dev Removes STAB tokens which can be claimed for 1$ worth of gSTAB.
     */
    function removeTokenAddresses(address token) public onlyAdmin {
        require(_allowedTokens[token], "This token is not governed yet.");
        delete _allowedTokens[token];
    }

    /**
     * @dev Sets the reference to the token price oracle.
     * @param govTokenPriceOracle_ The address of the gSTAB token price oracle contract.
     */
    function setTokenPriceOracle(IOracle govTokenPriceOracle_) external onlyAdmin
    {
        govTokenPriceOracle = govTokenPriceOracle_;
    }

    /**
    * @notice Change fee paid when exchanges (r)STAB <-> gSTAB.
    */
    function setFeeParams(uint256 multiplier, uint256 divisor) public onlyAdmin
    {
        require(multiplier <= divisor, "'multiplier' shouldn't be higher than 'divisor'");

        _feeMultiplier = multiplier;
        _feeDivisor = divisor;
    }

    /**
    * @notice Fetches gSTAB price from oracle.
    */
    function getGovPrice() internal view returns (uint256) {
        uint256 tokenPrice;
        bool tokenPriceValid;
        (tokenPrice, tokenPriceValid) = govTokenPriceOracle.getData();
        require(tokenPriceValid, "invalid token price");

        return tokenPrice;
    }

    /**
    * @notice Applies fee to send amount.
    */
    function applyFee(uint256 beforeFee) internal view returns (uint256) {
        return beforeFee.mul(_feeMultiplier).div(_feeDivisor);
    }

    function applyRebaseAwareFee(uint256 beforeFee) internal view returns(uint256) {
        // TODO get amount of time left to rebase window and apply fee.
        return beforeFee;
    }

    /**
    * @notice _msgSender receives STAB token in exchange for gSTAB.
    */
    function mintStabForGov(Token token, uint256 govAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        address sender = _msgSender();
        _burn(sender, govAmount); // Simulate transfer + burn in one step, but check allowance as for normal transfer.
        decreaseAllowance(address(this), govAmount);

        uint256 govPrice = getGovPrice();
        uint256 stabAmount = govAmount.mul(govPrice).div(UNIT); // Always treat STAB as 1$.
        token.mint(sender, applyFee(stabAmount));
    }

    /**
    * @notice _msgSender receives gSTAB token in exchange for STAB.
    */
    function mintGovForStab(Token token, uint256 stabAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        token.transferFrom(_msgSender(), address(this), stabAmount);
        token.burnMyTokens(stabAmount);

        uint256 govPrice = getGovPrice();
        uint256 govAmount = stabAmount.mul(UNIT).div(govPrice); // Always treat STAB as 1$.
        _mint(_msgSender(), applyFee(govAmount));
    }

    /**
    * @notice _msgSender receives gSTAB token in exchange for STAB.
    */
    function exchangeStabForStab(Token fromStab, Token toStab, uint256 fromAmount) public {
        require(_allowedTokens[address(fromStab)], "'from' token is not governed by this contract.");
        require(_allowedTokens[address(toStab)], "'to' token is not governed by this contract.");

        fromStab.transferFrom(_msgSender(), address(this), fromAmount);
        fromStab.burnMyTokens(fromAmount);

        toStab.mint(_msgSender(), applyRebaseAwareFee(fromAmount));
    }
}
