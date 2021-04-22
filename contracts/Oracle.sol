// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol"; // Use exactly the same version of math lib as Token.

import "./IOracle.sol";

contract Oracle is IOracle, AccessControl {
    using SafeMathUpgradeable for uint256;

    uint256 private constant DECIMALS = 9;
    uint256 private constant UNIT = 10 ** DECIMALS;

    uint256[24] private pastData;
    uint8 private dataIndex;

    bytes32 public constant ORACLE_UPDATER = keccak256("ORACLE_UPDATER"); // 0x44b95bb537aef5ad632cef9503788828b27f44285a867eeb813406ad80ee3748

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ORACLE_UPDATER, _msgSender());
    }

    modifier onlyOracleUpdater() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only admins");
        _;
    }

    function addNewData(uint256 newData) external onlyOracleUpdater {
        pastData[dataIndex] = newData;
        dataIndex = (dataIndex + 1) % pastData.length;
    }

    function getData() external override view returns (uint256, bool) {
        return (calculateAverage(), true);
    }

    function calculateAverage() internal view returns(uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < pastData.length; i++) {
            sum = sum.add(pastData[i]);
        }
        return sum.div(pastData.length);
    }
}
