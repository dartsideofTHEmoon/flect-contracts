const SafeMathUpgradeable = artifacts.require("./SafeMathUpgradeable.sol");
const SafeMathInt = artifacts.require("./SafeMathInt.sol");
const UInt256Lib = artifacts.require("./UInt256Lib.sol");
const EnumerableFifo = artifacts.require("./EnumerableFifo.sol");
const AddressUpgradeable = artifacts.require("./AddressUpgradeable.sol");
const EnumerableSetUpgradeable = artifacts.require("./EnumerableSetUpgradeable.sol");
const ECDSA = artifacts.require("./ECDSA.sol");
const Token = artifacts.require("./Token.sol");
const ChainSwap = artifacts.require("./ChainSwap.sol");
const GovToken = artifacts.require("./GovToken.sol");
const TokenMonetaryPolicy = artifacts.require("./TokenMonetaryPolicy.sol");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');

const BN = require("bn.js");
const UNIT = new BN(1).mul(new BN(10 ** 9));

function networkToChainName(network) {
    switch (network) {
        case "bsc":
            return "BSC";
        case "bsc_test":
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

    // link EnumerableFifo
    await deployer.link(SafeMathUpgradeable, EnumerableFifo);
    await deployer.link(SafeMathInt, EnumerableFifo);
    await deployer.link(UInt256Lib, EnumerableFifo);

    // link Token
    await deployer.link(EnumerableFifo, Token);
    await deployer.link(SafeMathUpgradeable, Token);
    await deployer.link(SafeMathInt, Token);
    await deployer.link(UInt256Lib, Token);
    await deployer.link(AddressUpgradeable, Token);
    await deployer.link(EnumerableSetUpgradeable, Token);

    // deploy Tokens
    const tokenInstance = await deployProxy(Token, ['STAB', 'stableflect.finance'], {deployer, unsafeAllowLinkedLibraries: true});
    const tokenRevInstance = await deployProxy(Token, ['rSTAB', 'revert.stableflect.finance'], {deployer, unsafeAllowLinkedLibraries: true});
    console.log('Token STAB deployed', tokenInstance.address);
    console.log('Token rSTAB deployed', tokenRevInstance.address);

    // link ChainSwap.sol
    await deployer.link(SafeMathUpgradeable, ChainSwap);
    await deployer.link(ECDSA, ChainSwap);

    // link TokenMonetaryPolicy.sol
    await deployer.link(SafeMathUpgradeable, TokenMonetaryPolicy);
    await deployer.link(SafeMathInt, TokenMonetaryPolicy);
    await deployer.link(UInt256Lib, TokenMonetaryPolicy);

    // deploy monetary policy
    const monetaryPolicyInstance = await deployer.deploy(TokenMonetaryPolicy,
        tokenInstance.address, tokenRevInstance.address, UNIT.mul(new BN(1450000)), networkToChainName(network));
    console.log('Monetary Policy deployed', monetaryPolicyInstance.address);

    // set up monetary policy roles for tokens
    await tokenInstance.grantRole("0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3", monetaryPolicyInstance.address);
    await tokenInstance.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", monetaryPolicyInstance.address);
    await tokenInstance.grantRole("0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848", monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole("0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3", monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", monetaryPolicyInstance.address);
    await tokenRevInstance.grantRole("0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848", monetaryPolicyInstance.address);

    // link GovToken
    await deployer.link(SafeMathUpgradeable, GovToken);
    await deployer.link(EnumerableSetUpgradeable, GovToken);

    // deploy GovToken
    const govTokenInstance = await deployer.deploy(GovToken, monetaryPolicyInstance.address,
        [tokenInstance.address, tokenRevInstance.address]);
    console.log('Governance token deployer', govTokenInstance.address);

    // set up governance token roles for tokens
    await tokenInstance.grantRole("0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3", govTokenInstance.address);
    await tokenInstance.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", govTokenInstance.address);
    await tokenInstance.grantRole("0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848", govTokenInstance.address);
    await tokenRevInstance.grantRole("0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3", govTokenInstance.address);
    await tokenRevInstance.grantRole("0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6", govTokenInstance.address);
    await tokenRevInstance.grantRole("0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848", govTokenInstance.address);
};
