// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../GovToken.sol";
import "../TokenMonetaryPolicy.sol";

contract GovTokenMock is GovToken {

    function getTotalSupplyEpochMock() public view returns (uint256) {
        return _totalSupplyEpoch;
    }

    function getTokensTotalSupplyMock() public view returns (uint256) {
        return _tokensTotalSupply;
    }

    function getMonetaryPolicyMock() public view returns (TokenMonetaryPolicy) {
        return _monetaryPolicy;
    }

    function getFeeParamsMock() public view returns(uint256, uint256) {
        return (_feeMultiplier, _feeDivisor);
    }
}
