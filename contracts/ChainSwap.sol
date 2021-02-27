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

    struct SwapRequest {
        string toNetwork;
        string toAddress;
        uint256 value;
        uint256 unlockTimestamp;
        address monetaryPolicy;
    }

    function _getUnlockAmount(address recipient) internal returns (uint256) {
        uint256 amount = 0;

        for (uint256 i = 0; i < _swapRequests[recipient].length; i++) {
            if (block.timestamp > _swapRequests[recipient][i].unlockTimestamp) {// already unlocked.
                amount = amount.add(_swapRequests[recipient][i].value);
                delete _swapRequests[recipient][i];
            }
        }

        return amount;
    }

    function _verifySignature(bytes32 messageHash, bytes memory signature, address account) pure internal returns (bool) {
        return messageHash
        .toEthSignedMessageHash()
        .recover(signature) == account;
    }

    function _migrateToOtherChain(Token _stab, uint256 amount, string memory toNetwork,
        string memory toAddress, uint256 timeForUnlock) internal
    {
        require(timeForUnlock >= 60 * 60 && timeForUnlock <= 60 * 60 * 24, "time for unlock should be between 60 minutes and 24 hours.");
        // 1hr - 24hrs
        require(_stab.balanceOf(_msgSender()) >= amount, "Balance is to low.");

        // 1. User transfers own token to a monetary policy.
        // We use specially prepared send function which allows to skip approvals (only monetary policy can call it).
        uint baseValue = _stab.balanceOf(address(this));
        _stab.transferToMonetaryPolicy(_msgSender(), amount);
        uint amountAfterFee = _stab.balanceOf(address(this)).sub(baseValue, "Amount after transfer is lower!");
        // TODO we have to apply rebase to SwapRequest values as well.

        // 2. Add swap request to pending swaps.
        SwapRequest memory newSwapRequest = SwapRequest({toNetwork : toNetwork, toAddress : toAddress,
            value : amountAfterFee, unlockTimestamp : block.timestamp + timeForUnlock, monetaryPolicy : address(this)});
        _swapRequests[_msgSender()].push(newSwapRequest);

        // 3. Notify backend about the request.
        emit MigrateRequest(_msgSender(), toNetwork, toAddress, amountAfterFee);
    }

    function _createMessageHash(uint64 id, address sendTo, uint256 amount, string memory chainName) internal returns (bytes32) {
        return keccak256(abi.encodePacked(id, sendTo, amount, chainName));
    }

    function _claimFromOtherChain(Token _stab, uint64 id, address sendTo, uint256 amount, string memory chainName,
        bytes memory signature, address whiteListedSigner) internal {
        bytes32 messageHash = _createMessageHash(id, sendTo, amount, chainName);
        if (_verifySignature(messageHash, signature, whiteListedSigner) == true) {
            require(_claimedFunds[messageHash] == false, "Funds already claimed.");
            _claimedFunds[messageHash] = true;
            _stab.mint(address(this), amount);
            _stab.transfer(_msgSender(), amount);
        }
    }

    event MigrateRequest(address indexed owner, string toNetwork, string toAddress, uint256 amount);
}
