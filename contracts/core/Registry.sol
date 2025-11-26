// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../libs/FeatureFlagKeys.sol";
import {Errors} from "../libs/Errors.sol";

/// @title Module Registry
/// @notice Tracks deployed module implementations with upgrade history and rollback.
contract Registry is ModuleBase {
    struct ModuleHistory {
        address[] versions;
    }

    mapping(bytes32 => address) private _modules;
    mapping(bytes32 => ModuleHistory) private _histories;

    event ModuleRegistered(bytes32 indexed key, address indexed implementation);
    event ModuleReplaced(bytes32 indexed key, address indexed previousImplementation, address indexed newImplementation);
    event ModuleRemoved(bytes32 indexed key, address indexed implementation);
    event ModuleRolledBack(bytes32 indexed key, address indexed fromImplementation, address indexed toImplementation);

    constructor(address accessController_, address featureFlags_) ModuleBase(address(0), address(0)) {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
    }

    function setModule(bytes32 key, address implementation)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REGISTRY)
    {
        require(key != bytes32(0), "Registry: empty key");
        require(implementation != address(0), "Registry: zero implementation");

        address current = _modules[key];
        if (current == implementation) {
            revert(Errors.INVALID_PARAMS);
        }

        _modules[key] = implementation;
        ModuleHistory storage history = _histories[key];
        history.versions.push(implementation);

        if (current == address(0)) {
            emit ModuleRegistered(key, implementation);
        } else {
            emit ModuleReplaced(key, current, implementation);
        }
    }

    function removeModule(bytes32 key)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REGISTRY)
    {
        address current = _modules[key];
        require(current != address(0), "Registry: module not set");

        _modules[key] = address(0);
        _histories[key].versions.push(address(0));

        emit ModuleRemoved(key, current);
    }

    function rollback(bytes32 key)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REGISTRY)
    {
        ModuleHistory storage history = _histories[key];
        uint256 length = history.versions.length;
        require(length >= 2, "Registry: no rollback target");

        address current = history.versions[length - 1];
        address previous = history.versions[length - 2];

        history.versions.pop();
        _modules[key] = previous;

        emit ModuleRolledBack(key, current, previous);
    }

    function getModule(bytes32 key) external view returns (address) {
        return _modules[key];
    }

    function getHistory(bytes32 key) external view returns (address[] memory history) {
        address[] storage versions = _histories[key].versions;
        history = new address[](versions.length);
        for (uint256 i = 0; i < versions.length; i++) {
            history[i] = versions[i];
        }
    }

    uint256[45] private __gap;
}
