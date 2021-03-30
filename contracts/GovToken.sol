// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";

import "./Token.sol";
import "./GovERC20Upgradeable.sol";
import "./IOracle.sol";
import "./TokenMonetaryPolicy.sol";

contract GovToken is Initializable, GovERC20Upgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 private UNIT; // = 10 ** _decimals
    uint256 private _feeMultiplier;
    uint256 private _feeDivisor;

    // Market oracle provides the gSTAB/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 gSTAB is trading for $1.50.
    IOracle public govTokenPriceOracle;

    // Keeps a list of tokens which are mintable for 1$ worth of gSTAB.
    mapping(address => bool) private _allowedTokens;
    EnumerableSetUpgradeable.AddressSet private _stabTokens;
    uint256 private _totalSupplyEpoch;
    uint256 private _tokensTotalSupply;

    // Set monetary policy.
    TokenMonetaryPolicy private _monetaryPolicy;

    function initialize() public initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained("gov.stableflect.finance", "gSTAB");

        UNIT = 10 ** 9;
        _tokensTotalSupply = 0;
        _totalSupplyEpoch = 0;

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
        _stabTokens.add(token);
        updateTotalSupply(true);
    }

    /**
     * @dev Removes STAB tokens which can be claimed for 1$ worth of gSTAB.
     */
    function removeTokenAddresses(address token) public onlyAdmin {
        require(_allowedTokens[token], "This token is not governed yet.");
        delete _allowedTokens[token];
        _stabTokens.remove(token);
        updateTotalSupply(true);
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
    * @notice Sets monetary policy contract. It is required to get current epoch.
    */
    function setTokenMonetaryPolicy(address monetaryPolicy_) public onlyAdmin
    {
        _monetaryPolicy = TokenMonetaryPolicy(monetaryPolicy_);
        updateTotalSupply(true);
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

    /**
    * @notice Applies fee to send amount. The bigger fee, the shorter time to rebase left.
    */
    function applyRebaseAwareFee(uint256 beforeFee) internal view returns(uint256) {
        // TODO get amount of time left to rebase window and apply fee.
        return beforeFee;
    }

    /**
    * @notice Updates total supply if required.
    */
    function updateTotalSupply(bool force) internal {
        if (force || _monetaryPolicy.epoch() != _totalSupplyEpoch) {
            _tokensTotalSupply = sumTotalSupplyOfTokens();
            _totalSupplyEpoch = _monetaryPolicy.epoch();
        }
    }

    /**
    * @notice Calculates total supply of all allowed STAB tokens.
    */
    function sumTotalSupplyOfTokens() internal view returns(uint256) {
        uint256 totalSupply = 0;
        for (uint256 i = 0; i < _stabTokens.length(); i++) {
            totalSupply = totalSupply.add(Token(_stabTokens.at(i)).totalSupply());
        }
        return totalSupply;
    }

    /**
    * @notice _msgSender receives STAB token in exchange for gSTAB.
    */
    function mintStabForGov(Token token, uint256 govAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        address sender = _msgSender();
        _burn(sender, govAmount); // Simulate transfer + burn in one step, but check allowance as for normal transfer.
        decreaseAllowance(address(this), govAmount);

        updateTotalSupply(false);

        uint256 govPrice = getGovPrice();
        uint256 stabAmount = govAmount.mul(govPrice).div(UNIT); // Always treat STAB as 1$.
        stabAmount = stabAmount.mul(totalSupply()).div(_tokensTotalSupply); // but scale the price by all STAB's total supply : gov total supply
        token.mint(sender, applyFee(stabAmount));
    }

    /**
    * @notice _msgSender receives gSTAB token in exchange for STAB.
    */
    function mintGovForStab(Token token, uint256 stabAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        token.transferFrom(_msgSender(), address(this), stabAmount);
        token.burnMyTokens(stabAmount);

        updateTotalSupply(false);

        uint256 govPrice = getGovPrice();
        uint256 govAmount = stabAmount.mul(UNIT).div(govPrice); // Always treat STAB as 1$.
        govAmount = govAmount.mul(_tokensTotalSupply).div(totalSupply());  // but scale the price by all STAB's total supply : gov total supply
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
