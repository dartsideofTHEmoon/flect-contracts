const BN = require("bn.js");
const { accounts, contract } = require('@openzeppelin/test-environment');
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const Token = contract.fromArtifact("TokenMock");

require('chai').should();
require('chai')
    .use(require('chai-bn')(BN))
    .should();


const DECIMALS = 9;
const INTIAL_SUPPLY = toUnitsDenomination(5 * 10 ** 6);
const UNIT = toUnitsDenomination(1);
const MAX_UINT224 = new BN(2).pow(new BN(223));
const INITIAL_REFLECTION = MAX_UINT224.sub(MAX_UINT224.umod(INTIAL_SUPPLY));
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

describe('Rebase parameters', async () => {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('Test rebase factors', async() => {
        const exchangePrice = toUnitsDenomination(11);
        const targetPrice = toUnitsDenomination(7);
        const values = await this.instance._getRebaseFactorsMock.call(exchangePrice, targetPrice, 5);
        const {0: minEpoch, 1: currentNetMultiplier, 2: maxFactor} = values;

        minEpoch.eq(1);
        currentNetMultiplier.should.bignumber.eq(new BN(1114285714));
        maxFactor.should.bignumber.eq(UNIT);
    });

    it('Test rebase factors (more epochs)', async() => {
        await this.instance._setEpochMock(13);
        const decreasePerEpoch = await this.instance._getDecreasePerEpochMock();

        const exchangePrice = toUnitsDenomination(7);
        const targetPrice = toUnitsDenomination(11);
        const values = await this.instance._getRebaseFactorsMock.call(exchangePrice, targetPrice, 5);
        const {0: minEpoch, 1: currentNetMultiplier, 2: maxFactor} = values;

        minEpoch.eq(1);
        currentNetMultiplier.should.bignumber.eq(new BN(927272728));
        maxFactor.should.bignumber.eq(UNIT.add(new BN(decreasePerEpoch * (13 - 1))));
    });

    it('Test rebase factor (max incentive)', async() => {
        await this.instance._setEpochMock(500);
        const decreasePerEpoch = await this.instance._getDecreasePerEpochMock();
        const maxIncetive = await this.instance._getMaxIncentiveMock();
        const maxHistoryLen = await this.instance._getMaxHistoryLenMock();

        const exchangePrice = toUnitsDenomination(150);
        const targetPrice = toUnitsDenomination(123);
        const values = await this.instance._getRebaseFactorsMock.call(exchangePrice, targetPrice, 5);
        const {0: minEpoch, 1: currentNetMultiplier, 2: maxFactor} = values;

        minEpoch.eq(1);
        currentNetMultiplier.should.bignumber.eq(new BN(1043902439));
        maxFactor.should.bignumber.eq(UNIT.add(new BN(decreasePerEpoch * maxHistoryLen)));
        maxFactor.should.bignumber.eq(maxIncetive);
    });

    it('Test simple positive rebase', async() => {
        const exchangePrice = toUnitsDenomination(12);
        const targetPrice = toUnitsDenomination(11);

        await this.instance.setMonetaryPolicy(this.deployer, {from: this.deployer});
        await this.instance.rebase(exchangePrice, targetPrice, 5, {from: this.deployer});

        // (await this.instance.totalSupply()).should.bignumber.eq(new BN(5090909090000000));
        (await this.instance.balanceOf(this.deployer)).should.bignumber.eq(new BN(5090909090000000));
    });

    it('Test simple negative rebase', async() => {
        const exchangePrice = toUnitsDenomination(20);
        const targetPrice = toUnitsDenomination(21);

        await this.instance.setMonetaryPolicy(this.deployer, {from: this.deployer});
        await this.instance.rebase(exchangePrice, targetPrice, 2, {from: this.deployer});

        // (await this.instance.totalSupply()).should.bignumber.eq(new BN(5090909090000000));
        (await this.instance.balanceOf(this.deployer)).should.bignumber.eq(new BN(4880952385000000));
    });
});
