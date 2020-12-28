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
import "./utils/EnumerableFifo.sol";

contract Token is Context, IERC20, Ownable, Pausable {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableFifo for EnumerableFifo.U32ToU256Queue;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Base ERC20 variables
    string constant private _name = 'stableflect.finance';
    string constant private _symbol = 'STAB';
    uint8 constant private _decimals = 9;

    // Variables responsible for counting balances and network shares
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant UNIT = 10**_decimals;
    uint256 private constant _initialTotalSupply = 5 * 10**6 * UNIT;
    uint256 private constant _initialReflectionSupply = (MAX - (MAX % _initialTotalSupply));
    uint256 private _totalSupply = _initialTotalSupply;
    uint256 private _reflectionTotal = _initialReflectionSupply;
    uint256 private _transactionFeeEpoch = 0;
    uint32 private _epoch = 1;

    // Variables responsible for keeping user account balances
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => EnumerableFifo.U32ToU256Queue) private _netShareOwned;
    mapping (address => uint256) private _tokenOwned;

    // Variables responsible for keeping address 'types'
    EnumerableSet.AddressSet private _excluded;
    EnumerableSet.AddressSet private _included;

    // Special administrator variables
    mapping (address => bool) private _banned;

    constructor () public {
        _netShareOwned[_msgSender()].add(_epoch, _initialReflectionSupply);
        _included.add(_msgSender());
        emit Transfer(address(0), _msgSender(), _initialTotalSupply);
    }

    // ----- Public erc20 view functions -----
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function epoch() public view returns (uint32) {
        return _epoch;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _netShareOwned[_msgSender()].getSum();
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

    // ----- Administrator only functions (onlyOwner) -----
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function banUser(address user) public onlyOwner {
        _banned[user] = true;
    }

    function unbanUser(address user) public onlyOwner {
        delete _banned[user];
    }
    // ----- End of administrator part -----

    function _calcMaxReflection(uint256 totalSupply) private {
        _reflectionTotal = (MAX - (MAX % totalSupply));
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

        bool senderExcluded = _excluded.contains(sender);
        bool recipientExcluded = _excluded.contains(recipient);

        if (!senderExcluded && !recipientExcluded) {
            _transferStandard(sender, recipient, amount);
        } else if (!senderExcluded && recipientExcluded) {
            _transferToExcluded(sender, recipient, amount);
        } else if (senderExcluded && !recipientExcluded) {
            _transferFromExcluded(sender, recipient, amount);
        } else {
            _transferBothExcluded(sender, recipient, amount);
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
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _reflectionTotal;
        uint256 tSupply = _totalSupply;
        for (uint256 i = 0; i < _excluded.length(); i++) {
            if (_netShareOwned[_excluded.at(i)].getSum() > rSupply || _tokenOwned[_excluded.at(i)] > tSupply) return (_reflectionTotal, _totalSupply);
            rSupply = rSupply.sub(_netShareOwned[_excluded.at(i)].getSum());
            tSupply = tSupply.sub(_tokenOwned[_excluded.at(i)]);
        }
        if (rSupply < _reflectionTotal.div(_totalSupply)) return (_reflectionTotal, _totalSupply);
        return (rSupply, tSupply);
    }
}
