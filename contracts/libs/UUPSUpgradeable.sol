// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";
import {Context} from "./Context.sol";
import {ERC1967Upgrade} from "./ERC1967Upgrade.sol";

/// @notice Minimal UUPS upgrade pattern mixin.
abstract contract UUPSUpgradeable is Initializable, Context, ERC1967Upgrade {
    function __UUPSUpgradeable_init() internal onlyInitializing {}

    /// @notice Upgrade the implementation of the proxy to `newImplementation`.
    function upgradeTo(address newImplementation) external {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, bytes(""), false);
    }

    /// @notice Upgrade implementation and execute call.
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    /// @notice Must be overridden to include access control to upgrades.
    function _authorizeUpgrade(address newImplementation) internal virtual;
}
