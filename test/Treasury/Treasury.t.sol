// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {TreasuryModule} from "../../contracts/modules/treasury/TreasuryModule.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";
import {IPriceOracle} from "../../contracts/interfaces/IPriceOracle.sol";
import {IZIR} from "../../contracts/interfaces/IZIR.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 private _price;

    constructor(uint256 priceE18) {
        _price = priceE18;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }

    function syncPrice() external override {}

    function latestPrice() external view override returns (uint256) {
        return _price;
    }

    function convertToUsd(uint256 amountZir6) external view override returns (uint256) {
        return (amountZir6 * _price) / 1e6;
    }

    function convertFromUsd(uint256 amountUsd18) external view override returns (uint256) {
        return (amountUsd18 * 1e6) / _price;
    }

    function quoteFee(uint256) external pure override returns (uint256) {
        return 0;
    }

    function nativeUsdPriceE18() external pure override returns (uint256) {
        return 0;
    }
}

contract FeeModuleCaller {
    TreasuryModule private treasury;

    constructor(TreasuryModule treasury_) {
        treasury = treasury_;
    }

    function route(uint256 amount) external {
        treasury.onPlatformFeeReceived(amount);
    }
}

contract ModuleWithdrawer {
    TreasuryModule private treasury;

    constructor(TreasuryModule treasury_) {
        treasury = treasury_;
    }

    function withdraw(address to, uint256 amount) external {
        treasury.withdrawForModule(to, amount);
    }
}

