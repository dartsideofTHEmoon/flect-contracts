pragma solidity >=0.6.0 <0.8.0;

import "../ChainSwap.sol";

contract ChainSwapMock is ChainSwap {
    function verifySignatureMock(bytes32 messageHash, bytes memory signature, address account) pure public returns (bool) {
        return _verifySignature(messageHash, signature, account);
    }
}
