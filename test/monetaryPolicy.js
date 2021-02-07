const BN = require("bn.js");
const {accounts, contract} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');

const Token = contract.fromArtifact("TokenMock");
const EnumerableFifo = contract.fromArtifact("EnumerableFifo");
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
const BILLION = UNIT.mul(new BN(1000 * 1000 * 1000));

function toUnitsDenomination(x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const library = await EnumerableFifo.new();
    await Token.detectNetwork();
    await Token.link('EnumerableFifo', library.address);
    const tokenInstance = await Token.new({from: deployer});
    await tokenInstance.initialize({from: deployer});
    const monetaryPolicy = await MonetaryPolicy.new({from: deployer});
    await monetaryPolicy.initialize(tokenInstance.address, BILLION, {from: deployer});

    return [tokenInstance, monetaryPolicy, deployer, receiver];
}

async function waitForSomeTime(seconds) {
    await time.increase(seconds);
}

describe('Initialization', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should set the owner', async () => {
        expect(await this.monetaryPolicy.hasRole('0x00', this.deployer));
    });

    it('stab token test', async () => {
        this.monetaryPolicy.setStabToken(this.tokenInstance.address, {from: this.deployer});
        expect(await this.monetaryPolicy.hasRole('0x00', this.deployer)).to.eq(true);

        await expectRevert(this.monetaryPolicy.setStabToken(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
        expect(await this.monetaryPolicy.hasRole('0x00', this.receiver)).to.eq(false);
    });
});

describe('TokenMonetaryPolicy:setTokenPriceOracle', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should set tokenPriceOracle', async () => {
        await this.monetaryPolicy.setTokenPriceOracle(await this.deployer, {from: this.deployer});
        expect(await this.monetaryPolicy.tokenPriceOracle()).to.equal(this.deployer);
    });
});

describe('Token:setTokenPriceOracle:accessControl', () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should be callable by owner', async () => {
        await this.monetaryPolicy.setTokenPriceOracle(this.deployer, {from: this.deployer});
    });

    it('should NOT be callable by non-owner', async () => {
        await expectRevert(this.monetaryPolicy.setTokenPriceOracle(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
    });
});

describe('TokenMonetaryPolicy:setMcapOracle', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should set mcapOracle', async () => {
        await this.monetaryPolicy.setMcapOracle(await this.deployer, {from: this.deployer});
        expect(await this.monetaryPolicy.mcapOracle()).to.equal(this.deployer);
    });
});

describe('Token:setMcapOracle:accessControl', () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should be callable by owner', async () => {
        await this.monetaryPolicy.setMcapOracle(this.deployer, {from: this.deployer});
    });

    it('should NOT be callable by non-owner', async () => {
        await expectRevert(this.monetaryPolicy.setMcapOracle(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
    });
});

describe('TokenMonetaryPolicy:setOrchestrator', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should set orchestrator', async () => {
        await this.monetaryPolicy.setOrchestrator(await this.deployer, {from: this.deployer});
        expect(await this.monetaryPolicy.orchestrator()).to.equal(this.deployer);
    })
});

describe('Token:setOrchestrator:accessControl', () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should be callable by owner', async () => {
        await this.monetaryPolicy.setOrchestrator(this.deployer, {from: this.deployer});
    });

    it('should NOT be callable by non-owner', async () => {
        await expectRevert(this.monetaryPolicy.setOrchestrator(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
    });
});

describe('TokenMonetaryPolicy:setRebaseLag', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    describe('when rebaseLag is more than 0', async () => {
        it('should setRebaseLag', async () => {
            const prevLag = await this.monetaryPolicy.rebaseLag();
            const lag = prevLag.add(new BN(1));
            await this.monetaryPolicy.setRebaseLag(lag, {from: this.deployer});
            (await this.monetaryPolicy.rebaseLag()).should.bignumber.eq(lag);
        })
    });

    describe('when rebaseLag is 0', async () => {
        it('should fail', async () => {
            await expectRevert(this.monetaryPolicy.setRebaseLag(0, {from: this.deployer}), 'rebase lag should be bigger than 0');
        })
    })
});

describe('Token:setRebaseLag:accessControl', () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should be callable by owner', async () => {
        await this.monetaryPolicy.setRebaseLag(1, {from: this.deployer});
    });

    it('should NOT be callable by non-owner', async () => {
        await expectRevert(this.monetaryPolicy.setRebaseLag(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
    });
});

