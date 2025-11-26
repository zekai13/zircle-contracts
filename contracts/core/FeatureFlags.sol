// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "../libs/Initializable.sol";
import {UUPSUpgradeable} from "../libs/UUPSUpgradeable.sol";
import {IAccessController} from "../interfaces/IAccessController.sol";
import {Errors} from "../libs/Errors.sol";
import {Roles} from "../libs/Roles.sol";

/// @title FeatureFlags
/// @notice Stores boolean toggles for feature gating across modules.
contract FeatureFlags is Initializable, UUPSUpgradeable {
    struct Flag {
        bool enabled;
        bool exists;
        uint64 updatedAt;
    }

    event FeatureToggled(bytes32 indexed key, bool enabled);

    mapping(bytes32 => Flag) private _flags;
    IAccessController public accessController;
    uint256[49] private __gap;

    constructor(address accessController_) {
        if (accessController_ != address(0)) {
            initialize(accessController_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_) public initializer {
        require(accessController_ != address(0), "FeatureFlags: access controller required");
        __UUPSUpgradeable_init();
        accessController = IAccessController(accessController_);
    }

    modifier onlyManager() {
        _onlyManager();
        _;
    }

    function _onlyManager() internal view {
        if (!accessController.hasRole(Roles.ROLE_MANAGER, msg.sender)) {
            revert(Errors.UNAUTHORIZED);
        }
    }

    function setFlag(bytes32 key, bool enabled) external onlyManager {
        Flag storage flag = _flags[key];
        flag.enabled = enabled;
        flag.exists = true;
        flag.updatedAt = uint64(block.timestamp);
        emit FeatureToggled(key, enabled);
    }

    function isEnabled(bytes32 key) external view returns (bool) {
        return _flags[key].enabled;
    }

    function flagInfo(bytes32 key) external view returns (Flag memory) {
        return _flags[key];
    }

    function requireEnabled(bytes32 key, bool strict) external view {
        _requireFeature(key, strict);
    }

    function _requireFeature(bytes32 key, bool strict) internal view returns (bool) {
        Flag memory flag = _flags[key];
        if (!flag.exists) {
            if (strict) revert(Errors.FEATURE_NOT_CONFIGURED);
            return false;
        }
        if (!flag.enabled) {
            revert(Errors.FEATURE_DISABLED);
        }
        return true;
    }

    function _authorizeUpgrade(address) internal view override {
        if (!accessController.hasRole(Roles.ROLE_UPGRADER, msg.sender)) {
            revert(Errors.UNAUTHORIZED);
        }
    }
}
