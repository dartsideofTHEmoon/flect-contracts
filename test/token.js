const BN = require("bn.js");
const { accounts, contract } = require('@openzeppelin/test-environment');
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const Token = contract.fromArtifact("Token");

require('chai').should();
require('chai')
    .use(require('chai-bn')(BN))
    .should();


const DECIMALS = 9;
const INTIAL_SUPPLY = toUnitsDenomination(5 * 10 ** 6);
const MAX_UINT256 = new BN(2).pow(new BN(255));
const INITIAL_REFLECTION = MAX_UINT256.sub(MAX_UINT256.umod(INTIAL_SUPPLY));
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

function toUnitsDenomination (x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

async function BeforeEach() {
    const [deployer, receiver] = accounts;
    const instance = await Token.new({from: deployer});

    return [instance, deployer, receiver];
}

describe('Initialization', async () => {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should transfer 5M tokens to the deployer', async () => {
        (await this.instance.balanceOf.call(this.deployer)).should.be.bignumber.eq(INTIAL_SUPPLY);
        const events = await this.instance.getPastEvents();
        const log = events[1];  // First one is OwnershipTransferred from 'Ownable'
        expect(log.event).to.eq('Transfer');
        expect(log.args.from).to.eq(ZERO_ADDRESS);
        expect(log.args.to).to.eq(this.deployer);
        log.args.value.should.be.bignumber.eq(INTIAL_SUPPLY);
    });

    it('should set the owner', async () => {
        expect(await this.instance.owner()).to.equal(this.deployer);
    });

    it('should have correct name name', async () => {
        expect(await this.instance.name.call()).to.eq('stableflect.finance');
    });

    it('should have correct ticker', async () => {
        expect(await this.instance.symbol.call()).to.eq('STAB');
    });

    it('should have correct decimals', async () => {
        (await this.instance.decimals()).should.bignumber.eq(new BN(DECIMALS));
    });

    it('should have epoch set to 1', async () => {
        (await this.instance.epoch.call()).eq(1);
    });

    it('should set initial supply', async () => {
        (await this.instance.totalSupply.call()).should.bignumber.eq(INTIAL_SUPPLY);
    });

    it('shouldn\'t be excluded, but included', async () => {
        expect(await this.instance.isExcluded(this.deployer)).to.eq(false);
        expect(await this.instance.isIncluded(this.deployer)).to.eq(true);
    });

    it('shouldn\'t be paused', async () => {
        expect(await this.instance.paused.call({from: this.deployer})).to.eq(false);
    });
});

describe('Admin actions', function () {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('ban user', async () => {
        await this.instance.banUser(this.deployer, {from: this.deployer});
        expect(await this.instance.isExcluded(this.deployer)).to.eq(true);
    });

    it('banned cannot send transaction', async () => {
        await this.instance.banUser(this.deployer, {from: this.deployer});

        await expectRevert.unspecified(this.instance.transfer(accounts[1], 1, {from: this.deployer}), 'User banned');
    });

    it('paused token cannot send transaction', async () => {
        const receipt = await this.instance.pause({from: this.deployer});
        expectEvent(receipt, 'Paused', {account: this.deployer});

        await expectRevert.unspecified(this.instance.transfer(accounts[1], 1, {from: this.deployer}),
            'Pausable: paused');
    });

    it('exclude-include account balances', async () => {
        const preExcludeBalance = await this.instance.balanceOf(this.deployer);
        await this.instance.excludeAccount(this.deployer, {from: this.deployer});
        expect(await this.instance.isExcluded(this.deployer)).to.eq(true);
        expect(await this.instance.isIncluded(this.deployer)).to.eq(false);
        const postExcludeBalance = await this.instance.balanceOf(this.deployer);
        await this.instance.includeAccount(this.deployer, {from: this.deployer});
        expect(await this.instance.isExcluded(this.deployer)).to.eq(false);
        expect(await this.instance.isIncluded(this.deployer)).to.eq(true);
        const postReIncludeBalance = await this.instance.balanceOf(this.deployer);

        preExcludeBalance.should.bignumber.eq(postExcludeBalance);
        postExcludeBalance.should.bignumber.eq(postReIncludeBalance);
    });
});

describe('Transactions', function () {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('simple transaction', async () => {
        await this.instance.transfer(this.receiver, INTIAL_SUPPLY.div(new BN(2)), {from: this.deployer});
        const receiverFunds = await this.instance.balanceOf(this.receiver);
        const deployerFunds = await this.instance.balanceOf(this.deployer);

        receiverFunds.should.bignumber.eq(new BN(2497497497497497));
        deployerFunds.should.bignumber.eq(new BN(2502502502502502));

        receiverFunds.add(deployerFunds).should.bignumber.eq(INTIAL_SUPPLY.sub(new BN(1)));
    });

    it('simple transaction and send back', async () => {
        await this.instance.transfer(this.receiver, INTIAL_SUPPLY.div(new BN(2)), {from: this.deployer});
        await this.instance.transfer(this.deployer, new BN(2497497497497497), {from: this.receiver});
        const receiverFunds = await this.instance.balanceOf(this.receiver);
        const deployerFunds = await this.instance.balanceOf(this.deployer);

        receiverFunds.should.bignumber.eq(new BN(0));
        deployerFunds.should.bignumber.eq(INTIAL_SUPPLY.sub(new BN(1)));
    });

    it('more simple transactions', async () => {
        await this.instance.transfer(this.receiver, INTIAL_SUPPLY.div(new BN(2)), {from: this.deployer});
        const receiverFunds = await this.instance.balanceOf(this.receiver);
        const deployerFunds = await this.instance.balanceOf(this.deployer);

        receiverFunds.should.bignumber.eq(new BN(2497497497497497));
        deployerFunds.should.bignumber.eq(new BN(2502502502502502));

        receiverFunds.add(deployerFunds).should.bignumber.eq(INTIAL_SUPPLY.sub(new BN(1)));
    });
});