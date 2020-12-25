const BN = require("bn.js");

const Token = artifacts.require("./Token.sol");
require('chai')
    .use(require('chai-bn')(BN))
    .should();


const DECIMALS = 9;
const INTIAL_SUPPLY = toUFrgDenomination(5 * 10 ** 6);

function toUFrgDenomination (x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

contract("Token:Initialization", (accounts) => {
    let instance;
    beforeEach('Sets up contract instance', async () => {
        instance = await Token.deployed({from: accounts[0]});
    });

    it('should set the owner', async function () {
        expect(await instance.owner.call()).to.eq(accounts[0]);
    });

    it('should have correct name name', async () => {
        expect(await instance.name.call()).to.eq('stableflect.finance');
    });

    it('should have correct ticker', async () => {
        expect(await instance.symbol.call()).to.eq('STAB');
    });

    it('should have correct decimals', async () => {
        const decimals = await instance.decimals();
        assert.equal(decimals, DECIMALS);
    });

    it('should set initial supply', async() => {
        (await instance.totalSupply.call()).should.bignumber.eq(INTIAL_SUPPLY);
    });

});
