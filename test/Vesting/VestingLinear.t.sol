// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {VestingLinear} from "../../contracts/modules/vesting/VestingLinear.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract VestingLinearTest is TestBase {
    uint256 private constant ONE_ZIR = 1_000_000;

    AccessController private controller;
    FeatureFlags private flags;
    ZIR private zir;
    VestingLinear private vesting;
    address private beneficiary;

    function setUp() public {
        beneficiary = vm.addr(0xBEEF);

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

        address flagsProxy = deployProxy(
            address(new FeatureFlags(address(0))),
            abi.encodeWithSelector(FeatureFlags.initialize.selector, controllerProxy)
        );
        flags = FeatureFlags(flagsProxy);

        address zirProxy = deployProxy(
            address(new ZIR(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                ZIR.initialize.selector,
                controllerProxy,
                flagsProxy,
                address(this)
            )
        );
        zir = ZIR(zirProxy);
        flags.setFlag(FeatureFlagKeys.ZIR_TOKEN, true);

        address vestingProxy = deployProxy(
            address(new VestingLinear(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                VestingLinear.initialize.selector,
                controllerProxy,
                flagsProxy,
                zirProxy
            )
        );
        vesting = VestingLinear(vestingProxy);
        flags.setFlag(FeatureFlagKeys.VESTING, true);

        bool funded = zir.transfer(address(vesting), 10_000 * ONE_ZIR);
        assertTrue(funded, "VES-Linear: funding vesting contract failed");
    }

    function test_VES_01_CliffZeroAndDelayed() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = uint64(30 days);
        uint64 cliff = 0;
        vesting.createOrUpdateSchedule(beneficiary, 3_000 * ONE_ZIR, start, cliff, duration);

        vm.warp(start + 15 days);
        vm.prank(beneficiary);
        vesting.release();
        uint256 received = zir.balanceOf(beneficiary);
        uint256 expected = (3_000 * ONE_ZIR * 15 days) / duration;
        uint256 tol = expected / 50;
        assertTrue(received >= expected - tol && received <= expected + tol, "VES-01: cliff zero vest");

        address beneficiary2 = vm.addr(uint256(0xBEEF) + 1);
        start = uint64(block.timestamp);
        duration = uint64(60 days);
        cliff = uint64(20 days);
        vesting.createOrUpdateSchedule(beneficiary2, 6_000 * ONE_ZIR, start, cliff, duration);
        vm.warp(start + 10 days);
        vm.prank(beneficiary2);
        bool success;
        (success, ) = address(vesting).call(abi.encodeWithSignature("release()"));
        assertFalse(success, "VES-01: release before cliff should revert");
    }

    function test_VES_02_ReplenishConsistency() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = uint64(40 days);
        vesting.createOrUpdateSchedule(beneficiary, 4_000 * ONE_ZIR, start, 0, duration);

        vm.warp(start + 20 days);
        vm.prank(beneficiary);
        vesting.release();
        uint256 firstClaim = zir.balanceOf(beneficiary);

        vesting.createOrUpdateSchedule(beneficiary, 6_000 * ONE_ZIR, start, 0, duration);
        vm.warp(start + 30 days);
        vm.prank(beneficiary);
        vesting.release();

        uint256 totalClaimed = zir.balanceOf(beneficiary);
        uint256 vested = (6_000 * ONE_ZIR * 30 days) / duration;
        uint256 tol = vested / 50;
        assertTrue(totalClaimed >= vested - tol && totalClaimed <= vested + tol, "VES-02: replenishment inconsistent");
        assertTrue(totalClaimed > firstClaim, "VES-02: second claim should exceed first");
    }
}
