const BN = require("bn.js");
const {accounts, contract} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');

const Token = contract.fromArtifact("TokenMock");
const EnumerableFifo = contract.fromArtifact("EnumerableFifo");
const MonetaryPolicy = contract.fromArtifact("TokenMonetaryPolicy");

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
const BILLION = 1000 * 1000 * 1000;

function toUnitsDenomination(x) {
    return new BN(x).mul(new BN(10 ** DECIMALS));
}

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const library = await EnumerableFifo.new();
    await Token.detectNetwork();
    await Token.link('EnumerableFifo', library.address);
    const tokenInstance = await Token.new({from: deployer});
    const monetaryPolicy = await MonetaryPolicy.new(tokenInstance.address, UNIT.mul(new BN(BILLION)), {from: deployer});

    return [tokenInstance, monetaryPolicy, deployer, receiver];
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

       await expectRevert.unspecified(this.monetaryPolicy.setStabToken(this.tokenInstance.address, {from: this.receiver}), 'Restricted to admins.');
       expect(await this.monetaryPolicy.hasRole('0x00', this.receiver)).to.eq(false);
    });
});
