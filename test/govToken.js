const BN = require("bn.js");
const {accounts, contract} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');

const GovToken = contract.fromArtifact("GovTokenMock");
const Token = contract.fromArtifact("Token");
const EnumerableFifo = contract.fromArtifact("EnumerableFifo");
const EnumerableSetUpgradeable = contract.fromArtifact("EnumerableSetUpgradeable");
const MonetaryPolicy = contract.fromArtifact("TokenMonetaryPolicy");
const OracleMock = contract.fromArtifact("OracleMock");

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

const ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000';
const MONETARY_POLICY_ROLE = '0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3';
const MINTER_ROLE = '0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6';
const BURNER_ROLE = '0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848';
const BILLION = UNIT.mul(new BN(1000 * 1000 * 1000));

function toUnitsDenomination(x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const enuberableFifo = await EnumerableFifo.new();
    await Token.detectNetwork();
    await Token.link('EnumerableFifo', enuberableFifo.address);
    const tokenInstance = await Token.new({from: deployer});
    await tokenInstance.initialize('STAB', 'stableflect.finance', {from: deployer});
    const tokenRevInstance = await Token.new({from: deployer});
    await tokenRevInstance.initialize('rSTAB', 'revert.stableflect.finance', {from: deployer});

    const monetaryPolicy = await MonetaryPolicy.new(tokenInstance.address, tokenRevInstance.address, BILLION, "ETH",
        {from: deployer});

    // Set up roles in monetary policy
    await tokenInstance.grantRole(MONETARY_POLICY_ROLE, monetaryPolicy.address, {from: deployer});
    await tokenInstance.grantRole(MINTER_ROLE, monetaryPolicy.address, {from: deployer});
    await tokenInstance.grantRole(BURNER_ROLE, monetaryPolicy.address, {from: deployer});
    await tokenRevInstance.grantRole(MONETARY_POLICY_ROLE, monetaryPolicy.address, {from: deployer});
    await tokenRevInstance.grantRole(MINTER_ROLE, monetaryPolicy.address, {from: deployer});
    await tokenRevInstance.grantRole(BURNER_ROLE, monetaryPolicy.address, {from: deployer});

    const library = await EnumerableSetUpgradeable.new();
    await GovToken.detectNetwork();
    await GovToken.link('EnumerableSetUpgradeable', library.address);
    const govInstance = await GovToken.new({from: deployer});
    await govInstance.initialize(monetaryPolicy.address, [], {from: deployer});

    // Set up roles in governance token.
    await tokenInstance.grantRole(MONETARY_POLICY_ROLE, govInstance.address, {from: deployer});
    await tokenInstance.grantRole(MINTER_ROLE, govInstance.address, {from: deployer});
    await tokenInstance.grantRole(BURNER_ROLE, govInstance.address, {from: deployer});
    await tokenRevInstance.grantRole(MONETARY_POLICY_ROLE, govInstance.address, {from: deployer});
    await tokenRevInstance.grantRole(MINTER_ROLE, govInstance.address, {from: deployer});
    await tokenRevInstance.grantRole(BURNER_ROLE, govInstance.address, {from: deployer});

    return [govInstance, tokenInstance, tokenRevInstance, deployer, receiver];
}

