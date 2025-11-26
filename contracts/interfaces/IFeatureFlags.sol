// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeatureFlags {
    struct Flag {
        bool enabled;
        bool exists;
        uint64 updatedAt;
    }

    function isEnabled(bytes32 key) external view returns (bool);

    function requireEnabled(bytes32 key, bool strict) external view;

    function flagInfo(bytes32 key) external view returns (Flag memory);
}
