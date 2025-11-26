// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Protocol Custom Errors
/// @notice Central place for revert messages to keep bytecode size constrained.
library Errors {
    string internal constant UNAUTHORIZED = "ERR_UNAUTHORIZED";
    string internal constant FEATURE_DISABLED = "ERR_FEATURE_DISABLED";
    string internal constant FEATURE_NOT_CONFIGURED = "ERR_FEATURE_NOT_CONFIGURED";
    string internal constant MODULE_PAUSED = "ERR_MODULE_PAUSED";
    string internal constant INVALID_PARAMS = "ERR_INVALID_PARAMS";
    string internal constant INVALID_STATE = "ERR_INVALID_STATE";
    string internal constant BLACKLISTED = "ERR_BLACKLISTED";
    string internal constant FEE_ON_TRANSFER = "ERR_FEE_ON_TRANSFER";
    string internal constant GAS_ACCOUNTING = "ERR_GAS_ACCOUNTING";
}
