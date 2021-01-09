// SPDX-License-Identifier:
/*
 *
 */

pragma solidity >=0.6.0 <0.8.0;

import "openzeppelin-solidity/contracts/GSN/Context.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";
import "openzeppelin-solidity/contracts/utils/EnumerableSet.sol";
import "openzeppelin-solidity/contracts/utils/Pausable.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./utils/SafeMathInt.sol";
import "./utils/UInt256Lib.sol";
import "./utils/EnumerableFifo.sol";
import "./utils/Rebaseable.sol";

contract Token is Context, IERC20, Ownable, Pausable, Rebaseable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;
    using Address for address;
    using EnumerableFifo for EnumerableFifo.U32ToU256Queue;
    using EnumerableSet for EnumerableSet.AddressSet;

    // I. Base ERC20 variables
    string constant private _name = 'stableflect.finance';
    string constant private _symbol = 'STAB';
    uint8 constant private _decimals = 9;

    // II. Variables responsible for counting balances and network shares
    uint256 private constant MAX = ~uint256(0) / (1 << 32); // Leave some space for UNIT to grow during rebases and funds migrations.
    uint256 private constant UNIT = 10**_decimals;
    uint256 private constant _initialTotalSupply = 5 * 10**6 * UNIT;
    uint256 private _totalSupply = _initialTotalSupply;
    uint256 internal _reflectionTotal = MAX - (MAX % _totalSupply);
    uint256 internal constant _reflectionPerToken = (MAX - (MAX % _initialTotalSupply)) / _initialTotalSupply;
    // Fees since beginning of an epoch.
    uint256 private _transactionFeeEpoch = 0;

    // III. Variables responsible for keeping user account balances
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => EnumerableFifo.U32ToU256Queue) private _netShareOwned;
    mapping (address => uint256) private _tokenOwned;

    // IV. Variables responsible for keeping address 'types'
    EnumerableSet.AddressSet private _excluded;
    EnumerableSet.AddressSet private _included;

    // V. Special administrator variables
    mapping (address => bool) private _banned;

    constructor () public {
        _netShareOwned[_msgSender()].add(_epoch, _reflectionTotal);
        _included.add(_msgSender());
        emit Transfer(address(0), _msgSender(), _initialTotalSupply);
    }

    // VI. User special incentives parameters.
    //TODO add ability to adjust it later.
    uint256 internal constant _maxIncentive = 3 * UNIT; // UNIT == no incentive, 2*UNIT = 100% bigger rebase.
    uint256 internal constant _decreasePerEpoch = UNIT / 100 * 2; // 0.1% * 2 = 0.02 each epoch => 100 days to get +2x
    // Epoch number.
    uint32 internal _epoch = 1;
    // How long transaction history to keep (in days).
    uint32 internal constant _maxHistoryLen = uint32((_maxIncentive - UNIT) / _decreasePerEpoch); // 2x / 0.02


    // ----- Public erc20 view functions -----
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
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

    function balanceOf(address account) public view override returns (uint256) {
        if (_excluded.contains(account)) return _tokenOwned[account];
        return tokenFromReflection(_netShareOwned[account].getSum());
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    // ----- End of public erc20 view functions -----


    // ----- Public erc20 state modifiers -----
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    // ----- End of public erc20 state modifiers -----


    // ----- Public view functions for additional features -----
    function isExcluded(address account) public view returns (bool) {
        return _excluded.contains(account);
    }

    function isIncluded(address account) public view returns (bool) {
        return _included.contains(account);
    }

    function tokenFromReflection(uint256 reflectionAmount) public view returns(uint256) {
        uint256 currentRate =  _getRate();
        return reflectionAmount.div(currentRate);
    }
    // ----- End of public view functions for additional features -----


    // ----- Public rebase state modifiers -----
    function setMonetaryPolicy(address monetaryPolicy_) external onlyOwner {
        _setMonetaryPolicy(monetaryPolicy_);
    }

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

        if (supplyChange >= 0) {
            _totalSupply = _totalSupply.add(uint256(supplyChange));
        } else {
            _totalSupply = _totalSupply.sub(uint256(-supplyChange));
        }

        _finalizeRebase();
        return _totalSupply;
    }
    // ----- End of rebase state modifiers -----


    // ----- Administrator only functions (onlyOwner) -----
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function banUser(address user) public onlyOwner {
        _banned[user] = true;
        if (!_excluded.contains(user)) {
            excludeAccount(user);
        }
    }

    function unbanUser(address user, bool includeUser) public onlyOwner {
        delete _banned[user];
        if (includeUser) {
            includeAccount(user);
        }
    }

    function excludeAccount(address account) public onlyOwner {
        require(!_excluded.contains(account), "Account is already excluded");
        uint256 reflectionOwned = _netShareOwned[account].getSum();
        if(reflectionOwned > 0) {
            _tokenOwned[account] = tokenFromReflection(reflectionOwned);
            _included.remove(account);
        }
        _excluded.add(account);
    }

    function includeAccount(address account) public onlyOwner {
        require(_excluded.contains(account), "Account isn't excluded");
        require(!_included.contains(account), "Account is already included");

        _included.add(account);
        _excluded.remove(account);
        _tokenOwned[account] = 0;
    }
    // ----- End of administrator part -----

    function _calcMaxReflection(uint256 totalSupply_) private view returns (uint256){
        return totalSupply_ * _reflectionPerToken;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private whenNotPaused {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
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
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _netShareOwned[sender].sub(rAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _netShareOwned[sender].sub(rAmount);
        _tokenOwned[recipient] = _tokenOwned[recipient].add(tTransferAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _tokenOwned[sender] = _tokenOwned[sender].sub(tAmount);
        _netShareOwned[sender].sub(rAmount);
        _netShareOwned[recipient].add(_epoch, rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
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

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee) = _getValuesInToken(tAmount);
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee);
    }

    function _getValuesInToken(uint256 tAmount) private pure returns (uint256, uint256) {
        uint256 tFee = tAmount.div(500);
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply(_reflectionTotal);
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply(uint256 reflectionTotal_) private view returns(uint256, uint256) {
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

    function _getMinEpoch() internal view returns(uint32) {
        if (_epoch <= _maxHistoryLen) {
            return 1; // Epoch counts from 1.
        } else {
            return _epoch - _maxHistoryLen;
        }
    }

    // ----- Private rebase state modifiers -----
    function _getRebaseFactors(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) internal view returns(uint32, uint256, uint256) {
        // 1. minEpoch
        uint32 minEpoch = _getMinEpoch();

        // 2. currentNetMultiplier
        int256 targetRateSigned = targetRate.toInt256Safe();
        // (exchangeRate - targetRate) / targetRate => multiplier in <-UNIT, UNIT> range.
        int256 rebaseDelta = UNIT.toInt256Safe().mul(exchangeRate.toInt256Safe().sub(targetRateSigned)).div(targetRateSigned);
        // Apply the Dampening factor and construct multiplier.

        require(rebaseLag > 0); //TODO this actually can be lower, but need to be implemented. When this factor is lower treat it as leverage.
        uint256 currentNetMultiplier = uint256(UNIT.toInt256Safe().add(rebaseDelta.div(rebaseLag)));

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
        _reflectionTotal = _calcMaxReflection(_totalSupply);
    }

    function _getPostRebaseRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply(_calcMaxReflection(_totalSupply));
        return rSupply.div(tSupply);
    }
    // ----- End of private rebase state modifiers -----
}
