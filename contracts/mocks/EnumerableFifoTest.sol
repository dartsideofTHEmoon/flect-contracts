// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
import "../utils/EnumerableFifo.sol";

contract EnumerableFifoTest {
    using EnumerableFifo for EnumerableFifo.U32ToU256Queue;

    uint32 public epoch = 1;
    EnumerableFifo.U32ToU256Queue internal userBalance;

    function getSum() public view returns (uint256) {
        return userBalance.getSum();
    }

    function add(uint256 value) public {
        userBalance.add(epoch, value);
    }

    function sub(uint256 value) public {
        userBalance.sub(value);
    }

    function flatten(uint32 minAllowedKey) public {
        userBalance.flatten(minAllowedKey);
    }

    function rebaseUserFunds(uint32 maxIncentiveEpoch, uint256 factorDecreasePerEpoch,
        uint256 maxFactor, uint256[4] memory valuesArray) public returns (int256) {
        return userBalance.rebaseUserFunds(maxIncentiveEpoch, factorDecreasePerEpoch, maxFactor, valuesArray);
    }

    function adjustValue(uint256 value, uint256 userIncentiveFactor, uint256[4] memory valuesArray, bool excluded) public pure returns (uint256) {
        return EnumerableFifo.adjustValue(value, userIncentiveFactor, valuesArray, excluded);
    }
}
