// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Common Constants and Types
/// @notice Holds global constants and shared enums for the Zircle protocol.
abstract contract Common {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant ZIR_DECIMALS = 1e6;
    uint256 internal constant YEAR = 365 days;
}
