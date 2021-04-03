// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./utils/SafeMathInt.sol";
import "./utils/UInt256Lib.sol";
import "./utils/EnumerableFifo.sol";
import "./utils/Rebaseable.sol";
import "./ChainSwap.sol";


contract Token is Initializable, IERC20Upgradeable, RebaseableUpgradeable, ContextUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;
    using AddressUpgradeable for address;
    using EnumerableFifo for EnumerableFifo.U32ToU256Queue;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // I. Base ERC20 variables
    string private _name;
    string private _symbol;
    uint8 constant private _decimals = 9;

    // II. Variables responsible for counting balances and network shares
    uint256 private constant MAX = ~uint256(0) / (1 << 32); // Leave some space for UNIT to grow during rebases and funds migrations.
    uint256 private constant UNIT = 10 ** _decimals;
    uint256 private constant _initialTotalSupply = 5 * 10 ** 6 * UNIT;
    uint256 private _totalSupply; // = _initialTotalSupply;
    uint256 internal _reflectionTotal; // = MAX - (MAX % _totalSupply);
    uint256 internal constant _reflectionPerToken = (MAX - (MAX % _initialTotalSupply)) / _initialTotalSupply;
    // Fees since beginning of an epoch.
    uint256 private _transactionFeeEpoch; // = 0;

    // III. Variables responsible for keeping user account balances
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => EnumerableFifo.U32ToU256Queue) private _netShareOwned;
    mapping(address => uint256) private _tokenOwned;

    // IV. Variables responsible for keeping address 'types'
    EnumerableSetUpgradeable.AddressSet private _excluded;
    EnumerableSetUpgradeable.AddressSet private _included;

    // V. Special administrator variables
    mapping(address => bool) private _banned;
    bytes32 public constant MONETARY_POLICY_ROLE = keccak256("MONETARY_POLICY_ROLE"); // 0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); // 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE"); // 0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848

    // VI. User special incentives parameters.
    //TODO add ability to adjust it later.
    uint256 internal constant _maxIncentive = 3 * UNIT; // UNIT == no incentive, 2*UNIT = 100% bigger rebase.
    uint256 internal constant _decreasePerEpoch = UNIT / 100 * 2; // 0.1% * 2 = 0.02 each epoch => 100 days to get +2x
    // Epoch number.
    uint32 internal _epoch; // = 1;
    // How long transaction history to keep (in days).
    uint32 internal constant _maxHistoryLen = uint32((_maxIncentive - UNIT) / _decreasePerEpoch); // 2x / 0.02

    // VII. Others
    event Burned(address indexed from, uint256 amount);
    event Minted(address indexed from, uint256 amount);

    function initialize(string memory symbol_, string memory name_) public initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();

        _symbol = symbol_;
        _name = name_;

        //Set up variables
        _totalSupply = _initialTotalSupply;
        _reflectionTotal = MAX - (MAX % _totalSupply);
        _transactionFeeEpoch = 0;
        _epoch = 1;

        //Set up roles.
        address owner = _msgSender();
        _netShareOwned[owner].add(_epoch, _reflectionTotal);
        _included.add(owner);
        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MONETARY_POLICY_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
        _setupRole(BURNER_ROLE, owner);
        emit Transfer(address(0), owner, _initialTotalSupply);
    }

    // ----- Access control -----
    function requireAdmin() internal view {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only admins");
    }

    function requireMonetaryPolicy() internal view {
        require(hasRole(MONETARY_POLICY_ROLE, _msgSender()), "Only monetary policy");
    }

    modifier onlyAdmin() {
        requireAdmin();
        _;
    }

    modifier onlyMonetaryPolicy() {
        requireMonetaryPolicy();
        _;
    }

    modifier onlyMonetaryPolicyWithMintRole() {
        requireMonetaryPolicy();
        require(hasRole(MINTER_ROLE, _msgSender()), "Only minter");
        _;
    }

    modifier onlyMonetaryPolicyWithBurnRole() {
        requireMonetaryPolicy();
        require(hasRole(BURNER_ROLE, _msgSender()), "Only burner");
        _;
    }
    // ----- End access control -----

    // ----- Public erc20 view functions -----
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function epoch() public view returns (uint32) {
        return _epoch;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        if (_excluded.contains(account)) return _tokenOwned[account];
        return tokenFromReflection(_netShareOwned[account].getSum());
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    // ----- End of public erc20 view functions -----


    // ----- Public erc20 state modifiers -----
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "Exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "Below zero"));
        return true;
    }
    // ----- End of public erc20 state modifiers -----


    // ----- Public view functions for additional features -----
    function isExcluded(address account) external view returns (bool) {
        return _excluded.contains(account);
    }

    function isIncluded(address account) external view returns (bool) {
        return _included.contains(account);
    }

    function tokenFromReflection(uint256 reflectionAmount) public view returns (uint256) {
        uint256 currentRate = _getRate();
        return reflectionAmount.div(currentRate);
    }
    // ----- End of public view functions for additional features -----


    // ----- Public rebase state modifiers -----
    function rebase(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) external override onlyMonetaryPolicy returns (uint256) {
        if (targetRate == exchangeRate) {
            _finalizeRebase();
            return _totalSupply;
        }

        (uint32 maxIncentiveEpoch, uint256 currentNetMultiplier, uint256 maxFactor) = _getRebaseFactors(exchangeRate, targetRate, rebaseLag);

        uint256[4] memory valuesArray;
        valuesArray[0] = _getRate();
        valuesArray[1] = _getPostRebaseRate();
        valuesArray[2] = currentNetMultiplier;
        valuesArray[3] = UNIT;

        int256 supplyChange = 0;
        for (uint256 i = 0; i < _included.length(); i++) {
            int256 userSupplyChange = _netShareOwned[_included.at(i)].rebaseUserFunds(maxIncentiveEpoch, _decreasePerEpoch, maxFactor, valuesArray);
            supplyChange = supplyChange.add(userSupplyChange);
        }

        for (uint256 i = 0; i < _excluded.length(); i++) {
            uint256 owned = _tokenOwned[_excluded.at(i)];
            uint256 newOwned = EnumerableFifo.adjustValue(owned, UNIT, valuesArray, true);
            _tokenOwned[_excluded.at(i)] = newOwned;
            supplyChange = supplyChange.add(newOwned.toInt256Safe().sub(owned.toInt256Safe()));

            _netShareOwned[_excluded.at(i)].rebaseUserFunds(~uint32(0), 0, UNIT, valuesArray);
        }

        if (supplyChange >= 0) {
            _totalSupply = _totalSupply.add(uint256(supplyChange));
        } else {
            _totalSupply = _totalSupply.sub(uint256(- supplyChange));
        }

        _finalizeRebase();
        return _totalSupply;
    }
    // ----- End of rebase state modifiers -----

    // ----- Public monetary policy actions -----
    function mint(address owner, uint256 amount) external onlyMonetaryPolicyWithMintRole {
        if (!_included.contains(owner) && !_excluded.contains(owner)) {
            _included.add(owner);
        }
        uint256 amountFixed = amount.mul(_getRate());
        _reflectionTotal = _reflectionTotal.add(amountFixed);
        _netShareOwned[owner].add(_epoch, amountFixed);
        _netShareOwned[owner].flatten(_getMinEpoch());
        if (_excluded.contains(owner)) {
            _tokenOwned[owner] = tokenFromReflection(_netShareOwned[owner].getSum());
        }
        _totalSupply = _totalSupply.add(amount);

        emit Minted(owner, amount);
    }

    function _burn(address owner, uint256 amount) internal {
        uint256 amountFixed = amount.mul(_getRate());
        _reflectionTotal = _reflectionTotal.sub(amountFixed);
        _netShareOwned[owner].sub(amountFixed);
        uint256 leftFunds = _netShareOwned[owner].getSum();
        if (_excluded.contains(owner)) {
            _tokenOwned[owner] = tokenFromReflection(_netShareOwned[owner].getSum());
            if (leftFunds == 0) {
                _excluded.remove(owner);
            }
        } else if (leftFunds == 0) {
            _included.remove(owner);
        }

        _totalSupply = _totalSupply.sub(amount);

        emit Burned(owner, amount);
    }

    function burnMyTokens(uint256 amount) external {
        return _burn(_msgSender(), amount);
    }

    function burn(address owner, uint256 amount) external onlyMonetaryPolicyWithBurnRole {
        return _burn(owner, amount);
    }
    // ----- End of public monetary policy actions -----

    // ----- Administrator only functions (onlyAdmin) -----
    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function banUser(address user) external onlyAdmin {
        _banned[user] = true;
        if (!_excluded.contains(user)) {
            excludeAccount(user);
        }
    }

    function unbanUser(address user, bool includeUser) external onlyAdmin {
        delete _banned[user];
        if (includeUser) {
            includeAccount(user);
        }
    }

    function excludeAccount(address account) public onlyAdmin {
        require(!_excluded.contains(account), "Is excluded");
        uint256 reflectionOwned = _netShareOwned[account].getSum();
        if (reflectionOwned > 0) {
            _tokenOwned[account] = tokenFromReflection(reflectionOwned);
            _included.remove(account);
        }
        _excluded.add(account);
    }

    function includeAccount(address account) public onlyAdmin {
        require(_excluded.contains(account), "Isn't excluded");
        require(!_included.contains(account), "Is included");

        _included.add(account);
        _excluded.remove(account);
        _tokenOwned[account] = 0;
    }
    // ----- End of administrator part -----

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0) && spender != address(0), "Zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private whenNotPaused {
        require(sender != address(0) && recipient != address(0), "Zero address");
        require(amount > 0, "Amount zero");
        require(!_banned[sender], "User banned");

        bool senderExcluded = _excluded.contains(sender);
        bool recipientExcluded = _excluded.contains(recipient);

        if (senderExcluded) {
            if (recipientExcluded) {
                _transferBothExcluded(sender, recipient, amount);
            } else {
                _transferFromExcluded(sender, recipient, amount);
                _included.add(recipient);
            }

            if (_tokenOwned[sender] == 0) {
                _excluded.remove(sender);
                delete _tokenOwned[sender];
            }
        } else {
            if (recipientExcluded) {
                _transferToExcluded(sender, recipient, amount);
            } else {
                _transferStandard(sender, recipient, amount);
                _included.add(recipient);
            }

            if (_netShareOwned[sender].getSum() == 0) {
                _included.remove(sender);
                delete _netShareOwned[sender];
            } else {
                _netShareOwned[sender].flatten(_getMinEpoch());
            }
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, bool wipeSenderAmount) = _getValues(tAmount, sender);
        if (wipeSenderAmount) {
            _netShareOwned[sender].sub(_netShareOwned[sender].getSum());
        } else {
            _netShareOwned[sender].sub(rAmount);
        }
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, bool wipeSenderAmount) = _getValues(tAmount, sender);
        if (wipeSenderAmount) {
            _netShareOwned[sender].sub(_netShareOwned[sender].getSum());
        } else {
            _netShareOwned[sender].sub(rAmount);
        }
        _tokenOwned[recipient] = _tokenOwned[recipient].add(tTransferAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee,) = _getValues(tAmount, sender);
        _tokenOwned[sender] = _tokenOwned[sender].sub(tAmount);
        _netShareOwned[sender].sub(rAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee,) = _getValues(tAmount, sender);
        _tokenOwned[sender] = _tokenOwned[sender].sub(tAmount);
        _netShareOwned[sender].sub(rAmount);
        _tokenOwned[recipient] = _tokenOwned[recipient].add(tTransferAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _reflectionTotal = _reflectionTotal.sub(rFee);
        _transactionFeeEpoch = _transactionFeeEpoch.add(tFee);
    }

    function _getValues(uint256 tAmount, address sender) private view returns (uint256, uint256, uint256, uint256, uint256, bool) {
        (uint256 tTransferAmount, uint256 tFee) = _getValuesInToken(tAmount);
        uint256 currentRate = _getRate();

        uint256 additionalFee = 0;
        if (_included.contains(sender)) {
            uint256 tokenRef = _netShareOwned[sender].getSum();
            uint256 tokenFunds = tokenRef.div(currentRate).sub(tAmount);
            if (tokenFunds < UNIT) {
                additionalFee = tokenFunds;
            }
        }
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, additionalFee, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, additionalFee != 0);
    }

    function _getValuesInToken(uint256 tAmount) private pure returns (uint256, uint256) {
        uint256 tFee = tAmount.div(500);
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tFeeAdditional, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee);
        return (rAmount, rTransferAmount, rFee.add(tFeeAdditional.mul(currentRate)));
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply(_reflectionTotal);
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply(uint256 reflectionTotal_) private view returns (uint256, uint256) {
        uint256 rSupply = reflectionTotal_;
        uint256 tSupply = _totalSupply;
        for (uint256 i = 0; i < _excluded.length(); i++) {
            if (_netShareOwned[_excluded.at(i)].getSum() > rSupply || _tokenOwned[_excluded.at(i)] > tSupply) return (reflectionTotal_, _totalSupply);
            rSupply = rSupply.sub(_netShareOwned[_excluded.at(i)].getSum());
            tSupply = tSupply.sub(_tokenOwned[_excluded.at(i)]);
        }
        if (rSupply < reflectionTotal_.div(_totalSupply)) return (reflectionTotal_, _totalSupply);
        return (rSupply, tSupply);
    }

    function _getMinEpoch() internal view returns (uint32) {
        if (_epoch <= _maxHistoryLen) {
            return 1;
            // Epoch counts from 1.
        } else {
            return _epoch - _maxHistoryLen;
        }
    }

    // ----- Private rebase state modifiers -----
    function _getRebaseFactors(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) internal view returns (uint32, uint256, uint256) {
        // 1. minEpoch
        uint32 minEpoch = _getMinEpoch();

        // 2. currentNetMultiplier
        int256 targetRateSigned = targetRate.toInt256Safe();
        // (exchangeRate - targetRate) / targetRate => multiplier in <-UNIT, UNIT> range.
        int256 rebaseDelta = UNIT.toInt256Safe().mul(exchangeRate.toInt256Safe().sub(targetRateSigned)).div(targetRateSigned);
        // Apply the Dampening factor and construct multiplier.

        require(rebaseLag != 0);
        uint256 currentNetMultiplier = 0;
        if (rebaseLag > 0) {
            currentNetMultiplier = uint256(UNIT.toInt256Safe().add(rebaseDelta.div(rebaseLag)));
        } else {
            currentNetMultiplier = uint256(UNIT.toInt256Safe().sub(rebaseDelta.mul(rebaseLag))); // sub negative number = add
        }

        // 3. maxFactor
        require(_epoch >= minEpoch);
        uint32 epochsFromMin = _epoch - minEpoch;
        uint256 maxFactor = UNIT.add(_decreasePerEpoch.mul(epochsFromMin));

        return (minEpoch, currentNetMultiplier, maxFactor);
    }

    function _finalizeRebase() internal {
        emit LogRebase(_epoch, _totalSupply, _transactionFeeEpoch);
        ++_epoch;
        _transactionFeeEpoch = 0;

        _reflectionTotal = _totalSupply.mul(_reflectionPerToken);
    }

    function _getPostRebaseRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply(_totalSupply.mul(_reflectionPerToken));
        return rSupply.div(tSupply);
    }
    // ----- End of private rebase state modifiers -----
}
