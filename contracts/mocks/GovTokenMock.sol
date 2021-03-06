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

    function setTokensTotalSupplyMock(uint256 tokensTotalSupply_) public {
        _tokensTotalSupply = tokensTotalSupply_;
    }

    function getMainMonetaryPolicyMock() public view returns (TokenMonetaryPolicy) {
        return _mainMonetaryPolicy;
    }

    function getFeeParamsMock() public view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (_standardFeeMultiplier, _multiplier6hr, _multiplier1hr, _multiplier10m, _multiplier2m,
                _multiplierMadness, _feeDivisor);
    }
}
