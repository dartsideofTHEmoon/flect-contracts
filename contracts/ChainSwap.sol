pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol"; // Use exactly the same version of math lib as Token.
import "./Token.sol";

contract ChainSwap is Context {
    using SafeMathUpgradeable for uint256;
    using ECDSA for bytes32;

    mapping(address => SwapRequest[]) internal _swapRequests;
    mapping(bytes32 => bool) internal _claimedFunds;

    uint256 internal _feeMultiplier = 1;
    uint256 internal _feeDivisor = 1;

    struct SwapRequest {
        string toNetwork;
        string toAddress;
        uint256 value;
        uint256 unlockTimestamp;
        uint256 epoch;
        address monetaryPolicy;
    }

    event MigrateRequest(address indexed owner, string toNetwork, string toAddress, uint256 amount);

    function _verifySignature(bytes32 messageHash, bytes memory signature, address account) pure internal returns (bool) {
        return messageHash
        .toEthSignedMessageHash()
        .recover(signature) == account;
    }

    function _applyFee(uint256 amount) internal view returns(uint256) {
        return amount.mul(_feeMultiplier).div(_feeDivisor);
    }

    function _migrateToOtherChain(Token _stab, uint256 amount, string memory toNetwork,
        string memory toAddress, uint256 timeForUnlock, uint256 epoch) internal
    {
        require(timeForUnlock >= 60 * 60 && timeForUnlock <= 60 * 60 * 24, "time for unlock should be between 60 minutes and 24 hours.");
        // 1hr - 24hrs
        require(_stab.balanceOf(_msgSender()) >= amount, "Balance is to low.");

        // 1. User transfers own token to a monetary policy.
        // We use specially prepared send function which allows to skip approvals (only monetary policy can call it).
        uint256 baseValue = _stab.balanceOf(address(this));
        _stab.transferToMonetaryPolicy(_msgSender(), amount);
        uint256 amountBeforeFee = _stab.balanceOf(address(this)).sub(baseValue, "Amount after transfer is lower!");
        uint256 amountAfterFee = _applyFee(amountBeforeFee);
        _stab.burnMyTokens(amountAfterFee);

        // 2. Add swap request to pending swaps.
        SwapRequest memory newSwapRequest = SwapRequest({toNetwork : toNetwork, toAddress : toAddress,
            value : amountAfterFee, unlockTimestamp : block.timestamp + timeForUnlock, epoch : epoch,
            monetaryPolicy : address(this)});
        _swapRequests[_msgSender()].push(newSwapRequest);

        // 3. Notify backend about the request.
        emit MigrateRequest(_msgSender(), toNetwork, toAddress, amountAfterFee);
    }

    function _createMessageHash(uint256 id, address sendTo, uint256 amount, string memory chainName, uint256 epoch) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(id, sendTo, amount, chainName, epoch));
    }

    function _claimFromOtherChain(Token _stab, uint256 id, address sendTo, uint256 amount, string memory chainName,
        uint256 epoch, bytes memory signature, address whiteListedSigner) internal returns (bool) {
        bytes32 messageHash = _createMessageHash(id, sendTo, amount, chainName, epoch);
        if (_verifySignature(messageHash, signature, whiteListedSigner) == true) {
            require(_claimedFunds[messageHash] == false, "Funds already claimed.");
            _claimedFunds[messageHash] = true;
            _stab.mint(address(this), amount);
            return _stab.transfer(_msgSender(), amount);
        }
        return false;
    }
}
