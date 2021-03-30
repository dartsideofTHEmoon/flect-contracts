// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../GovToken.sol";
import "../TokenMonetaryPolicy.sol";

contract GovTokenMock is GovToken {

    function getTotalSupplyEpochMock() public returns (uint256) {
        return _totalSupplyEpoch;
    }

    function getTokensTotalSupplyMock() public returns (uint256) {
        return _tokensTotalSupply;
    }

    function getMonetaryPolicyMock() public returns (TokenMonetaryPolicy) {
        return _monetaryPolicy;
    }
}
