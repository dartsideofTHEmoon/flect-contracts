pragma solidity >=0.6.0 <0.8.0;

import "../ChainSwap.sol";

contract ChainSwapMock is ChainSwap {
    function areFundsClaimed(bytes32 hash) view public returns(bool) {
        return _claimedFunds[hash];
    }

    function verifySignatureMock(bytes32 messageHash, bytes memory signature, address account) pure public returns (bool) {
        return _verifySignature(messageHash, signature, account);
    }

    function migrateToOtherChainMock(Token _stab, uint256 amount, string memory toNetwork, string memory toAddress,
            uint256 timeForUnlock, uint256 epoch) public{
        return _migrateToOtherChain(_stab, amount, toNetwork, toAddress, timeForUnlock, epoch);
    }

    function setFeeParamsMock(uint256 multiplier, uint256 divisor) public
    {
        _feeMultiplier = multiplier;
        _feeDivisor = divisor;
    }

    function createMessageHashMock(uint256 id, address sendTo, uint256 amount, string memory chainName, uint256 epoch)
        public pure returns (bytes32) {
        return _createMessageHash(id, sendTo, amount, chainName, epoch);
    }

    function getMessageBeforeHash(uint64 id, address sendTo, uint256 amount, string memory chainName) public pure returns (bytes memory) {
        return abi.encode(id, sendTo, amount, chainName);
    }

    function claimFromOtherChainMock(Token _stab, uint64 id, address sendTo, uint256 amount, string memory chainName,
        uint256 epoch, bytes memory signature, address whiteListedSigner) public returns(bool) {
        return _claimFromOtherChain(_stab, id, sendTo, amount, chainName, epoch, signature, whiteListedSigner);
    }
}
