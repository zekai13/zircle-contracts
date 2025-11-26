// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {TestBase} from "../utils/TestBase.sol";

contract FlagExternalCaller {
    function trySetFlag(address featureFlags, bytes32 key, bool enabled) external returns (bool success) {
        (success, ) = featureFlags.call(abi.encodeWithSignature("setFlag(bytes32,bool)", key, enabled));
    }
}

contract FeatureFlagsTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;

    bytes32 private constant KEY = keccak256("TEST_FEATURE");

    function setUp() public {
        address controllerProxy = deployProxy(
            address(new AccessController(address(0), address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                AccessController.initialize.selector,
                address(this),
                address(0),
                address(0),
                address(0),
                address(0)
            )
        );
        controller = AccessController(controllerProxy);

        address flagsProxy = deployProxy(
            address(new FeatureFlags(address(0))),
            abi.encodeWithSelector(FeatureFlags.initialize.selector, controllerProxy)
        );
        flags = FeatureFlags(flagsProxy);
        controller.grantRole(Roles.ROLE_MANAGER, address(this));
    }

    function test_FF_01_StrictModeBlocksWhenUnset() public view {
        bool reverted;
        try flags.requireEnabled(KEY, true) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "FF-01: expected revert for unset feature in strict mode");
    }

    function test_FF_02_ToggleImmediateEffect() public {
        flags.setFlag(KEY, true);

        assertTrue(flags.isEnabled(KEY), "FF-02: flag should enable immediately");

        bool reverted;
        try flags.requireEnabled(KEY, true) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertFalse(reverted, "FF-02: strict check should pass once enabled");

        flags.setFlag(KEY, false);

        try flags.requireEnabled(KEY, true) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "FF-02: strict check should fail after disabling");
    }

    function test_ALL_01_ManagerOnlyCanToggle() public {
        FlagExternalCaller caller = new FlagExternalCaller();
        bool success = caller.trySetFlag(address(flags), KEY, true);
        assertFalse(success, "ALL-01: non-manager should not toggle features");
    }
}
