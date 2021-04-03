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
    uint256 internal _standardFeeMultiplier;
    uint256 internal _multiplier6hr;
    uint256 internal _multiplier1hr;
    uint256 internal _multiplier10m;
    uint256 internal _multiplier2m;
    uint256 internal _multiplierMadness;
    uint256 internal _feeDivisor;

    // Market oracle provides the gSTAB/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e9 it would mean 1 gSTAB is trading for $1.50.
    IOracle public govTokenPriceOracle;

    // Keeps a list of tokens which are mintable for 1$ worth of gSTAB.
    mapping(address => bool) internal _allowedTokens;
    EnumerableSetUpgradeable.AddressSet internal _stabTokens;
    mapping(address => TokenMonetaryPolicy) internal _allowedTokenToMonetaryPolicy;
    TokenMonetaryPolicy internal _mainMonetaryPolicy; // used only to keep track of epoch.
    uint256 internal _totalSupplyEpoch; // epoch in 'main' monetary policy.
    uint256 internal _tokensTotalSupply;

    function initialize(address monetaryPolicy, address[] memory tokens) public initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained("gov.stableflect.finance", "gSTAB");

        UNIT = 10 ** _decimals;
        _tokensTotalSupply = 0;
        _totalSupplyEpoch = 0;

        address owner = _msgSender();
        _mint(owner, UNIT.mul(100000000)); // 100 mln tokens.
        _setupRole(DEFAULT_ADMIN_ROLE, owner);

        for (uint256 i = 0; i < tokens.length; i++) {
            _allowedTokens[tokens[i]] = true;
            _stabTokens.add(tokens[i]);
            _allowedTokenToMonetaryPolicy[tokens[i]] = TokenMonetaryPolicy(monetaryPolicy);
        }
        _mainMonetaryPolicy = TokenMonetaryPolicy(monetaryPolicy);
        updateTotalSupply(true);
        setFeeParams(997, 990, 980, 950, 850, 667, 1000); // standard = 0.3% / 6hrs+ = 1% / 1hr+ 2% / 10min+ = 5% / 2min+ = 15% / madness = 33% fee.
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only admins");
        _;
    }

    /**
     * @dev Add STAB tokens which can be claimed for 1$ worth of gSTAB.
     */
    function addTokenAddresses(address token, TokenMonetaryPolicy monetaryPolicy) public onlyAdmin {
        require(_allowedTokens[token] == false, "This token is already governed.");
        require(address(0) != token, "Cannot add a zero address.");
        _allowedTokens[token] = true;
        _stabTokens.add(token);
        updateTotalSupply(true);
        _allowedTokenToMonetaryPolicy[token] = monetaryPolicy;
    }

    /**
     * @dev Removes STAB tokens which can be claimed for 1$ worth of gSTAB.
     */
    function removeTokenAddresses(address token) public onlyAdmin {
        require(_allowedTokens[token], "This token is not governed yet.");
        delete _allowedTokens[token];
        _stabTokens.remove(token);
        updateTotalSupply(true);
        delete _allowedTokenToMonetaryPolicy[token];
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
    function setFeeParams(uint256 standardMultiplier, uint256 multiplier6hr, uint256 multiplier1hr,
        uint256 multiplier10m, uint256 multiplier2m, uint256 multiplierMadness, uint256 divisor) public onlyAdmin
    {
        require(standardMultiplier <= divisor, "'multiplier' shouldn't be higher than 'divisor'");
        require(standardMultiplier >= multiplier6hr, "'multiplier6hr' shouldn't be higher than 'standardMultiplier'");
        require(multiplier6hr >= multiplier1hr, "'multiplier1hr' shouldn't be higher than 'multiplier6hr'");
        require(multiplier1hr >= multiplier10m, "'multiplier10m' shouldn't be higher than 'multiplier1hr'");
        require(multiplier10m >= multiplier2m, "'multiplier2min' shouldn't be higher than 'multiplier10m'");
        require(multiplier2m >= multiplierMadness, "'multiplierMadness' shouldn't be higher than 'multiplier2m'");

        _standardFeeMultiplier = standardMultiplier;
        _multiplier6hr = multiplier6hr;
        _multiplier1hr = multiplier1hr;
        _multiplier10m = multiplier10m;
        _multiplier2m = multiplier2m;
        _multiplierMadness = multiplierMadness;
        _feeDivisor = divisor;
    }

    /**
    * @notice Sets main monetary policy contract. It is required to get current epoch.
    */
    function setMainMonetaryPolicy(address monetaryPolicy) public onlyAdmin
    {
        _mainMonetaryPolicy = TokenMonetaryPolicy(monetaryPolicy);
        updateTotalSupply(true);
    }

    /**
    * @notice Sets monetary policy contract for a token.
    */
    function setTokenMonetaryPolicy(address token, address monetaryPolicy) public onlyAdmin
    {
        _allowedTokenToMonetaryPolicy[token] = TokenMonetaryPolicy(monetaryPolicy);
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
        return beforeFee.mul(_standardFeeMultiplier).div(_feeDivisor);
    }

    /**
    * @notice Applies fee to send amount. The bigger fee, the shorter time to rebase left.
    */
    function applyRebaseAwareFee(uint256 beforeFee, uint256 timeLeft) internal view returns(uint256) {
        require(timeLeft != 0, "Cannot exchange tokens in 'to' token rebase window.");

        if (timeLeft >= 43200) { // left more than 12hrs to next rebase window.
            return applyFee(beforeFee); // standard fee
        } else if (timeLeft >= 21600) {  // more than 6hrs
            return beforeFee.mul(_multiplier6hr).div(_feeDivisor);
        } else if (timeLeft >= 3600) { // more than 1 hr
            return beforeFee.mul(_multiplier1hr).div(_feeDivisor);
        } else if (timeLeft >= 600) { // more than 10 min
            return beforeFee.mul(_multiplier10m).div(_feeDivisor);
        } else if (timeLeft >= 120) { // more than 2 min
            return beforeFee.mul(_multiplier2m).div(_feeDivisor);
        }
        // less than 2 min!
        return beforeFee.mul(_multiplierMadness).div(_feeDivisor);
    }

    /**
    * @notice Updates total supply if required.
    */
    function updateTotalSupply(bool force) internal {
        uint256 epoch = _mainMonetaryPolicy.epoch();
        if (force || epoch != _totalSupplyEpoch) {
            _tokensTotalSupply = sumTotalSupplyOfTokens();
            _totalSupplyEpoch = epoch;
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
    *  @notice Calculates amount of STAB received for particular amount of gov tokens for a total supply provided.
    */
    function getMintAmountForGov(uint256 startSupply, uint256 govAmount) internal view returns (uint256) {
        uint256 govValue = govAmount.mul(getGovPrice());
        uint256 stabRarity = startSupply.mul(UNIT).div(_tokensTotalSupply); // rarity parameter. When rarity > UNIT less STAB exists than gSTAB.
        uint256 stabAmount = govValue.div(stabRarity);
        return applyFee(stabAmount);
    }

    /**
    *  @notice Calculates amount of STAB received for particular amount of gov tokens for a current total supply.
    */
    function getMintAmountForGov(uint256 govAmount) public view returns (uint256) {
        return getMintAmountForGov(totalSupply(), govAmount);
    }

    /**
    * @notice _msgSender receives STAB token in exchange for gSTAB.
    */
    function mintStabForGov(Token token, uint256 govAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        uint256 startSupply = totalSupply();
        address sender = _msgSender();
        _burn(sender, govAmount); // Simulate transfer + burn in one step, but check allowance as for normal transfer.
        decreaseAllowance(address(this), govAmount);

        updateTotalSupply(false);

        uint256 tokenAmount = getMintAmountForGov(startSupply, govAmount);
        token.mint(sender, tokenAmount); // fee is burned (not minted) in that case.
        updateTotalSupply(true); // update token total supply as mint changes it.
    }

    /**
    *  @notice Calculates amount of GOV received for particular amount of STAB tokens.
    */
    function getMintAmountForStab(uint256 stabAmount) public view returns (uint256) {
        uint256 stabRarity = totalSupply().mul(UNIT).div(_tokensTotalSupply); // rarity parameter. When rarity > UNIT less STAB exists than gSTAB.
        uint256 stabValue = stabAmount.mul(stabRarity);
        uint256 govAmount = stabValue.div(getGovPrice());
        return applyFee(govAmount);
    }

    /**
    * @notice _msgSender receives gSTAB token in exchange for STAB.
    */
    function mintGovForStab(Token token, uint256 stabAmount) public {
        require(_allowedTokens[address(token)], "Token is not governed by this contract.");

        updateTotalSupply(false);

        token.transferFrom(_msgSender(), address(this), stabAmount);
        token.burnMyTokens(stabAmount);

        uint256 govAmount = getMintAmountForStab(stabAmount);
        _mint(_msgSender(), govAmount); // fee is burned (not minted) in that case.
        updateTotalSupply(true);
    }

    /**
    * @notice _msgSender receives gSTAB token in exchange for STAB.
    */
    function exchangeStabForStab(Token fromStab, Token toStab, uint256 fromAmount) public {
        require(_allowedTokens[address(fromStab)], "'from' token is not governed by this contract.");
        require(_allowedTokens[address(toStab)], "'to' token is not governed by this contract.");

        uint256 timeLeft = _allowedTokenToMonetaryPolicy[address(toStab)].getTimeLeftToRebaseWindow();
        uint256 afterFee = applyRebaseAwareFee(fromAmount, timeLeft);

        fromStab.transferFrom(_msgSender(), address(this), fromAmount);
        fromStab.burnMyTokens(afterFee); // keeps fee reduced by transfer fee (redistributed to stab holders).

        toStab.mint(_msgSender(), afterFee);
    }
}
