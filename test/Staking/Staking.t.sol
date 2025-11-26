// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {StakingModule} from "../../contracts/modules/staking/StakingModule.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";
import {IReputation} from "../../contracts/interfaces/IReputation.sol";

contract ReputationMock is IReputation {
    struct RepData {
        int256 score;
        bool underPenalty;
    }

    mapping(address => RepData) internal reps;

    function setReputation(address account, int256 score, bool underPenalty) external {
        reps[account] = RepData(score, underPenalty);
    }

    function recordTrade(address) external pure override returns (int256) {
        return 0;
    }

    function recordArbitrationWin(address) external pure override returns (int256) {
        return 0;
    }

    function recordArbitrationLoss(address) external pure override returns (int256) {
        return 0;
    }

    function adjustReputation(address, int256) external pure override returns (int256) {
        return 0;
    }

    function getReputation(address account) external view override returns (int256 score, bool underPenalty) {
        RepData memory data = reps[account];
        return (data.score, data.underPenalty);
    }

    function canReceiveBonus(address account) external view override returns (bool) {
        return !reps[account].underPenalty;
    }
}

contract StakingTest is TestBase {
    uint256 private constant ONE_ZIR = 1_000_000;
    uint256 private constant USER_PK = 0xAA;
    uint256 private constant USER_B_PK = 0xBB;
    uint256 private constant USER_C_PK = 0xCC;

    AccessController private controller;
    FeatureFlags private flags;
    ZIR private zir;
    ReputationMock private reputation;
    StakingModule private staking;

    address private userA;
    address private userB;
    address private userC;

    function setUp() public {
        userA = vm.addr(USER_PK);
        userB = vm.addr(USER_B_PK);
        userC = vm.addr(USER_C_PK);

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
        reputation = new ReputationMock();

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
        zir.setFeeRate(0);

        address stakingProxy = deployProxy(
            address(new StakingModule(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                StakingModule.initialize.selector,
                controllerProxy,
                flagsProxy,
                zirProxy,
                address(reputation)
            )
        );
        staking = StakingModule(stakingProxy);
        flags.setFlag(FeatureFlagKeys.STAKING, true);

        bool fundedA = zir.transfer(userA, 10_000 * ONE_ZIR);
        bool fundedB = zir.transfer(userB, 10_000 * ONE_ZIR);
        bool fundedC = zir.transfer(userC, 10_000 * ONE_ZIR);
        assertTrue(fundedA && fundedB && fundedC, "STK-setup: user funding failed");

        vm.startPrank(userA);
        zir.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(userB);
        zir.approve(address(staking), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(userC);
        zir.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function _fundRewards(uint256 amount) internal {
        bool rewardSeeded = zir.transfer(address(staking), amount);
        assertTrue(rewardSeeded, "STK-util: reward funding failed");
    }

    function test_STK_01_RewardAccrualOverTime() public {
        reputation.setReputation(userA, 5_000, false); // 1.0x multiplier
        _fundRewards(2_000_000 * ONE_ZIR);

        vm.prank(userA);
        staking.stake(1_000 * ONE_ZIR);

        vm.warp(block.timestamp + 7 days);

        vm.prank(userA);
        staking.claimReward();

        uint256 rewardRate = staking.rewardRate();
        uint256 elapsed = 7 days;
        uint256 expected = rewardRate * elapsed;
        uint256 balance = zir.balanceOf(userA);
        uint256 principalSpent = 1_000 * ONE_ZIR;
        uint256 claimed = balance - (10_000 * ONE_ZIR - principalSpent);

        uint256 tolerance = expected / 100; // 1%
        assertTrue(claimed >= expected - tolerance && claimed <= expected + tolerance, "STK-01: reward mismatch");
    }

    function test_STK_02_MultiplierScaling() public {
        _fundRewards(2_000_000 * ONE_ZIR);

        reputation.setReputation(userA, 0, false); // 0.8x
        reputation.setReputation(userB, 10_000, false); // 1.2x
        reputation.setReputation(userC, 10_000, true); // penalty => <=1.0x

        vm.prank(userA);
        staking.stake(1_000 * ONE_ZIR);
        vm.prank(userB);
        staking.stake(1_000 * ONE_ZIR);
        vm.prank(userC);
        staking.stake(1_000 * ONE_ZIR);

        vm.warp(block.timestamp + 3 days);

        vm.prank(userA);
        staking.claimReward();
        vm.prank(userB);
        staking.claimReward();
        vm.prank(userC);
        staking.claimReward();

        uint256 rewardRate = staking.rewardRate();
        uint256 elapsed = 3 days;
        uint256 totalReward = rewardRate * elapsed;
        uint256 basePerUser = totalReward / 3;
        uint256 tol = basePerUser / 50; // 2%

        uint256 rewardA = zir.balanceOf(userA) - (10_000 * ONE_ZIR - 1_000 * ONE_ZIR);
        uint256 rewardB = zir.balanceOf(userB) - (10_000 * ONE_ZIR - 1_000 * ONE_ZIR);
        uint256 rewardC = zir.balanceOf(userC) - (10_000 * ONE_ZIR - 1_000 * ONE_ZIR);

        uint256 expectedA = (basePerUser * 8) / 10;
        uint256 expectedB = (basePerUser * 12) / 10;
        uint256 expectedC = basePerUser;

        assertTrue(rewardA >= expectedA - tol && rewardA <= expectedA + tol, "STK-02: 0.8x mismatch");
        assertTrue(rewardB >= expectedB - tol && rewardB <= expectedB + tol, "STK-02: 1.2x mismatch");
        assertTrue(rewardC >= expectedC - tol && rewardC <= expectedC + tol, "STK-02: penalty clamp");
    }

    function test_STK_03_InsufficientRewardBalanceReverts() public {
        reputation.setReputation(userA, 5_000, false);

        vm.prank(userA);
        staking.stake(1_000 * ONE_ZIR);

        vm.warp(block.timestamp + 1 days);

        vm.prank(userA);
        bool success;
        (success, ) = address(staking).call(abi.encodeWithSignature("claimReward()"));
        assertFalse(success, "STK-03: should revert when reward balance insufficient");
    }

    function test_STK_04_CooldownEnforcement() public {
        reputation.setReputation(userA, 5_000, false);
        _fundRewards(500_000 * ONE_ZIR);

        vm.prank(userA);
        staking.stake(500 * ONE_ZIR);

        vm.prank(userA);
        bool success;
        (success, ) = address(staking).call(abi.encodeWithSignature("withdraw(uint256)", 100 * ONE_ZIR));
        assertFalse(success, "STK-04: withdraw before cooldown should revert");

        vm.warp(block.timestamp + 4 days);
        vm.prank(userA);
        staking.withdraw(100 * ONE_ZIR);
        uint256 expectedPrincipalBalance = 10_000 * ONE_ZIR - 500 * ONE_ZIR + 100 * ONE_ZIR;
        assertTrue(zir.balanceOf(userA) >= expectedPrincipalBalance, "STK-04: principal not returned");

        (uint256 stakedAmount,, uint256 accruedReward,,) = staking.userInfo(userA);
        assertEq(stakedAmount, 400 * ONE_ZIR, "STK-04: remaining stake incorrect");
        uint256 pendingReward = staking.pendingReward(userA);
        assertEq(accruedReward, pendingReward, "STK-04: accrued reward accounting mismatch");
    }
}
