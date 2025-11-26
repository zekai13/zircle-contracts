// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract TokenActor {
    function transferToken(address token, address to, uint256 amount) external returns (bool) {
        return ZIR(token).transfer(to, amount);
    }

    function approveToken(address token, address spender, uint256 amount) external returns (bool) {
        return ZIR(token).approve(spender, amount);
    }

    function transferFromToken(address token, address from, address to, uint256 amount) external returns (bool) {
        return ZIR(token).transferFrom(from, to, amount);
    }

    function burnTreasury(address token, uint256 amount) external returns (bool) {
        ZIR(token).burnFromTreasury(amount);
        return true;
    }
}

contract ZIRTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    ZIR private zir;
    TokenActor private alice;
    TokenActor private bob;

    address private constant CHARLIE = address(0x1001);
    uint256 private constant ONE_ZIR = 1_000_000;

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

        alice = new TokenActor();
        bob = new TokenActor();
    }

    function test_ZIR_01_FeeAndRatioBounds() public {
        zir.setFeeRate(0);
        zir.setFeeRate(500);

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("setFeeRate(uint16)", 501),
            "ZIR-01: fee upper bound rejection"
        );

        zir.setRatios(50, 20);

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("setRatios(uint16,uint16)", 49, 20),
            "ZIR-01: burn ratio below minimum"
        );

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("setRatios(uint16,uint16)", 70, 25),
            "ZIR-01: reward ratio above maximum"
        );

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("setRatios(uint16,uint16)", 70, 40),
            "ZIR-01: ratio sum exceeds 100%"
        );

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("setTreasury(address)", address(0)),
            "ZIR-01: treasury zero address rejection"
        );

        zir.setExempt(address(alice), true);
        assertTrue(zir.feeExempt(address(alice)), "ZIR-01: fee exemption not recorded");

        zir.setBlacklist(address(bob), true);
        assertTrue(zir.blacklist(address(bob)), "ZIR-01: blacklist flag not set");

        callAndExpectRevert(
            address(zir),
            abi.encodeWithSignature("transfer(address,uint256)", address(bob), ONE_ZIR),
            "ZIR-01: transfer to blacklisted address should revert"
        );

        TokenActor outsider = new TokenActor();
        callAndExpectRevert(
            address(outsider),
            abi.encodeWithSignature("burnTreasury(address,uint256)", address(zir), ONE_ZIR),
            "ZIR-01: burnFromTreasury unauthorized caller rejected"
        );

        uint256 supplyBefore = zir.totalSupply();
        zir.burnFromTreasury(ONE_ZIR);
        assertEq(zir.totalSupply(), supplyBefore - ONE_ZIR, "ZIR-01: treasury burn should reduce supply");
    }

    function test_ZIR_02_FeeDistributionConservation() public {
        zir.setFeeRate(100); // 1%
        zir.setRatios(50, 20); // burn=50%, reward=20%, treasury remainder
        zir.setExempt(address(alice), false);

        bool seededAlice = zir.transfer(address(alice), 10 * ONE_ZIR);
        assertTrue(seededAlice, "ZIR-02: funding Alice failed");
        uint256 treasuryBefore = zir.balanceOf(address(this));
        uint256 totalSupplyBefore = zir.totalSupply();

        uint256 transferAmount = ONE_ZIR;
        bool success = alice.transferToken(address(zir), CHARLIE, transferAmount);
        assertTrue(success, "ZIR-02: transfer execution failed");

        uint256 expectedFee = (transferAmount * 100) / 10_000;
        uint256 expectedBurn = (expectedFee * 50) / 100;
        uint256 expectedReward = (expectedFee * 20) / 100;
        uint256 expectedTreasury = expectedFee - expectedBurn - expectedReward;

        assertEq(
            zir.balanceOf(CHARLIE),
            transferAmount - expectedFee,
            "ZIR-02: net amount mismatch for recipient"
        );
        assertEq(
            zir.balanceOf(address(alice)),
            9 * ONE_ZIR,
            "ZIR-02: sender balance incorrect after fee deduction"
        );
        assertEq(
            zir.balanceOf(address(this)),
            treasuryBefore + expectedTreasury + expectedReward,
            "ZIR-02: treasury accumulation incorrect"
        );
        assertEq(
            zir.totalSupply(),
            totalSupplyBefore - expectedBurn,
            "ZIR-02: total supply should fall by burn amount"
        );

        zir.setExempt(address(alice), true);
        uint256 bobBalanceBefore = zir.balanceOf(address(bob));
        success = alice.transferToken(address(zir), address(bob), ONE_ZIR);
        assertTrue(success, "ZIR-02: whitelist transfer failed");
        assertEq(
            zir.balanceOf(address(bob)),
            bobBalanceBefore + ONE_ZIR,
            "ZIR-02: whitelist transfer should not deduct fee"
        );

        alice.approveToken(address(zir), address(bob), ONE_ZIR);
        success = bob.transferFromToken(address(zir), address(alice), CHARLIE, ONE_ZIR);
        assertTrue(success, "ZIR-02: transferFrom execution failed");
    }

    function test_ZIR_03_LowAmountPrecision() public {
        zir.setFeeRate(50); // 0.5%
        zir.setRatios(50, 20);

        uint256[5] memory tinyAmounts = [uint256(1), 9, 10, 99, 100];
        for (uint256 i = 0; i < tinyAmounts.length; i++) {
            TokenActor sender = new TokenActor();
            address receiver = address(uint160(0x2000 + i));
            bool seededSender = zir.transfer(address(sender), tinyAmounts[i]);
            assertTrue(seededSender, "ZIR-03: funding sender failed");

            uint256 totalSupplyBefore = zir.totalSupply();
            bool success = sender.transferToken(address(zir), receiver, tinyAmounts[i]);
            assertTrue(success, "ZIR-03: tiny transfer failed");
            assertTrue(
                zir.balanceOf(receiver) <= tinyAmounts[i],
                "ZIR-03: receiver balance overflow"
            );
            assertTrue(
                zir.totalSupply() <= totalSupplyBefore,
                "ZIR-03: total supply should not increase"
            );
        }
    }

    function test_ZIR_04_AutoAdjustBurnRatioClamping() public {
        zir.setRatios(55, 20);

        zir.autoAdjustBurnRatio(250);
        assertEq(zir.burnRatioPct(), 60, "ZIR-04: burn ratio should increase by 5");

        zir.autoAdjustBurnRatio(250);
        assertEq(zir.burnRatioPct(), 65, "ZIR-04: burn ratio second increase");

        zir.autoAdjustBurnRatio(250);
        assertEq(zir.burnRatioPct(), 70, "ZIR-04: burn ratio should clamp at 70");

        zir.autoAdjustBurnRatio(250);
        assertEq(zir.burnRatioPct(), 70, "ZIR-04: burn ratio must remain clamped at 70");

        zir.setRatios(50, 20);
        zir.autoAdjustBurnRatio(120);
        assertEq(zir.burnRatioPct(), 50, "ZIR-04: burn ratio should not drop below 50");

        zir.setRatios(55, 20);
        zir.autoAdjustBurnRatio(140);
        assertEq(zir.burnRatioPct(), 50, "ZIR-04: burn ratio decreases by 5 when inflation low");
    }

    function test_ZIR_05_PauseBlocksTransfers() public {
        bool pauseSeed = zir.transfer(address(alice), ONE_ZIR);
        assertTrue(pauseSeed, "ZIR-05: funding Alice failed");

        zir.pause();

        callAndExpectRevert(
            address(alice),
            abi.encodeWithSignature("transferToken(address,address,uint256)", address(zir), CHARLIE, ONE_ZIR),
            "ZIR-05: transfer should revert while paused"
        );

        zir.unpause();

        bool success = alice.transferToken(address(zir), CHARLIE, ONE_ZIR);
        assertTrue(success, "ZIR-05: transfer should succeed after unpause");
    }
}
