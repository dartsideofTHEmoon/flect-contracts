const BN = require("bn.js");
const {accounts, contract} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
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

describe('GovToken', async () => {
    beforeEach(async () => {
        [this.govInstance, this.tokenInstance, this.tokenRevInstance, this.deployer, this.receiver] = await BeforeEach();
    });

    describe('addTokenAddresses', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.addTokenAddresses(this.receiver, "0x0000000000000000000000000000000000000000", {from: this.receiver}), 'Only admins.');
        });

        it('already added', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await expectRevert(this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer}), 'This token is already governed.');
        });

        it("not zero address", async () => {
            await expectRevert(this.govInstance.addTokenAddresses("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", {from: this.deployer}), 'Cannot add a zero address.');
        });

        it("success", async () => {
            (await this.govInstance.getTokensTotalSupplyMock.call()).should.bignumber.eq("0");
            (await this.govInstance.getTotalSupplyEpochMock.call()).should.bignumber.eq("1");

            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});

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
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenRevInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
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
            await expectRevert(this.govInstance.setFeeParams(100, 95, 90, 85, 80, 60, 110, {from: this.receiver}), 'Only admins.');
        });

        it('success', async () => {
            await this.govInstance.setFeeParams(112, 111, 110, 109, 108, 107, 155, {from: this.deployer});

            const {0: feeMultiplier, 1: fee6h, 2: fee1h, 3: fee10m, 4: fee2m, 5: feeMad, 6: feeDivisor} = await this.govInstance.getFeeParamsMock.call();

            feeMultiplier.should.bignumber.eq(new BN(112));
            fee6h.should.bignumber.eq(new BN(111));
            fee1h.should.bignumber.eq(new BN(110));
            fee10m.should.bignumber.eq(new BN(109));
            fee2m.should.bignumber.eq(new BN(108));
            feeMad.should.bignumber.eq(new BN(107));
            feeDivisor.should.bignumber.eq(new BN(155));
        });
    });

    describe('setTokenMonetaryPolicy', async () => {
        it('only admin', async () => {
            await expectRevert(this.govInstance.setTokenMonetaryPolicy(this.receiver, "0x0000000000000000000000000000000000000000", {from: this.receiver}), 'Only admins.');
        });
    });

    describe('getMintAmountForGov', async () => {
        this.prepareGetMintAmountForGovTest = async (cls, govPrice, tokensSupply) => {
            await cls.govInstance.setTokensTotalSupplyMock(tokensSupply);
            const govPriceOracle = await OracleMock.new('govPrice');
            await govPriceOracle.storeData(govPrice);
            await cls.govInstance.setTokenPriceOracle(govPriceOracle.address, {from: cls.deployer});
        }

        it('gov supply greater, gov 1$', async () => {
            await this.prepareGetMintAmountForGovTest(this, UNIT, UNIT.mul(new BN(1000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(2500000)))).should.bignumber.eq(UNIT.mul(new BN(24925))); // 25k - fee in exchange for 2.5mln
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(997000000)));
            (await this.govInstance.getMintAmountForGov(100)).should.bignumber.eq("0"); // to small amount 100 : 100 - fee -> 0
            (await this.govInstance.getMintAmountForGov(1000)).should.bignumber.eq("9"); // 1000 : 100 - fee -> 9
        });

        it('gov supply greater, gov 4$', async () => {
            await this.prepareGetMintAmountForGovTest(this, UNIT.mul(new BN(4)), UNIT.mul(new BN(1000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(2500000)))).should.bignumber.eq(UNIT.mul(new BN(99700)));
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(3988000000)));
            (await this.govInstance.getMintAmountForGov(100)).should.bignumber.eq("3"); // really small amount 4 * 100 : 100 - fee -> 3
            (await this.govInstance.getMintAmountForGov(1000)).should.bignumber.eq("39"); // 4 * 1000 : 100 - fee -> 39
        });

        it('gov supply lower, gov 1$', async () => {
            await this.prepareGetMintAmountForGovTest(this, UNIT, UNIT.mul(new BN(500000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(25000)))).should.bignumber.eq(UNIT.mul(new BN(124625)));
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(498500000000)));
            (await this.govInstance.getMintAmountForGov(100)).should.bignumber.eq("498");
            (await this.govInstance.getMintAmountForGov(1000)).should.bignumber.eq("4985");
        });

        it('gov supply lower, gov 5$', async () => {
            await this.prepareGetMintAmountForGovTest(this, UNIT.mul(new BN(5)), UNIT.mul(new BN(500000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(25000)))).should.bignumber.eq(UNIT.mul(new BN(623125)));
            (await this.govInstance.getMintAmountForGov(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(2492500000000)));
            (await this.govInstance.getMintAmountForGov(1)).should.bignumber.eq("24");
            (await this.govInstance.getMintAmountForGov(1000)).should.bignumber.eq("24925");
        });
    });

    describe('mintStabForGov', async () => {
        it('only whitelisted', async () => {
            await expectRevert(this.govInstance.mintStabForGov(this.tokenInstance.address, 1000, {from: this.receiver}), 'Token is not governed by this contract.');
        });

        it('missing allowance', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await expectRevert(this.govInstance.mintStabForGov(this.tokenInstance.address, 1000, {from: this.deployer}), 'ERC20: decreased allowance below zero.');
        });

        it('success', async () => {
            await this.govInstance.increaseAllowance(this.govInstance.address, 1000, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
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

    describe('getMintAmountForStab', async () => {
        this.prepareGetMintAmountForStabTest = async (cls, govPrice, tokensSupply) => {
            await cls.govInstance.setTokensTotalSupplyMock(tokensSupply);
            const govPriceOracle = await OracleMock.new('govPrice');
            await govPriceOracle.storeData(govPrice);
            await cls.govInstance.setTokenPriceOracle(govPriceOracle.address, {from: cls.deployer});
        }

        it('gov supply greater, gov 1$', async () => {
            await this.prepareGetMintAmountForStabTest(this, UNIT, UNIT.mul(new BN(1000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(2500000)))).should.bignumber.eq(UNIT.mul(new BN(249250000))); // 25k - fee in exchange for 2.5mln
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(9970000000000)));
            (await this.govInstance.getMintAmountForStab(100)).should.bignumber.eq("9970");
            (await this.govInstance.getMintAmountForStab(1000)).should.bignumber.eq("99700");
        });

        it('gov supply greater, gov 4$', async () => {
            await this.prepareGetMintAmountForStabTest(this, UNIT.mul(new BN(4)), UNIT.mul(new BN(1000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(2500000)))).should.bignumber.eq(UNIT.mul(new BN(62312500)));
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(2492500000000)));
            (await this.govInstance.getMintAmountForStab(100)).should.bignumber.eq("2492");
            (await this.govInstance.getMintAmountForStab(1000)).should.bignumber.eq("24925");
        });

        it('gov supply lower, gov 1$', async () => {
            await this.prepareGetMintAmountForStabTest(this, UNIT, UNIT.mul(new BN(500000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(25000)))).should.bignumber.eq(UNIT.mul(new BN(4985)));
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(19940000000)));
            (await this.govInstance.getMintAmountForStab(100)).should.bignumber.eq("19");
            (await this.govInstance.getMintAmountForStab(1000)).should.bignumber.eq("199");
        });

        it('gov supply lower, gov 5$', async () => {
            await this.prepareGetMintAmountForStabTest(this, UNIT.mul(new BN(5)), UNIT.mul(new BN(500000000)));

            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000))); // 100 mln
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(25000)))).should.bignumber.eq(UNIT.mul(new BN(997)));
            (await this.govInstance.getMintAmountForStab(UNIT.mul(new BN(100000000000)))).should.bignumber.eq(UNIT.mul(new BN(3988000000)));
            (await this.govInstance.getMintAmountForStab(100)).should.bignumber.eq("3");
            (await this.govInstance.getMintAmountForStab(1000)).should.bignumber.eq("39");
        });
    });

    describe('mintGovForStab', async () => {
        it('only whitelisted', async () => {
            await expectRevert(this.govInstance.mintGovForStab(this.tokenInstance.address, 1000, {from: this.receiver}), 'Token is not governed by this contract.');
        });

        it('missing allowance', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await expectRevert(this.govInstance.mintGovForStab(this.tokenInstance.address, 1000, {from: this.deployer}), 'Exceeds allowance.');
        });

        it('success', async () => {
            await this.tokenInstance.transfer(this.govInstance.address, 10000, {from: this.deployer});
            await this.tokenInstance.increaseAllowance(this.govInstance.address, 1000, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
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
            (await this.govInstance.totalSupply.call()).should.bignumber.eq(UNIT.mul(new BN(100000000)).add(new BN(997)));
        });
    });

    describe('exchangeStabForStab', async () => {
        it('from not whitelisted', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await expectRevert(this.govInstance.exchangeStabForStab(this.tokenRevInstance.address, this.tokenInstance.address, 1), '\'from\' token is not governed by this contract.');
        });

        it('to not whitelisted', async () => {
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, "0x0000000000000000000000000000000000000000", {from: this.deployer});
            await expectRevert(this.govInstance.exchangeStabForStab(this.tokenInstance.address, this.tokenRevInstance.address, 1), '\'to\' token is not governed by this contract.');
        });

        it('success', async() => {
            const monetary = new MonetaryPolicy(await this.govInstance.getMainMonetaryPolicyMock());
            await this.govInstance.addTokenAddresses(this.tokenInstance.address, monetary.address, {from: this.deployer});
            await this.govInstance.addTokenAddresses(this.tokenRevInstance.address, monetary.address, {from: this.deployer});
            const timeInterval = await monetary.minRebaseTimeIntervalSec.call();
            timeInterval.should.bignumber.eq(new BN(86400));
            const latest = await time.latest();
            const timeToRebase = timeInterval.sub(latest.mod(timeInterval));
            const endOfRebase = timeInterval.sub(await monetary.rebaseWindowOffsetSec.call());
            await time.increase(timeToRebase.add(endOfRebase).add(new BN(60))); // make sure 'normal fee' is applied.
            await time.advanceBlock(); // produce a block with new time.
            await this.tokenInstance.increaseAllowance(this.govInstance.address, 1000000000000000, {from: this.deployer});

            (await this.tokenInstance.balanceOf(this.deployer)).should.bignumber.eq(new BN(5000000000000000));
            (await this.tokenRevInstance.balanceOf(this.deployer)).should.bignumber.eq(new BN(5000000000000000));
            (await this.tokenInstance.balanceOf(this.govInstance.address)).should.bignumber.eq(new BN(0));
            (await this.govInstance.getTokensTotalSupplyMock()).should.bignumber.eq(new BN("10000000000000000"));
            this.govInstance.exchangeStabForStab(this.tokenInstance.address, this.tokenRevInstance.address, 1000000000000000, {from: this.deployer});
            (await this.tokenInstance.balanceOf(this.deployer)).should.bignumber.eq(new BN(4001600640256102));
            (await this.tokenRevInstance.balanceOf(this.deployer)).should.bignumber.eq(new BN(5997000000000000));
            (await this.tokenInstance.balanceOf(this.govInstance.address)).should.bignumber.eq(new BN(1399359743897));
            (await this.govInstance.getTokensTotalSupplyMock()).should.bignumber.eq(new BN("10000000000000000"));
        });
    });
});