describe('TokenMonetaryPolicy:setRebaseTimingParameters', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    describe('when interval=0', () => {
        it('should fail', async () => {
            await expectRevert(this.monetaryPolicy.setRebaseTimingParameters(0, 0, 0, {from: this.deployer}), 'minRebaseTimeIntervalSec cannot be 0');
        })
    });

    describe('when offset > interval', () => {
        it('should fail', async () => {
            await expectRevert(this.monetaryPolicy.setRebaseTimingParameters(300, 3600, 300, {from: this.deployer}), 'rebaseWindowOffsetSec_ >= minRebaseTimeIntervalSec_');
        })
    });

    describe('when params are valid', () => {
        it('should setRebaseTimingParameters', async () => {
            await this.monetaryPolicy.setRebaseTimingParameters(600, 60, 300, {from: this.deployer});
            (await this.monetaryPolicy.minRebaseTimeIntervalSec()).should.bignumber.eq(new BN(600));
            (await this.monetaryPolicy.rebaseWindowOffsetSec()).should.bignumber.eq(new BN(60));
            (await this.monetaryPolicy.rebaseWindowLengthSec()).should.bignumber.eq(new BN(300));
        })
    })
});

describe('Token:setRebaseTimingParameters:accessControl', () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('should be callable by owner', async () => {
        await this.monetaryPolicy.setRebaseTimingParameters(600, 60, 30, {from: this.deployer});
    });

    it('should NOT be callable by non-owner', async () => {
        await expectRevert(this.monetaryPolicy.setRebaseTimingParameters(600, 60, 30, {from: this.receiver}), 'Restricted to admins.');
    });
});

describe('TokenMonetaryPolicy:Rebase:accessControl', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
        await this.monetaryPolicy.setRebaseTimingParameters(60, 0, 60, {from: this.deployer});
        await this.monetaryPolicy.setOrchestrator(await this.deployer, {from: this.deployer});
        await this.monetaryPolicy.setStabToken(this.tokenInstance.address, {from: this.deployer});
        // Grant monetary policy role
        await this.tokenInstance.grantRole("0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3", this.monetaryPolicy.address, {from: this.deployer});

        const mcapOracle = await OracleMock.new('mcap', {from: this.deployer});
        await mcapOracle.storeData(BILLION.mul(new BN(105)).div(new BN(100)));
        const tokenPriceOracle = await OracleMock.new('token price', {from: this.deployer});
        await tokenPriceOracle.storeData(UNIT.mul(new BN(12)).div(new BN(10)));
        await this.monetaryPolicy.setMcapOracle(mcapOracle.address, {from: this.deployer});
        await this.monetaryPolicy.setTokenPriceOracle(tokenPriceOracle.address, {from: this.deployer});
    });

    describe('when rebase called by orchestrator', () => {
        it('should succeed', async () => {
            const epoch = await this.monetaryPolicy.epoch();
            await this.monetaryPolicy.rebase({from: this.deployer});
            (await this.monetaryPolicy.epoch()).should.bignumber.eq(epoch.add(new BN(1)));
        })
    });

    describe('when rebase called by non-orchestrator', () => {
        it('should fail', async () => {
            it('should NOT be callable by non-owner', async () => {
                await expectRevert(this.monetaryPolicy.rebase({from: this.receiver}), 'Restricted to admins.');
            });
        });
    });
});

describe('TokenMonetaryPolicy:RebaseParams', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.monetaryPolicy, this.deployer, this.receiver] = await BeforeEach();
    });

    it('get rebase params', async () => {
        const mcapOracle = await OracleMock.new('mcap', {from: this.deployer});
        await mcapOracle.storeData(BILLION.mul(new BN(105)).div(new BN(100)));
        const tokenPriceOracle = await OracleMock.new('token price', {from: this.deployer});
        await tokenPriceOracle.storeData(UNIT.mul(new BN(12)).div(new BN(10)));
        await this.monetaryPolicy.setMcapOracle(mcapOracle.address, {from: this.deployer});
        await this.monetaryPolicy.setTokenPriceOracle(tokenPriceOracle.address, {from: this.deployer});

        const values = await this.monetaryPolicy.getRebaseParams();
        const {0: mcap, 1: targetRate, 2: tokenPrice} = values;

        mcap.should.bignumber.eq(UNIT.mul(new BN(1050000000)));
        targetRate.should.bignumber.eq(new BN(1050000000));
        tokenPrice.should.bignumber.eq(new BN(1200000000));
    });
});
