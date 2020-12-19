// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.3.0/contracts/math/SafeMath.sol";
/**
 * @dev Library for managing hodlings time.
 *
 * Types were adjusted to project requirements.
 */
library EnumerableFifo {
    using SafeMath for uint256;

    struct Entry {
        uint32 _key;
        uint32 _nextKey;
        uint256 _value;
    }

    struct Map {
        // Storage of map keys and values
        mapping (uint32 => Entry) _entries;

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
        map._entries[key] = Entry({ _key: key, _nextKey: 0, _value: value });
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
        if (entry._nextKey == 0) { // Removing last entry in queue.
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

    // U32ToU256Map

    struct U32ToU256Queue {
        Map _inner;
    }

    /**
     * @dev Adds value to an existing key or creates a new one.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(U32ToU256Queue storage map, uint32 key, uint256 value) internal {
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
     * @dev Subtracts value from existing key.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow, result must be positive.
     */
    function sub(U32ToU256Queue storage map, uint32 key, uint256 value) internal {
        require(key > 0);
        require(value > 0);
        require(value <= map._inner._sum);

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
    function flatten(U32ToU256Queue storage map, uint32 minAllowedKey) internal {
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
}
