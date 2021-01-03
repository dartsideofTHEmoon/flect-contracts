pragma solidity >=0.6.0 <0.8.0;

import "../Token.sol";

contract TokenMock is Token {

    function _getRebaseFactorsMock(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) public view returns(uint32, uint256, uint256) {
        return Token._getRebaseFactors(exchangeRate, targetRate, rebaseLag);
    }
}
