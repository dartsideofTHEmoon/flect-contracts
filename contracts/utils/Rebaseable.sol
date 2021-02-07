// SPDX-License-Identifier:
/*
 *
 */

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of 'rebase able' coin type.
 */
abstract contract Rebaseable {
    /**
     * @dev Notifies STAB contract about a new rebase cycle.
     * @param exchangeRate Current STAB exchange rate.this
     * @param targetRate STAB price rebase target.
     * @param rebaseLag Rebase lag when rebaseLag > 1 or rebase leverage (when rebase lag < -1).
     * @return The total number of tokens after the supply adjustment.
     */
    function rebase(uint256 exchangeRate, uint256 targetRate, int256 rebaseLag) external virtual returns (uint256);

    /**
    * @dev Emitted when rebase started.
    */
    event LogRebase(uint256 indexed epoch, uint256 totalSupply, uint256 feeInEpoch);

    /**
    * @dev Emitted when monetary policy address changed.
    *
    * Note only monetary policy have access to rebase functionality.
    */
    event LogMonetaryPolicyUpdated(address monetaryPolicy);
}
