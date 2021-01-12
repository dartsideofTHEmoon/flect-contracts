pragma solidity >=0.6.0 <0.8.0;

contract DebugHelpers {

    function concatStrings(string memory a, string memory b) public pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function concatStrings(string memory a, string memory b, string memory c) public pure returns (string memory) {
        return string(abi.encodePacked(a, b, c));
    }

    function concatStrings(string memory a, string memory b, string memory c, string memory d) public pure returns (string memory) {
        return string(abi.encodePacked(a, b, c, d));
    }

    function raiseString(string memory a) public pure {
        require(false, a);
    }

    function bytes32ToStr(bytes32 _bytes32) public pure returns (string memory) {

        // string memory str = string(_bytes32);
        // TypeError: Explicit type conversion not allowed from "bytes32" to "string storage pointer"
        // thus we should fist convert bytes32 to bytes (to dynamically-sized byte array)

        bytes memory bytesArray = new bytes(32);
        for (uint256 i; i < 32; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function uintToBytes(uint v) public pure returns (bytes32) {
        bytes32 ret;
        if (v == 0) {
            ret = '0';
        }
        else {
            while (v > 0) {
                ret = bytes32(uint(ret) / (2 ** 8));
                ret |= bytes32(((v % 10) + 48) * 2 ** (8 * 31));
                v /= 10;
            }
        }
        return ret;
    }

    function uintToString(uint v) public pure returns (string memory) {
        return bytes32ToStr(uintToBytes(v));
    }
}
