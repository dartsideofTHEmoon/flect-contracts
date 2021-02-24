const BN = require("bn.js");
const {accounts, contract, web3} = require('@openzeppelin/test-environment');
const {expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');

const ChainSwap = contract.fromArtifact("ChainSwapMock");

require('chai').should();
require('chai')
    .use(require('chai-bn')(BN))
    .should();

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const chainSwap = await ChainSwap.new({from: deployer});

    return [chainSwap, deployer, receiver];
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
        [this.chainSwapInstance, this.deployer, this.receiver] = await BeforeEach();
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
});
