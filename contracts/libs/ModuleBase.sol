// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";
import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {FeatureFlagSupport} from "./FeatureFlagSupport.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {IAccessController} from "../interfaces/IAccessController.sol";
import {Errors} from "./Errors.sol";
import {Roles} from "./Roles.sol";

/// @notice Common base for protocol modules handling access control, pausing, and feature flags.
abstract contract ModuleBase is Initializable, Pausable, ReentrancyGuard, FeatureFlagSupport, UUPSUpgradeable {
    IAccessController public accessController;
    uint256[44] private __gap;

    event AccessControllerUpdated(address indexed previous, address indexed current);

    constructor(address accessController_, address featureFlags_) {
        if (accessController_ != address(0) && featureFlags_ != address(0)) {
            _initializerBefore();
            __ModuleBase_init_unchained(accessController_, featureFlags_);
            _initializerAfter();
        }
    }

    function __ModuleBase_init(address accessController_, address featureFlags_) internal onlyInitializing {
        __ModuleBase_init_unchained(accessController_, featureFlags_);
    }

    function __ModuleBase_init_unchained(address accessController_, address featureFlags_) internal onlyInitializing {
        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __FeatureFlagSupport_init(featureFlags_);
        __UUPSUpgradeable_init();
        _setAccessController(accessController_);
    }

    modifier onlyRole(bytes32 role) {
        _requireRole(role);
        _;
    }

    modifier onlyManager() {
        _requireRole(Roles.ROLE_MANAGER);
        _;
    }

    modifier onlyTreasurer() {
        _requireRole(Roles.ROLE_TREASURER);
        _;
    }

    modifier onlyArbiter() {
        _requireRole(Roles.ROLE_ARBITER);
        _;
    }

    modifier onlyPauser() {
        _requireRole(Roles.ROLE_PAUSER);
        _;
    }

    function pause() public virtual onlyPauser {
        _pause();
    }

    function unpause() public virtual onlyPauser {
        _unpause();
    }

    function _setAccessController(address accessController_) internal {
        require(accessController_ != address(0), "ModuleBase: access controller required");
        address previous = address(accessController);
        accessController = IAccessController(accessController_);
        emit AccessControllerUpdated(previous, accessController_);
    }

    function _requireRole(bytes32 role) internal view {
        if (!accessController.hasRole(role, _msgSender())) {
            revert(Errors.UNAUTHORIZED);
        }
    }

    function _authorizeUpgrade(address) internal view override {
        if (!accessController.hasRole(Roles.ROLE_UPGRADER, _msgSender())) {
            revert(Errors.UNAUTHORIZED);
        }
    }
}
