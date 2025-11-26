// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../contracts/libs/ModuleBase.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {AccessController} from "../../contracts/access/AccessController.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockModule is ModuleBase {
    bool public executed;
    uint256 public callCount;

    constructor() ModuleBase(address(0), address(0)) {}

    function initialize(address accessController_, address featureFlags_) external initializer {
        __ModuleBase_init(accessController_, featureFlags_);
    }

    function doSomething() external nonReentrant whenNotPaused whenFeatureEnabled(FeatureFlagKeys.ESCROW) {
        executed = true;
        unchecked {
            callCount += 1;
        }
    }
}

contract ModuleBaseTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    MockModule private module;

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

        address moduleProxy = deployProxy(
            address(new MockModule()),
            abi.encodeWithSelector(
                MockModule.initialize.selector,
                controllerProxy,
                flagsProxy
            )
        );
        module = MockModule(moduleProxy);
    }

    function test_ALL_02_PauseBlocksOperations() public {
        flags.setFlag(FeatureFlagKeys.ESCROW, true);
        module.doSomething();
        assertEq(module.callCount(), 1, "ALL-02: first call count mismatch");

        module.pause();

        (bool success, ) = address(module).call(abi.encodeWithSignature("doSomething()"));
        assertFalse(success, "ALL-02: paused module should reject operations");

        module.unpause();
        module.doSomething();
        assertEq(module.callCount(), 2, "ALL-02: call count should increment after unpause");
    }

    function test_ALL_03_FeatureStrictMode() public {
        (bool success, ) = address(module).call(abi.encodeWithSignature("doSomething()"));
        assertFalse(success, "ALL-03: should revert when feature not configured");

        flags.setFlag(FeatureFlagKeys.ESCROW, true);
        module.doSomething();
        assertTrue(module.executed(), "ALL-03: should execute once feature enabled");
    }
}
