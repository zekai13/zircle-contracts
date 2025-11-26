// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";
import {IFeatureFlags} from "../interfaces/IFeatureFlags.sol";

/// @dev Provides the whenFeatureEnabled modifier for modules.
abstract contract FeatureFlagSupport is Initializable {
    IFeatureFlags public featureFlags;
    uint256[49] private __gap;

    event FeatureFlagsUpdated(address indexed previous, address indexed current);

    function __FeatureFlagSupport_init(address featureFlags_) internal onlyInitializing {
        _setFeatureFlags(featureFlags_);
    }

    modifier whenFeatureEnabled(bytes32 key) {
        _whenFeatureEnabled(key);
        _;
    }

    function _whenFeatureEnabled(bytes32 key) internal view {
        featureFlags.requireEnabled(key, true);
    }

    function _setFeatureFlags(address featureFlags_) internal {
        require(featureFlags_ != address(0), "FeatureFlagSupport: zero address");
        address previous = address(featureFlags);
        featureFlags = IFeatureFlags(featureFlags_);
        emit FeatureFlagsUpdated(previous, featureFlags_);
    }
}
