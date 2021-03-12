// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./UInt256Lib.sol";
import "./SafeMathInt.sol";
/**
 * @dev Library for managing hodlings time.
 *
 * Types were adjusted to project requirements.
 */
library EnumerableFifo {
    using SafeMathUpgradeable for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    struct Entry {
        uint32 _key;
        uint32 _nextKey;
        uint256 _value;
    }

    struct Map {
        // Storage of map keys and values
        mapping(uint32 => Entry) _entries;

        uint256 _sum;

        uint32 _lastKey;
        uint32 _firstKey;
    }

    /**
     * @dev Adds a key-value pair to a queue on the last position. O(1).
     *
     */
    function _enqueue(Map storage map, uint32 key, uint256 value) private {
        if (map._firstKey == 0) {
            map._firstKey = key;
        }
        if (map._lastKey != 0) {
            map._entries[map._lastKey]._nextKey = key;
        }
        map._entries[key] = Entry({_key : key, _nextKey : 0, _value : value});
        map._lastKey = key;
        map._sum = map._sum.add(value);
    }

    /**
     * @dev Removes a key-value pair from a queue on the first position. O(1).
     *
     */
    function _dequeue(Map storage map) private returns (uint256) {
        if (map._firstKey == 0) {
            // Nothing to do, empty queue
            return 0;
        }
        Entry storage entry = map._entries[map._firstKey];
        uint32 firstKey = map._firstKey;
        uint256 value = entry._value;
        if (entry._nextKey == 0) {// Removing last entry in queue.
            map._firstKey = 0;
            map._lastKey = 0;
            map._sum = 0;
        } else {
            map._firstKey = entry._nextKey;
            map._sum = map._sum.sub(value);
        }
        delete map._entries[firstKey];

        return (value);
    }

    /**
     * @dev Gets next entry using their key.
     */
    function _get(Map storage map, uint32 key) private view returns (uint32, uint32, uint256) {
        Entry storage entry = map._entries[key];
        return (entry._key, entry._nextKey, entry._value);
    }

    /**
     * @dev Gets the first entry in a queue.
     */
    function _getFirst(Map storage map) private view returns (uint32, uint32, uint256) {
        if (map._firstKey == 0) {
            return (0, 0, 0);
        }

        Entry storage entry = map._entries[map._firstKey];
        return (entry._key, entry._nextKey, entry._value);
    }

    /**
     * @dev Gets the last entry in a queue.
     */
    function _getLast(Map storage map) private view returns (uint32, uint256) {
        if (map._lastKey == 0) {
            return (0, 0);
        }

        Entry storage entry = map._entries[map._lastKey];
        return (entry._key, entry._value);
    }

    /**
     * @dev Updates a value of the first entry in a queue.
     */
    function _updateFirstValue(Map storage map, uint256 newValue) private {
        require(map._firstKey > 0);
        uint256 oldValue = map._entries[map._firstKey]._value;
        map._sum = map._sum.sub(oldValue).add(newValue);
        map._entries[map._firstKey]._value = newValue;
    }

    /**
     * @dev Updates a value of the last entry in a queue.
     */
    function _updateLastValue(Map storage map, uint256 newValue) private {
        require(map._lastKey > 0);
        uint256 oldValue = map._entries[map._lastKey]._value;
        map._sum = map._sum.sub(oldValue).add(newValue);
        map._entries[map._lastKey]._value = newValue;
    }

    /**
     * @dev Updates a value of the last entry in a queue.
     */
    function _updateValueAtKey(Map storage map, uint32 key, uint256 newValue) private {
        require(key > 0);
        uint256 oldValue = map._entries[key]._value;
        require(oldValue > 0);
        // Check if this value exists.

        map._sum = map._sum.sub(oldValue).add(newValue);
        map._entries[key]._value = newValue;
    }

    // U32ToU256Map

    struct U32ToU256Queue {
        Map _inner;
    }

    /**
     * @dev Gets sum of account balance.
     */
    function getSum(U32ToU256Queue storage map) public view returns (uint256) {
        return map._inner._sum;
    }

    /**
     * @dev Adds value to an existing key or creates a new one.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(U32ToU256Queue storage map, uint32 key, uint256 value) public {
        require(key > 0);
        require(value > 0);

        (uint32 lastKey, uint256 lastValue) = _getLast(map._inner);
        if (key == lastKey) {
            _updateLastValue(map._inner, lastValue.add(value));
        } else {
            _enqueue(map._inner, key, value);
        }
    }

    /**
     * @dev Subtracts value from existing beginning of the queue.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow, result must be positive.
     */
    function sub(U32ToU256Queue storage map, uint256 value) public {
        require(value > 0);
        require(value <= map._inner._sum, "Not enough balance");

        uint256 leftToSub = value;
        (uint32 currentKey, uint32 nextKey, uint256 currentValue) = _getFirst(map._inner);
        while (currentKey != 0) {
            if (currentValue <= leftToSub) {
                _dequeue(map._inner);
                leftToSub = leftToSub.sub(currentValue);
            } else {
                currentValue = currentValue.sub(leftToSub);
                _updateFirstValue(map._inner, currentValue);
                return;
            }

            (currentKey, nextKey, currentValue) = _get(map._inner, nextKey);
        }
    }

    /**
     * @dev Removes history older than minAllowedKey.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow, result must be positive.
     */
    function flatten(U32ToU256Queue storage map, uint32 minAllowedKey) public {
        uint256 cumulativeValue = 0;
        (uint32 currentKey, uint32 nextKey, uint256 currentValue) = _getFirst(map._inner);
        while (currentKey != 0) {
            if (currentKey < minAllowedKey) {
                uint256 dequeueValue = _dequeue(map._inner);
                cumulativeValue = cumulativeValue.add(dequeueValue);
            } else {
                if (cumulativeValue > 0) {
                    _updateFirstValue(map._inner, cumulativeValue.add(currentValue));
                    cumulativeValue = 0;
                }
                break;
            }

            (currentKey, nextKey, currentValue) = _get(map._inner, nextKey);
        }
        // All keys were lower than 'minAllowedKey', so we have to create a new entry.
        if (cumulativeValue > 0) {
            _enqueue(map._inner, minAllowedKey, cumulativeValue);
        }
    }

    /*
    * @dev Rebases user funds and returns value diff.
    * @param preRebaseRate Current user shares vs all tokens in network.
    * @param postRebaseRate User tokens share after rebase (it is used to add earned fee to user account for good).
    * @param maxIncentiveEpoch Epoch which gives user maxFactor.
    * @param factorDecreasePerStep User incentive drops by that number each epoch. It is 10**DECIMALS based value.
    * @param maxFactor Maximum incentive possible for epoch <= minAllowedKey. It is 10**DECIMALS based value.
    * @param valuesArray 4 uint256 values (preRebaseRate, postRebaseRate, currentNetMultiplier, UNIT).
        Array is used to avoid EVM limit for 16 local variables.
    */
    function rebaseUserFunds(U32ToU256Queue storage map, uint32 maxIncentiveEpoch, uint256 factorDecreasePerEpoch,
        uint256 maxFactor, uint256[4] memory valuesArray) public returns (int256) {

        int256 originalSum = map._inner._sum.toInt256Safe();

        (uint32 currentKey, uint32 nextKey, uint256 currentValue) = _getFirst(map._inner);
        while (currentKey != 0) {
            uint256 rebaseFactor = maxFactor;
            if (currentKey > maxIncentiveEpoch) {
                uint32 epochDiff = currentKey - maxIncentiveEpoch;
                uint256 decreaseValue = factorDecreasePerEpoch.mul(epochDiff);
                rebaseFactor = maxFactor.sub(decreaseValue, "Max user adjusted rebase factor cannot be lower than 0");
            }
            _updateValueAtKey(map._inner, currentKey, adjustValue(currentValue, rebaseFactor, valuesArray, false));

            (currentKey, nextKey, currentValue) = _get(map._inner, nextKey);
        }

        int256 newSum = map._inner._sum.toInt256Safe();
        return newSum.sub(originalSum).div(valuesArray[0].toInt256Safe());
    }

    /*
    * @dev Calculates user adjusted rebase factor.
    * @param value User funds.
    * @param userIncentiveFactor Special incentive param for user.
    * @param valuesArray 4 uint256 values (preRebaseRate, postRebaseRate, currentNetMultiplier, UNIT).
    */
    function adjustValue(uint256 value, uint256 userIncentiveFactor, uint256[4] memory valuesArray, bool excluded)
        public pure returns (uint256) {

        uint256 currentNetMultiplier = valuesArray[2];
        uint256 valuesBase = valuesArray[3];

        if (!excluded) {
            value = value.div(valuesArray[0]);
        }

        // Unwraps amount from 'reflection' to token.
        if (currentNetMultiplier < valuesBase) {
            // Multiplier is lower than '1 * 10**DECIMALS', so we have to decrease funds.
            // for e.g.
            // userIncentiveFactor == 4 * 10**DECIMALS, currentNetMultiplier == 0.8 * 10**DECIMALS, valuesBase == 10**DECIMALS
            uint256 multiplier = valuesBase.sub(currentNetMultiplier);
            // (1 - 0.8) * 10**DECIMALS
            multiplier = multiplier.mul(valuesBase).div(userIncentiveFactor);
            // 0.2 * 10**DECIMALS * 10**DECIMALS / (4 * 10**DECIMALS) => 0.05 * 10**DECIMALS
            multiplier = valuesBase.sub(multiplier);
            // (1 - 0.05) * 10**DECIMALS
            value = value.mul(multiplier).div(valuesBase);
            // newValue = oldValue * (0.95 * 10**DECIMALS) / 10**DECIMALS
        } else {
            // Multiplier is bigger than '1 * 10**DECIMALS', so we have to increase funds.
            // for e.g.
            // userIncentiveFactor == 4 * 10**DECIMALS, currentNetMultiplier == 1.15 * 10**DECIMALS, valuesBase == 10**DECIMALS
            uint256 multiplier = currentNetMultiplier.sub(valuesBase);
            // (1.15 - 1) * 10**DECIMALS
            multiplier = multiplier.mul(userIncentiveFactor).div(valuesBase);
            // 0.15 * 10**DECIMALS * 4 * 10**DECIMALS / 10**DECIMALS => 0.6 * 10**DECIMALS
            multiplier = multiplier.add(valuesBase);
            // 0.6 * 10**DECIMALS + 10**DECIMALS = 1.6 * 10**DECIMALS
            value = value.mul(multiplier).div(valuesBase);
        }
        // Wraps amount with 'reflection' with a new rate. New rate is bigger, because user earned fee (if there was at
        // least 1 transaction in passing epoch).
        if (!excluded) {
            return value.mul(valuesArray[1]);
        }
        return value;
    }
}