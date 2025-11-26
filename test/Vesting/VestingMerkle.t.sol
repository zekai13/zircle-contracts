// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {VestingMerkle} from "../../contracts/modules/vesting/VestingMerkle.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract VestingMerkleTest is TestBase {
    uint256 private constant ONE_ZIR = 1_000_000;

    AccessController private controller;
    FeatureFlags private flags;
    ZIR private zir;
    VestingMerkle private vesting;
    address private alice;
    address private bob;

    function setUp() public {
        alice = vm.addr(0xAAA1);
        bob = vm.addr(0xAAA2);

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
            address(new VestingMerkle(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                VestingMerkle.initialize.selector,
                controllerProxy,
                flagsProxy,
                zirProxy
            )
        );
        vesting = VestingMerkle(vestingProxy);
        flags.setFlag(FeatureFlagKeys.VESTING, true);

        bool funded = zir.transfer(address(vesting), 5_000 * ONE_ZIR);
        assertTrue(funded, "VES-Merkle: funding vesting contract failed");
    }

    function test_VES_03_MerkleClaimsAndDoubleSpend() public {
        uint64 scheduleStart = 1;
        vm.warp(scheduleStart);
        uint64 cliff = 0;
        uint64 duration = uint64(30 days);

        bytes32 leafAlice = _leaf(alice, 2_000 * ONE_ZIR, scheduleStart, cliff, duration);
        bytes32 leafBob = _leaf(bob, 1_000 * ONE_ZIR, scheduleStart, cliff, duration);
        bytes32 root = leafBob <= leafAlice
            ? keccak256(abi.encodePacked(leafBob, leafAlice))
            : keccak256(abi.encodePacked(leafAlice, leafBob));
        vesting.setMerkleRoot(root);

        vm.warp(scheduleStart + 15 days);
        bytes32[] memory proofBob = new bytes32[](1);
        proofBob[0] = leafAlice;

        vm.prank(bob);
        vesting.claim(1_000 * ONE_ZIR, scheduleStart, cliff, duration, 400 * ONE_ZIR, proofBob);
        assertEq(zir.balanceOf(bob), 400 * ONE_ZIR, "VES-03: first claim mismatch");

        vm.warp(scheduleStart + 20 days);
        vm.prank(bob);
        vesting.claim(1_000 * ONE_ZIR, scheduleStart, cliff, duration, 200 * ONE_ZIR, proofBob);
        assertEq(zir.balanceOf(bob), 600 * ONE_ZIR, "VES-03: cumulative claim mismatch");

        vm.prank(bob);
        bool success;
        (success, ) = address(vesting).call(
            abi.encodeWithSignature(
                "claim(uint256,uint64,uint64,uint64,uint256,bytes32[])",
                1_000 * ONE_ZIR,
                scheduleStart,
                cliff,
                duration,
                500 * ONE_ZIR,
                proofBob
            )
        );
        assertFalse(success, "VES-03: cannot exceed vested");

        // invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(123));
        vm.prank(alice);
        (success, ) = address(vesting).call(
            abi.encodeWithSignature(
                "claim(uint256,uint64,uint64,uint64,uint256,bytes32[])",
                2_000 * ONE_ZIR,
                scheduleStart,
                cliff,
                duration,
                100 * ONE_ZIR,
                invalidProof
            )
        );
        assertFalse(success, "VES-03: invalid proof should revert");
    }

    function _leaf(
        address account,
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, total, start, cliff, duration));
    }

}
