// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "../Token.sol";

contract TokenMock is Token {

    function _getRebaseFactorsMock(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) public pure returns (uint256) {
        return Token._getRebaseFactors(exchangeRate, targetRate, rebaseLag);
    }

    function _getDecreasePerEpochMock() public pure returns (uint256) {
        return _decreasePerEpoch;
    }

    function _getMaxHistoryLenMock() public pure returns (uint32) {
        return _maxHistoryLen;
    }

    function _getMaxIncentiveMock() public pure returns (uint256) {
        return _maxIncentive;
    }

    function _getReflectionTotalMock() public view returns (uint256) {
        return _reflectionTotal;
    }

    function _setEpochMock(uint32 newEpoch) public {
        _epoch = newEpoch;
    }
}
