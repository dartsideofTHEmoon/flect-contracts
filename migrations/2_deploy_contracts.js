const Token = artifacts.require("./Token.sol");

// JavaScript export
module.exports = function(deployer) {
    // Deploy the contract to the network
    deployer.deploy(Token)
        .then(() => {Token.deployed()});
};
