const BN = require("bn.js");
const {accounts, contract, web3} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');

const Token = contract.fromArtifact("TokenMock");
const EnumerableFifo = contract.fromArtifact("EnumerableFifo");
const ChainSwap = contract.fromArtifact("ChainSwapMock");

require('chai').should();
require('chai')
    .use(require('chai-bn')(BN))
    .should();

const DECIMALS = 9;
const UNIT = new BN(1).mul(new BN(10 ** DECIMALS));
const MONETARY_POLICY_ROLE = '0x901ebb412049abe4673b7c942b9b01ba7e8a61bb1e7e0da5426bdcd9a7a3a7e3';
const MINTER_ROLE = '0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6';

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const library = await EnumerableFifo.new();
    await Token.detectNetwork();
    await Token.link('EnumerableFifo', library.address);

    const chainSwap = await ChainSwap.new({from: deployer});
    const tokenInstance = await Token.new({from: deployer});
    await tokenInstance.initialize({from: deployer});


    return [tokenInstance, chainSwap, deployer, receiver];
}

function toEthSignedMessageHash(messageHex) {
    const messageBuffer = Buffer.from(messageHex.substring(2), 'hex');
    const prefix = Buffer.from(`\u0019Ethereum Signed Message:\n${messageBuffer.length}`);
    return web3.utils.sha3(Buffer.concat([prefix, messageBuffer]));
}

function fixSignature(signature) {
    // in geth its always 27/28, in ganache its 0/1. Change to 27/28 to prevent
    // signature malleability if version is 0/1
    // see https://github.com/ethereum/go-ethereum/blob/v1.8.23/internal/ethapi/api.go#L465
    let v = parseInt(signature.slice(130, 132), 16);
    if (v < 27) {
        v += 27;
    }
    const vHex = v.toString(16);
    return signature.slice(0, 130) + vHex;
}

describe('ChainSwap', async () => {
    beforeEach(async () => {
        [this.tokenInstance, this.chainSwapInstance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('returns signer address', async () => {
        // Create the signature
        const signature = fixSignature(await web3.eth.sign(web3.utils.sha3("MESSAGE"), this.deployer));

        // Recover the signer address from the generated message and signature.
        expect(await this.chainSwapInstance.verifySignatureMock(
            web3.utils.sha3("MESSAGE"),
            signature,
            this.deployer,
        )).to.equal(true);
    });

    describe('migrate to other chain', async () => {
        it('less than min time', async () => {
            expectRevert(this.chainSwapInstance.migrateToOtherChainMock(this.tokenInstance.address,
                UNIT.mul(new BN(1000000)), 'BSC', 'ADDRS_ON_A_NEW_CHAIN', 60 * 30, 1),
                "time for unlock should be between 60 minutes and 24 hours.");
        });

        it('more than max time', async () => {
            expectRevert(this.chainSwapInstance.migrateToOtherChainMock(this.tokenInstance.address,
                UNIT.mul(new BN(1000000)), 'BSC', 'ADDRS_ON_A_NEW_CHAIN', 60 * 30, 1),
                "time for unlock should be between 60 minutes and 24 hours.");
        });

        it('low balance', async () => {
            expectRevert(this.chainSwapInstance.migrateToOtherChainMock(this.tokenInstance.address,
                UNIT.mul(new BN(1000000)), 'BSC', 'ADDRS_ON_A_NEW_CHAIN', 60 * 60, 1), "Balance is to low.");
        });

        it('migrate to other chain', async () => {
            await this.tokenInstance.transfer(this.receiver, UNIT.mul(new BN(1000000)), {from: this.deployer});
            (await this.tokenInstance.balanceOf(this.receiver)).should.bignumber.eq(new BN(998399359743897));
            await this.tokenInstance.grantRole(MONETARY_POLICY_ROLE, this.chainSwapInstance.address, {from: this.deployer});

            expectEvent(await this.chainSwapInstance.migrateToOtherChainMock(this.tokenInstance.address, new BN(998399359743897),
                'BSC', 'ADDRS_ON_A_NEW_CHAIN', 60 * 60, 1, {from: this.receiver}), 'MigrateRequest',
                [this.receiver, 'BSC', 'ADDRS_ON_A_NEW_CHAIN', new BN(996800643073944)]);
            (await this.tokenInstance.balanceOf(this.chainSwapInstance.address)).should.bignumber.eq(new BN(0));
        });

        it('migrate to other chain - with fee', async () => {
            await this.tokenInstance.transfer(this.receiver, UNIT.mul(new BN(1000000)), {from: this.deployer});
            (await this.tokenInstance.balanceOf(this.receiver)).should.bignumber.eq(new BN(998399359743897));
            await this.tokenInstance.grantRole(MONETARY_POLICY_ROLE, this.chainSwapInstance.address, {from: this.deployer});
            await this.chainSwapInstance.setFeeParamsMock(999, 1000);

            expectEvent(await this.chainSwapInstance.migrateToOtherChainMock(this.tokenInstance.address, new BN(998399359743897),
                'BSC', 'ADDRS_ON_A_NEW_CHAIN', 60 * 60, 1, {from: this.receiver}), 'MigrateRequest',
                [this.receiver, 'BSC', 'ADDRS_ON_A_NEW_CHAIN', new BN(995803842430870)]);
            (await this.tokenInstance.balanceOf(this.chainSwapInstance.address)).should.bignumber.eq(new BN(996800643074));
        });
    });

    describe('test creating a hash', async () => {
        it('check produces the same hash', async () => {
            const hash = await this.chainSwapInstance.createMessageHashMock(124, '0x47e1090438d3Da2173a28D156D5E217d62551FF3', 1501, 'TBSC');
            const testHash = web3.utils.soliditySha3(124, '0x47e1090438d3Da2173a28D156D5E217d62551FF3', 1501, 'TBSC');
            expect(hash).to.equal(testHash);
        })
    });

    describe('claim from other chain', async () => {
        it('valid signature, not permissions', async () => {
            const signerAddr = this.deployer;
            const sig = fixSignature(await web3.eth.sign(web3.utils.soliditySha3(124, this.receiver, 25000, 'BSC'), signerAddr));

            expectRevert(this.chainSwapInstance.claimFromOtherChainMock(this.tokenInstance.address, 124,
                this.receiver, 25000, 'BSC', sig, signerAddr, {from: this.receiver}), 'Only monetary policy');
        });
    });
});
