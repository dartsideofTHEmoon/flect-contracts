const BN = require("bn.js");
const UNIT = new BN(1).mul(new BN(10 ** 9));

const SafeMathUpgradeable = artifacts.require("./SafeMathUpgradeable.sol");
const ECDSA = artifacts.require("./ECDSA.sol");
const SafeMathInt = artifacts.require("./SafeMathInt.sol");
const UInt256Lib = artifacts.require("./UInt256Lib.sol");
const Token = artifacts.require("./Token.sol");
const ChainSwap = artifacts.require("./ChainSwap.sol");
const TokenMonetaryPolicy = artifacts.require("./TokenMonetaryPolicy.sol")

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
    await deployer.deploy(ECDSA);

    // ChainSwap.sol
    await deployer.link(SafeMathUpgradeable, ChainSwap);
    await deployer.link(ECDSA, ChainSwap);
    // TokenMonetaryPolicy.sol
    await deployer.link(SafeMathUpgradeable, TokenMonetaryPolicy);
    await deployer.link(SafeMathInt, TokenMonetaryPolicy);
    await deployer.link(UInt256Lib, TokenMonetaryPolicy);

    const monetaryPolicyInstance = await deployer.deploy(TokenMonetaryPolicy,
        Token.address, UNIT.mul(new BN(1450000)), networkToChainName(network));
    console.log('Monetary Policy deployed', monetaryPolicyInstance.address);
};
