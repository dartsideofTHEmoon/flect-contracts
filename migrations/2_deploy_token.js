const SafeMathUpgradeable = artifacts.require("./SafeMathUpgradeable.sol");
const SafeMathInt = artifacts.require("./SafeMathInt.sol");
const UInt256Lib = artifacts.require("./UInt256Lib.sol");
const EnumerableFifo = artifacts.require("./EnumerableFifo.sol");
const AddressUpgradeable = artifacts.require("./AddressUpgradeable.sol");
const EnumerableSetUpgradeable = artifacts.require("./EnumerableSetUpgradeable.sol");
const ECDSA = artifacts.require("./ECDSA.sol");
const Token = artifacts.require("./Token.sol");
const ChainSwap = artifacts.require("./ChainSwap.sol");
const TokenMonetaryPolicy = artifacts.require("./TokenMonetaryPolicy.sol");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const BN = require("bn.js");
const UNIT = new BN(1).mul(new BN(10 ** 9));

function networkToChainName(network) {
    switch (network) {
        case "BinanceSmartChainMain":
            return "BSC";
        case "BinanceSmartChainTest":
            return "TBSC";
        default:
            return "DEV";
    }
}

// JavaScript export
module.exports = async function(deployer, network) {
    console.log("Deploying to", network);

    // Deploy all libraries to the network
    await deployer.deploy(SafeMathUpgradeable);
    await deployer.deploy(SafeMathInt);
    await deployer.deploy(UInt256Lib);
    await deployer.deploy(EnumerableFifo);
    await deployer.deploy(AddressUpgradeable);
    await deployer.deploy(EnumerableSetUpgradeable);
    await deployer.deploy(ECDSA);

    await deployer.link(SafeMathUpgradeable, EnumerableFifo);
    await deployer.link(SafeMathInt, EnumerableFifo);
    await deployer.link(UInt256Lib, EnumerableFifo);

    await deployer.link(EnumerableFifo, Token);
    await deployer.link(SafeMathUpgradeable, Token);
    await deployer.link(SafeMathInt, Token);
    await deployer.link(UInt256Lib, Token);
    await deployer.link(AddressUpgradeable, Token);
    await deployer.link(EnumerableSetUpgradeable, Token);

    const tokenInstance = await deployProxy(Token, ['STAB', 'stableflect.finance'], {deployer, unsafeAllowLinkedLibraries: true});
    const tokenRevInstance = await deployProxy(Token, ['rSTAB', 'revert.stableflect.finance'], {deployer, unsafeAllowLinkedLibraries: true});

    // ChainSwap.sol
    await deployer.link(SafeMathUpgradeable, ChainSwap);
    await deployer.link(ECDSA, ChainSwap);
    // TokenMonetaryPolicy.sol
    await deployer.link(SafeMathUpgradeable, TokenMonetaryPolicy);
    await deployer.link(SafeMathInt, TokenMonetaryPolicy);
    await deployer.link(UInt256Lib, TokenMonetaryPolicy);

    const monetaryPolicyInstance = await deployer.deploy(TokenMonetaryPolicy,
        tokenInstance.address, tokenRevInstance.address, UNIT.mul(new BN(1450000)), networkToChainName(network));

    await tokenInstance.grantRole(Token.MONETARY_POLICY_ROLE(), monetaryPolicyInstance.address);
    await tokenInstance.grantRole(Token.MINTER_ROLE(), monetaryPolicyInstance.address);
    await tokenInstance.grantRole(Token.BURNER_ROLE(), monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole(Token.MONETARY_POLICY_ROLE(), monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole(Token.MINTER_ROLE(), monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole(Token.BURNER_ROLE(), monetaryPolicyInstance.address);

    console.log('Token STAB deployed', tokenInstance.address);
    console.log('Token rSTAB deployed', tokenRevInstance.address);
    console.log('Monetary Policy deployed', monetaryPolicyInstance.address);
};
