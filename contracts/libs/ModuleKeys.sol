// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Registry Module Keys
/// @notice Declares registry keys for module lookup.
library ModuleKeys {
    bytes32 internal constant ACCESS_CONTROLLER = keccak256("MODULE_ACCESS_CONTROLLER");
    bytes32 internal constant FEATURE_FLAGS = keccak256("MODULE_FEATURE_FLAGS");
    bytes32 internal constant ZIR_TOKEN = keccak256("MODULE_ZIR_TOKEN");
    bytes32 internal constant ESCROW = keccak256("MODULE_ESCROW");
    bytes32 internal constant TREASURY = keccak256("MODULE_TREASURY");
    bytes32 internal constant PRICE_ORACLE = keccak256("MODULE_PRICE_ORACLE");
    bytes32 internal constant STAKING = keccak256("MODULE_STAKING");
    bytes32 internal constant REPUTATION = keccak256("MODULE_REPUTATION");
    bytes32 internal constant DISTRIBUTOR = keccak256("MODULE_DISTRIBUTOR");
    bytes32 internal constant VESTING_LINEAR = keccak256("MODULE_VESTING_LINEAR");
    bytes32 internal constant VESTING_MERKLE = keccak256("MODULE_VESTING_MERKLE");
    bytes32 internal constant REGISTRY = keccak256("MODULE_REGISTRY");
}
