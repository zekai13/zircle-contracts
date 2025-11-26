// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Feature Flag Keys
/// @notice Helps keep feature keys consistent across the system.
library FeatureFlagKeys {
    bytes32 internal constant ESCROW = keccak256("FEATURE_ESCROW");
    bytes32 internal constant ZIR_TOKEN = keccak256("FEATURE_ZIR");
    bytes32 internal constant TREASURY = keccak256("FEATURE_TREASURY");
    bytes32 internal constant REGISTRY = keccak256("FEATURE_REGISTRY");
    bytes32 internal constant STAKING = keccak256("FEATURE_STAKING");
    bytes32 internal constant REPUTATION = keccak256("FEATURE_REPUTATION");
    bytes32 internal constant DISTRIBUTOR = keccak256("FEATURE_DISTRIBUTOR");
    bytes32 internal constant VESTING = keccak256("FEATURE_VESTING");
    bytes32 internal constant ORACLE = keccak256("FEATURE_ORACLE");
    bytes32 internal constant ESCROW_VAULT = keccak256("FEATURE_ESCROW_VAULT");
}
