// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {Registry} from "../../contracts/core/Registry.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {ModuleKeys} from "../../contracts/libs/ModuleKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract RegistryInvoker {
    function callSetModule(address target, bytes32 key, address implementation) external returns (bool success) {
        (success, ) = target.call(abi.encodeWithSignature("setModule(bytes32,address)", key, implementation));
    }

    function callRemoveModule(address target, bytes32 key) external returns (bool success) {
        (success, ) = target.call(abi.encodeWithSignature("removeModule(bytes32)", key));
    }

    function callRollback(address target, bytes32 key) external returns (bool success) {
        (success, ) = target.call(abi.encodeWithSignature("rollback(bytes32)", key));
    }
}

contract RegistryTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    Registry private registry;

    address private constant MODULE_V1 = address(0x1111);
    address private constant MODULE_V2 = address(0x2222);

    function setUp() public {
        address controllerProxy = deployProxy(
            address(new AccessController(address(0), address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                AccessController.initialize.selector,
                address(this),
                address(0),
                address(0),
                address(0),
                address(this)
            )
        );
        controller = AccessController(controllerProxy);
        controller.grantRole(Roles.ROLE_MANAGER, address(this));
        controller.grantRole(Roles.ROLE_PAUSER, address(this));

        address flagsProxy = deployProxy(
            address(new FeatureFlags(address(0))),
            abi.encodeWithSelector(FeatureFlags.initialize.selector, controllerProxy)
        );
        flags = FeatureFlags(flagsProxy);

        address registryProxy = deployProxy(
            address(new Registry(address(0), address(0))),
            abi.encodeWithSelector(
                Registry.initialize.selector,
                controllerProxy,
                flagsProxy
            )
        );
        registry = Registry(registryProxy);
    }

    function test_REG_01_ModuleLifecycle() public {
        bytes32 key = ModuleKeys.ZIR_TOKEN;

        // Feature flag unset should block operations.
        callAndExpectRevert(
            address(registry),
            abi.encodeWithSignature("setModule(bytes32,address)", key, MODULE_V1),
            "REG-01: feature flag should block operations"
        );

        flags.setFlag(FeatureFlagKeys.REGISTRY, true);

        callAndExpectRevert(
            address(registry),
            abi.encodeWithSignature("setModule(bytes32,address)", key, address(0)),
            "REG-01: zero address should be rejected"
        );

        registry.setModule(key, MODULE_V1);
        assertEq(registry.getModule(key), MODULE_V1, "REG-01: initial module not recorded");

        address[] memory history = registry.getHistory(key);
        assertEq(history.length, 1, "REG-01: history should contain one entry");
        assertEq(history[0], MODULE_V1, "REG-01: history entry mismatch");

        callAndExpectRevert(
            address(registry),
            abi.encodeWithSignature("setModule(bytes32,address)", key, MODULE_V1),
            "REG-01: duplicate module assignments should revert"
        );

        registry.setModule(key, MODULE_V2);
        assertEq(registry.getModule(key), MODULE_V2, "REG-01: replacement failed");

        history = registry.getHistory(key);
        assertEq(history.length, 2, "REG-01: history should include replacement");
        assertEq(history[1], MODULE_V2, "REG-01: replacement history incorrect");

        registry.removeModule(key);
        assertEq(registry.getModule(key), address(0), "REG-01: module not removed");

        history = registry.getHistory(key);
        assertEq(history.length, 3, "REG-01: removal should append history entry");
        assertEq(history[2], address(0), "REG-01: removal history entry should be zero");

        registry.rollback(key);
        assertEq(registry.getModule(key), MODULE_V2, "REG-01: rollback should restore previous version");

        history = registry.getHistory(key);
        assertEq(history.length, 2, "REG-01: history length after rollback mismatch");

        registry.rollback(key);
        assertEq(registry.getModule(key), MODULE_V1, "REG-01: rollback to v1 failed");

        callAndExpectRevert(
            address(registry),
            abi.encodeWithSignature("rollback(bytes32)", key),
            "REG-01: further rollback should revert when history exhausted"
        );
    }

    function test_REG_01_OnlyManagerCanMutate() public {
        flags.setFlag(FeatureFlagKeys.REGISTRY, true);

        RegistryInvoker invoker = new RegistryInvoker();

        bool success = invoker.callSetModule(address(registry), ModuleKeys.ESCROW, MODULE_V1);
        assertFalse(success, "REG-01: non-manager should not set module");

        registry.setModule(ModuleKeys.ESCROW, MODULE_V1);

        success = invoker.callRemoveModule(address(registry), ModuleKeys.ESCROW);
        assertFalse(success, "REG-01: non-manager should not remove module");

        success = invoker.callRollback(address(registry), ModuleKeys.ESCROW);
        assertFalse(success, "REG-01: non-manager should not rollback module");
    }
}
