const Token = artifacts.require("./Token.sol");

contract("Token", (accounts) => {
    let instance;
    beforeEach('Sets up contract instance', async () => {
        instance = await Token.deployed();
    });

    it('Tests token name', async () => {
        const name = await instance.name();

        assert.equal(name, 'stableflect.finance');
    });

    it('Tests token ticker', async () => {
        const ticker = await instance.symbol();

        assert.equal(ticker, 'STAB');
    });

    it('Tests token decimals', async () => {
        const decimals = await instance.decimals();

        assert.equal(decimals, 9);
    });

});