describe('Initialization', async () => {
    beforeEach(async () => {
        [this.govInstance, this.tokenInstance, this.tokenRevInstance, this.deployer, this.receiver] = await BeforeEach();
    });

    describe('addTokenAddresses', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.addTokenAddresses(this.receiver, {from: this.receiver}), 'Only admins.');
        });

        it('already added', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await expectRevert(this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer}), 'This token is already governed.');
        });

        it("not zero address", async () => {
            await expectRevert(this.govInstance.addTokenAddresses("0x0000000000000000000000000000000000000000", {from: this.deployer}), 'Cannot add a zero address.');
        });

        it("success", async () => {
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq("0");
            (await this.govInstance.getTotalSupplyEpochMock.call()).should.bignumber.eq("1");

            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});

            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq(await this.tokenInstance.totalSupply.call());
        });
    });

    describe('removeTokenAddresses', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.removeTokenAddresses(this.receiver, {from: this.receiver}), 'Only admins.');
        });

        it('not added', async () => {
            await expectRevert(this.govInstance.removeTokenAddresses(this.tokenInstance.address, {from: this.deployer}), 'This token is not governed yet.');
        });

        it("success", async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenRevInstance.address, {from: this.deployer});
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq("10000000000000000");
            (await this.govInstance.getTotalSupplyEpochMock.call()).should.bignumber.eq("1");

            await this.govInstance.removeTokenAddresses(this.tokenInstance.address, {from: this.deployer});

            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq("5000000000000000");
        });
    });

    describe('setTokenPriceOracle', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.setTokenPriceOracle(this.receiver, {from: this.receiver}), 'Only admins.');
        });
    });

    describe('setFeeParams', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.setFeeParams(100, 110, {from: this.receiver}), 'Only admins.');
        });

        it('success', async () => {
            await this.govInstance.setFeeParams(112, 155, {from: this.deployer});

            const {0: feeMultiplier, 1: feeDivisor} = await this.govInstance.getFeeParamsMock.call();

            feeMultiplier.should.bignumber.eq(new BN(112));
            feeDivisor.should.bignumber.eq(new BN(155));
        });
    });

    describe('setTokenMonetaryPolicy', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.setTokenMonetaryPolicy(this.receiver, {from: this.receiver}), 'Only admins.');
        });
    });

    describe('mintStabForGov', async () => {
        it('only whitelisted', async () => {
            await expectRevert(this.govInstance.mintStabForGov(this.tokenInstance.address, 1000, {from: this.receiver}), 'Token is not governed by this contract.');
        });

        it('missing allowance', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await expectRevert(this.govInstance.mintStabForGov(this.tokenInstance.address, 1000, {from: this.deployer}), 'ERC20: decreased allowance below zero.');
        });

        it('success', async () => {
            await this.govInstance.increaseAllowance(this.govInstance.address, 1000, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            const govPriceOracle = await OracleMock.new('govPrice');
            await govPriceOracle.storeData(UNIT.mul(new BN(8))); // 8USD = 1GOV.
            await this.govInstance.setTokenPriceOracle(govPriceOracle.address, {from: this.deployer});
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq(UNIT.mul(new BN(5000000)));
            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000)));

            // gSTAB total supply == 100mln, STAB total supply = 5mln, so rarity is on STAB side (20x),
            // but price of gSTAB = 8USD, and we treat STAB as 1USD * rarity.
            // Finally exchanges 1000 gSTAB for 400 STAB * 0.995 (fee).
            await this.govInstance.mintStabForGov(this.tokenInstance.address, 1000, {from: this.deployer});
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq(UNIT.mul(new BN(5000000)).add(new BN(398)));
            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000)).sub(new BN(1000)));
        });
    });

    describe('mintGovForStab', async () => {
        it('only whitelisted', async () => {
            await expectRevert(this.govInstance.mintGovForStab(this.tokenInstance.address, 1000, {from: this.receiver}), 'Token is not governed by this contract.');
        });

        it('missing allowance', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await expectRevert(this.govInstance.mintGovForStab(this.tokenInstance.address, 1000, {from: this.deployer}), 'Exceeds allowance.');
        });

        it('success', async () => {
            await this.tokenInstance.transfer(this.govInstance.address, 10000, {from: this.deployer});
            await this.tokenInstance.increaseAllowance(this.govInstance.address, 1000, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            const govPriceOracle = await OracleMock.new('govPrice');
            await govPriceOracle.storeData(UNIT.mul(new BN(8))); // 8USD = 1GOV.
            await this.govInstance.setTokenPriceOracle(govPriceOracle.address, {from: this.deployer});
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq(UNIT.mul(new BN(5000000)));
            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000)));

            // gSTAB total supply == 100mln, STAB total supply = 5mln, so rarity is on STAB side (20x),
            // but price of gSTAB = 8USD, and we treat STAB as 1USD * rarity.
            // Finally exchanges 1000 STAB for 400 gSTAB * 0.995 (fee).
            await this.govInstance.mintGovForStab(this.tokenInstance.address, 400, {from: this.deployer});
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq(UNIT.mul(new BN(5000000)).sub(new BN(400)));
            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000)).add(new BN(995)));
        });
    });

    describe('exchangeStabForStab', async () => {
        it('from not whitelisted', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await expectRevert(this.govInstance.exchangeStabForStab(this.tokenRevInstance.address, this.tokenInstance.address, 1), '\'from\' token is not governed by this contract.');
        });

        it('to not whitelisted', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, {from: this.deployer});
            await expectRevert(this.govInstance.exchangeStabForStab(this.tokenInstance.address, this.tokenRevInstance.address, 1), '\'to\' token is not governed by this contract.');
        });
    });
});
