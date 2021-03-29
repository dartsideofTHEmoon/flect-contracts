// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface IOracle {
    function getData() external view returns (uint256, bool);
}
