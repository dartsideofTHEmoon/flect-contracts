const SafeMathUpgradeable = artifacts.require("./SafeMathUpgradeable.sol");
const McapOracle = artifacts.require("./Oracle.sol");

module.exports = async function(deployer, network) {
    console.log("Deploying MCAP oracle to", network);

    // Deploy all libraries to the network
    await deployer.deploy(SafeMathUpgradeable);

    // link Token
    await deployer.link(SafeMathUpgradeable, McapOracle);

    // deploy mcap Oracle
    const instance = await deployer.deploy(McapOracle);
    console.log('MCAP oracle deployed', instance.address);
};
