// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Role Constants
/// @notice Keeps role identifiers consistent across modules.
library Roles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ROLE_MANAGER = keccak256("ROLE_MANAGER");
    bytes32 internal constant ROLE_TREASURER = keccak256("ROLE_TREASURER");
    bytes32 internal constant ROLE_ARBITER = keccak256("ROLE_ARBITER");
    bytes32 internal constant ROLE_PAUSER = keccak256("ROLE_PAUSER");
    bytes32 internal constant ROLE_UPGRADER = keccak256("ROLE_UPGRADER");
    bytes32 internal constant ROLE_VAULT_CALLER = keccak256("ROLE_VAULT_CALLER");
    bytes32 internal constant ROLE_SHIP_EXECUTOR = keccak256("ROLE_SHIP_EXECUTOR");
}
