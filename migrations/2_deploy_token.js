const SafeMathUpgradeable = artifacts.require("./SafeMathUpgradeable.sol");
const SafeMathInt = artifacts.require("./SafeMathInt.sol");
const UInt256Lib = artifacts.require("./UInt256Lib.sol");
const EnumerableFifo = artifacts.require("./EnumerableFifo.sol");
const AddressUpgradeable = artifacts.require("./AddressUpgradeable.sol")
const EnumerableSetUpgradeable = artifacts.require("./EnumerableSetUpgradeable.sol")
const Token = artifacts.require("./Token.sol");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

// JavaScript export
module.exports = async function(deployer) {
    // Deploy all libraries to the network
    await deployer.deploy(SafeMathUpgradeable);
    await deployer.deploy(SafeMathInt);
    await deployer.deploy(UInt256Lib);
    await deployer.deploy(EnumerableFifo);
    await deployer.deploy(AddressUpgradeable);
    await deployer.deploy(EnumerableSetUpgradeable);

    await deployer.link(SafeMathUpgradeable, EnumerableFifo);
    await deployer.link(SafeMathInt, EnumerableFifo);
    await deployer.link(UInt256Lib, EnumerableFifo);

    await deployer.link(EnumerableFifo, Token);
    await deployer.link(SafeMathUpgradeable, Token);
    await deployer.link(SafeMathInt, Token);
    await deployer.link(UInt256Lib, Token);
    await deployer.link(AddressUpgradeable, Token);
    await deployer.link(EnumerableSetUpgradeable, Token);

    const tokenInstance = await deployProxy(Token, [], {deployer, unsafeAllowLinkedLibraries: true});
    console.log('Token deployed', tokenInstance.address);
};
