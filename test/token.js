const BN = require("bn.js");

const Token = artifacts.require("./Token.sol");
require('chai')
    .use(require('chai-bn')(BN))
    .should();


const DECIMALS = 9;
const INTIAL_SUPPLY = toUFrgDenomination(5 * 10 ** 6);
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

function toUFrgDenomination (x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

contract("Token:Initialization", (accounts) => {
    let instance, deployer;
    beforeEach('Sets up contract instance', async () => {
        instance = await Token.new();
        deployer = accounts[0];
    });

    it('should transfer 5M tokens to the deployer', async function () {
        (await instance.balanceOf.call(deployer)).should.be.bignumber.eq(INTIAL_SUPPLY);
        const events = await instance.getPastEvents();
        console.log(events);
        const log = events[1];  // First one is OwnershipTransferred from 'Ownable'
        expect(log.event).to.eq('Transfer');
        expect(log.args.from).to.eq(ZERO_ADDRESS);
        expect(log.args.to).to.eq(deployer);
        log.args.value.should.be.bignumber.eq(INTIAL_SUPPLY);
    });

    it('should set the owner', async function () {
        expect(await instance.owner.call()).to.eq(deployer);
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

    it('should have epoch set to 1', async () => {
        (await instance.epoch.call()).eq(1);
    });

    it('should set initial supply', async() => {
        (await instance.totalSupply.call()).should.bignumber.eq(INTIAL_SUPPLY);
    });

});
