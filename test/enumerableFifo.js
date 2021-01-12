const BN = require("bn.js");
const { accounts, contract } = require('@openzeppelin/test-environment');
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const EnumerableFifoTest = contract.fromArtifact("EnumerableFifoTest");
const EnumerableFifo = contract.fromArtifact("EnumerableFifo");

require('chai').should();
require('chai')
    .use(require('chai-bn')(BN))
    .should();

async function BeforeEach() {
    const [deployer, receiver] = accounts;

    const library = await EnumerableFifo.new();
    await EnumerableFifoTest.detectNetwork();
    await EnumerableFifoTest.link('EnumerableFifo', library.address);
    const instance = await EnumerableFifoTest.new({from: deployer});

    return [instance, deployer, receiver];
}


describe('Simple math', async () => {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('Check add / sub', async () => {
        await this.instance.add(100);
        (await this.instance.getSum()).should.bignumber.eq(new BN(100));
        this.instance.epoch += 1;
        await this.instance.add(20);
        await this.instance.sub(50);
        await this.instance.add(30);
        this.instance.epoch += 2;
        await this.instance.sub(100);
        (await this.instance.getSum()).should.bignumber.eq(new BN(0));
    });

    it('Check flatten', async() => {
        this.instance.epoch += 30;
       await this.instance.add(50);
       this.instance.epoch += 30;
       await this.instance.add(75);
       (await this.instance.getSum()).should.bignumber.eq(new BN(125));
       await this.instance.flatten(10);
       (await this.instance.getSum()).should.bignumber.eq(new BN(125));
       await this.instance.add(25);
       await this.instance.flatten(31);
       await this.instance.sub(25);
       (await this.instance.getSum()).should.bignumber.eq(new BN(125));
    });
});

describe('Test rebase', async() => {
    beforeEach(async () => {
        [this.instance, this.deployer, this.receiver] = await BeforeEach();
    });

    it('Simple rebase', async() => {
        // await this.instance.add(100000000000); // 100 * 10**9
        // const totalChange = await this.instance.rebaseUserFunds(1, 0, 3 * 10**9, [10, 11, 10 ** 9, 10 ** 9]);
        // console.log(totalChange);
        // totalChange.should.bignumber.eq(new BN(1));
    });
});