contract TreasuryTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    MockPriceOracle private oracle;
    TreasuryModule private treasury;
    ZIR private zir;
    FeeModuleCaller private feeModule;
    ModuleWithdrawer private moduleWithdrawer;

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
        controller.grantRole(Roles.ROLE_TREASURER, address(this));
        controller.grantRole(Roles.ROLE_PAUSER, address(this));

        address flagsProxy = deployProxy(
            address(new FeatureFlags(address(0))),
            abi.encodeWithSelector(FeatureFlags.initialize.selector, controllerProxy)
        );
        flags = FeatureFlags(flagsProxy);
        oracle = new MockPriceOracle(2_000_000_000000000000); // 2 USD

        // Deploy ZIR with temporary treasury (this contract)
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

        address treasuryProxy = deployProxy(
            address(new TreasuryModule(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                TreasuryModule.initialize.selector,
                controllerProxy,
                flagsProxy,
                zirProxy,
                address(oracle)
            )
        );
        treasury = TreasuryModule(treasuryProxy);
        feeModule = new FeeModuleCaller(treasury);
        moduleWithdrawer = new ModuleWithdrawer(treasury);

        controller.grantRole(Roles.ROLE_MANAGER, address(treasury));
        controller.grantRole(Roles.ROLE_TREASURER, address(treasury));

        // Move minted supply to treasury and set treasury address in ZIR
        zir.setTreasury(address(treasury));

        flags.setFlag(FeatureFlagKeys.TREASURY, true);
        treasury.setModuleAllowance(address(feeModule), true, 0, 0);
    }

    function test_TRE_01_ReserveConstraint() public {
        treasury.setRewardLiability(5 * ONE_ZIR); // 5 ZIR liability
        uint256 required = treasury.requiredReserve();
        uint256 depositAmount = required + 5 * ONE_ZIR;

        zir.approve(address(treasury), depositAmount);
        treasury.deposit(address(zir), depositAmount);

        uint256 balance = zir.balanceOf(address(treasury));
        assertTrue(balance >= depositAmount, "TRE-01: deposit failed");

        uint256 excess = balance - required + 1;
        callAndExpectRevert(
            address(treasury),
            abi.encodeWithSignature("withdraw(address,address,uint256)", address(zir), address(this), excess),
            "TRE-01: reserve breach should revert"
        );

        uint256 allowable = balance - required;
        treasury.withdraw(address(zir), address(this), allowable);
        assertEq(
            zir.balanceOf(address(treasury)),
            required,
            "TRE-01: remaining balance should equal required reserve"
        );
    }

    function test_TRE_02_PlatformFeeRouting() public {
        uint256 initialSupply = zir.totalSupply();
        uint256 rewardBefore = treasury.rewardLiability();

        // Transfer fee to treasury before routing
        uint256 feeAmount = 10 * ONE_ZIR;
        bool seeded = zir.transfer(address(treasury), feeAmount);
        assertTrue(seeded, "TRE-setup: failed funding treasury");
        feeModule.route(feeAmount);

        uint256 burnExpected = (feeAmount * 50) / 100;
        uint256 rewardExpected = (feeAmount * 20) / 100;
        assertEq(
            treasury.rewardLiability(),
            rewardBefore + rewardExpected,
            "TRE-02: reward liability should increase"
        );
        assertEq(
            zir.totalSupply(),
            initialSupply - burnExpected,
            "TRE-02: total supply should decrease by burn"
        );
        assertEq(
            zir.balanceOf(address(treasury)),
            feeAmount - burnExpected,
            "TRE-02: treasury should retain net fee after burn"
        );
    }

    function test_TRE_03_BurnAndBuyback() public {
        treasury.setRewardLiability(5 * ONE_ZIR);
        treasury.setSurplusBurnThreshold(6 * ONE_ZIR);
        treasury.setBuybackThreshold(1 ether);

        uint256 depositAmount = 20 * ONE_ZIR;
        zir.approve(address(treasury), depositAmount);
        treasury.deposit(address(zir), depositAmount);

        uint256 balanceBefore = zir.balanceOf(address(treasury));
        treasury.burnSurplus();
        uint256 balanceAfter = zir.balanceOf(address(treasury));
        assertTrue(balanceAfter < balanceBefore, "TRE-03: burnSurplus should reduce balance");

        uint256 free = treasury.freeBalance();
        require(free > 0, "TRE-03: free balance should remain");

        treasury.triggerQuarterlyBurn(0, 500); // burn 5% of free balance
        uint256 afterQuarterly = zir.balanceOf(address(treasury));
        assertTrue(afterQuarterly < balanceAfter, "TRE-03: quarterly burn should reduce balance");

        oracle.setPrice(5_000_000_000000000000); // 5 USD
        treasury.triggerBuyback();
        assertEq(treasury.freeBalance(), 0, "TRE-03: buyback should remove free balance");
    }

    function test_TRE_04_DynamicFeeAdjustment() public {
        treasury.setDynamicFeePolicy(50, 500, 25, 1 days, 2_000, 5_000);

        uint16 currentRate = IZIR(address(zir)).feeRateBps();
        assertEq(currentRate, 0, "TRE-04: default fee rate should be zero before adjustments");

        treasury.setRewardLiability(10 * ONE_ZIR);
        uint256 required = treasury.requiredReserve();
        bool extraStake = zir.transfer(address(treasury), required + ONE_ZIR);
        assertTrue(extraStake, "TRE-04: failed transfer for liquidity test");

        vm.warp(block.timestamp + 2 days);
        treasury.assessLiquidityAndAdjustFee(0, 100);
        uint16 newRate = IZIR(address(zir)).feeRateBps();
        assertTrue(newRate >= 50, "TRE-04: fee rate should adjust upward");
    }

    function test_TRE_05_ModuleDailyLimit() public {
        uint256 allowance = 100 * ONE_ZIR;
        uint256 dailyLimit = 50 * ONE_ZIR;
        treasury.setModuleAllowance(address(moduleWithdrawer), true, allowance, dailyLimit);

        uint256 depositAmount = 150 * ONE_ZIR;
        zir.approve(address(treasury), depositAmount);
        treasury.deposit(address(zir), depositAmount);

        moduleWithdrawer.withdraw(address(this), 30 * ONE_ZIR);

        vm.expectRevert(bytes("Treasury: daily limit exceeded"));
        moduleWithdrawer.withdraw(address(this), 25 * ONE_ZIR);

        vm.warp(block.timestamp + 1 days + 1);
        moduleWithdrawer.withdraw(address(this), 20 * ONE_ZIR);

        (bool authorized, uint256 remaining, uint256 dailyLimitConfigured, uint256 dailySpent, uint64 windowStart) =
            treasury.moduleAllowances(address(moduleWithdrawer));

        assertTrue(authorized, "TRE-05: module no longer authorized");
        assertEq(remaining, allowance - 50 * ONE_ZIR, "TRE-05: allowance not decremented");
        assertEq(dailyLimitConfigured, dailyLimit, "TRE-05: daily limit mismatch");
        assertEq(dailySpent, 20 * ONE_ZIR, "TRE-05: daily spent should reset after window");
        assertTrue(windowStart > 0, "TRE-05: window start should be set");
    }

    function test_TRE_06_ModuleFuse() public {
        uint256 depositAmount = 100 * ONE_ZIR;
        zir.approve(address(treasury), depositAmount);
        treasury.deposit(address(zir), depositAmount);
        treasury.setModuleAllowance(address(moduleWithdrawer), true, 80 * ONE_ZIR, 0);
        uint256 balanceBefore = zir.balanceOf(address(this));

        treasury.setModuleAllowanceCircuitBreaker(true);
        vm.expectRevert(bytes("Treasury: module fuse active"));
        moduleWithdrawer.withdraw(address(this), 10 * ONE_ZIR);

        treasury.setModuleAllowanceCircuitBreaker(false);
        moduleWithdrawer.withdraw(address(this), 10 * ONE_ZIR);
        assertEq(
            zir.balanceOf(address(this)),
            balanceBefore + 10 * ONE_ZIR,
            "TRE-06: withdrawal should succeed after fuse reset"
        );
    }
}
