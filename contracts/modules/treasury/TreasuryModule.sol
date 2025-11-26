// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {SafeTransferLib} from "../../libs/SafeTransferLib.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IZIR} from "../../interfaces/IZIR.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {Common} from "../../libs/Common.sol";

/// @title TreasuryModule
/// @notice Manages platform reserves, fee routing, token burns, and dynamic fee adjustments.
contract TreasuryModule is ModuleBase, Common {
    using SafeTransferLib for IERC20;

    uint16 public constant QUARTERLY_BURN_MAX_BPS = 2_000; // 20%
    uint16 public constant PCT_BASE = 100;

    struct ModuleAllowance {
        bool authorized;
        uint256 allowanceZir6;
        uint256 dailyLimitZir6;
        uint256 dailySpentZir6;
        uint64 dailyWindowStart;
    }

    IZIR public zir;
    IERC20 public zirToken;
    IPriceOracle public priceOracle;

    uint256 public rewardLiability; // ZIR with 6 decimals
    uint16 public safetyMarginBps;

    uint256 public surplusBurnThreshold;
    uint256 public buybackThresholdUsd; // USD 18 decimals

    uint16 public platformFeeBurnPct;
    uint16 public platformFeeRewardPct;

    uint16 public minFeeRateBps;
    uint16 public maxFeeRateBps;
    uint16 public feeStepBps;
    uint256 public feeCooldown;
    uint256 public lastFeeAdjustmentAt;

    uint16 public liquidityIncreaseThresholdBps;
    uint16 public liquidityDecreaseThresholdBps;

    mapping(address => ModuleAllowance) public moduleAllowances;

    uint256 private zirBalanceCache;
    bool public moduleAllowanceFuseActive;

    uint256[38] private __gap;

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event ModuleAllowanceUpdated(address indexed module, bool authorized, uint256 allowanceZir6, uint256 dailyLimitZir6);
    event ModuleAllowanceCircuitBreakerUpdated(bool active);
    event RewardLiabilityUpdated(uint256 previousLiability, uint256 newLiability);
    event SafetyMarginUpdated(uint16 previousMargin, uint16 newMargin);
    event SurplusBurnThresholdUpdated(uint256 previousThreshold, uint256 newThreshold);
    event BuybackThresholdUpdated(uint256 previousThreshold, uint256 newThreshold);
    event PlatformFeeSplitUpdated(uint16 burnPct, uint16 rewardPct);
    event PriceOracleUpdated(address indexed previousOracle, address indexed newOracle);
    event PlatformFeeRouted(uint256 burnAmount, uint256 rewardAmount, uint256 retainedAmount);
    event SurplusBurned(uint256 amountBurned, uint256 balanceAfter);
    event QuarterlyBurnTriggered(uint256 amountBurned, uint256 minUsd, uint16 maxBps);
    event BuybackTriggered(uint256 amountBurned, uint256 usdBefore, uint256 thresholdUsd);
    event LiquidityAssessed(
        uint256 reserveRatioBps,
        uint16 currentFeeRate,
        uint16 newFeeRate,
        uint256 annualOutflow,
        uint256 targetFeeRate,
        uint8 action
    );

    modifier onlyAuthorizedModule() {
        ModuleAllowance storage config = moduleAllowances[msg.sender];
        require(config.authorized, "Treasury: module not authorized");
        _;
    }

    constructor(
        address accessController_,
        address featureFlags_,
        address zirToken_,
        address priceOracle_
    ) ModuleBase(address(0), address(0)) {
        if (accessController_ != address(0) && featureFlags_ != address(0)) {
            initialize(accessController_, featureFlags_, zirToken_, priceOracle_);
        }
        _disableInitializers();
    }

    function initialize(
        address accessController_,
        address featureFlags_,
        address zirToken_,
        address priceOracle_
    ) public initializer {
        __TreasuryModule_init(accessController_, featureFlags_, zirToken_, priceOracle_);
    }

    function __TreasuryModule_init(
        address accessController_,
        address featureFlags_,
        address zirToken_,
        address priceOracle_
    ) internal onlyInitializing {
        __ModuleBase_init(accessController_, featureFlags_);
        __TreasuryModule_init_unchained(zirToken_, priceOracle_);
    }

    function __TreasuryModule_init_unchained(address zirToken_, address priceOracle_) internal onlyInitializing {
        require(zirToken_ != address(0), "Treasury: ZIR required");
        zir = IZIR(zirToken_);
        zirToken = IERC20(zirToken_);
        priceOracle = IPriceOracle(priceOracle_);

        safetyMarginBps = 11_000;
        platformFeeBurnPct = 50;
        platformFeeRewardPct = 20;
        minFeeRateBps = 50;
        maxFeeRateBps = 500;
        feeStepBps = 25;
        feeCooldown = 7 days;
        liquidityIncreaseThresholdBps = 2_000;
        liquidityDecreaseThresholdBps = 5_000;
        lastFeeAdjustmentAt = block.timestamp > feeCooldown ? block.timestamp - feeCooldown : 0;
        zirBalanceCache = zirToken.balanceOf(address(this));
    }

    // ========== Configuration ==========

    function setPriceOracle(address oracle)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        emit PriceOracleUpdated(address(priceOracle), oracle);
        priceOracle = IPriceOracle(oracle);
    }

    function setRewardLiability(uint256 newLiability)
        external
        onlyTreasurer
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        emit RewardLiabilityUpdated(rewardLiability, newLiability);
        rewardLiability = newLiability;
    }

    function setSafetyMargin(uint16 newMarginBps)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(newMarginBps >= BPS, "Treasury: margin too low");
        emit SafetyMarginUpdated(safetyMarginBps, newMarginBps);
        safetyMarginBps = newMarginBps;
    }

    function setSurplusBurnThreshold(uint256 newThreshold)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        emit SurplusBurnThresholdUpdated(surplusBurnThreshold, newThreshold);
        surplusBurnThreshold = newThreshold;
    }

    function setBuybackThreshold(uint256 newThresholdUsd)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        emit BuybackThresholdUpdated(buybackThresholdUsd, newThresholdUsd);
        buybackThresholdUsd = newThresholdUsd;
    }

    function setPlatformFeeSplit(uint16 burnPct, uint16 rewardPct)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(burnPct <= PCT_BASE, "Treasury: burn pct invalid");
        require(rewardPct <= PCT_BASE, "Treasury: reward pct invalid");
        require(burnPct + rewardPct <= PCT_BASE, "Treasury: total pct exceeds 100");
        platformFeeBurnPct = burnPct;
        platformFeeRewardPct = rewardPct;
        emit PlatformFeeSplitUpdated(burnPct, rewardPct);
    }

    function setModuleAllowance(address module, bool authorized, uint256 allowanceZir6, uint256 dailyLimitZir6)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        ModuleAllowance storage config = moduleAllowances[module];
        config.authorized = authorized;

        uint256 emittedAllowance;
        uint256 emittedDailyLimit;

        if (!authorized) {
            config.allowanceZir6 = 0;
            config.dailyLimitZir6 = 0;
            config.dailySpentZir6 = 0;
            config.dailyWindowStart = 0;
        } else {
            config.allowanceZir6 = allowanceZir6;
            config.dailyLimitZir6 = dailyLimitZir6;
            if (dailyLimitZir6 == 0) {
                config.dailySpentZir6 = 0;
                config.dailyWindowStart = 0;
            } else if (config.dailyWindowStart == 0) {
                config.dailyWindowStart = uint64(block.timestamp);
                config.dailySpentZir6 = 0;
            } else if (config.dailySpentZir6 > dailyLimitZir6) {
                config.dailySpentZir6 = dailyLimitZir6;
            }
            emittedAllowance = allowanceZir6;
            emittedDailyLimit = dailyLimitZir6;
        }

        emit ModuleAllowanceUpdated(module, authorized, emittedAllowance, emittedDailyLimit);
    }

    function setModuleAllowanceCircuitBreaker(bool active)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        moduleAllowanceFuseActive = active;
        emit ModuleAllowanceCircuitBreakerUpdated(active);
    }

    function setDynamicFeePolicy(
        uint16 minBps,
        uint16 maxBps,
        uint16 stepBps,
        uint256 cooldown,
        uint16 increaseThresholdBps,
        uint16 decreaseThresholdBps
    ) external onlyManager whenFeatureEnabled(FeatureFlagKeys.TREASURY) {
        require(minBps <= maxBps, "Treasury: fee bounds invalid");
        require(stepBps > 0, "Treasury: step zero");
        require(cooldown >= 1 days, "Treasury: cooldown too low");
        minFeeRateBps = minBps;
        maxFeeRateBps = maxBps;
        feeStepBps = stepBps;
        feeCooldown = cooldown;
        liquidityIncreaseThresholdBps = increaseThresholdBps;
        liquidityDecreaseThresholdBps = decreaseThresholdBps;
        lastFeeAdjustmentAt = block.timestamp > cooldown ? block.timestamp - cooldown : 0;
    }

    // ========== Treasury Operations ==========

    function deposit(address token, uint256 amount)
        external
        onlyTreasurer
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(amount > 0, "Treasury: deposit zero");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (token == address(zirToken)) {
            _syncZirBalance();
        }
        emit Deposited(token, msg.sender, amount);
    }

    function withdraw(address token, address to, uint256 amount)
        external
        onlyTreasurer
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(to != address(0), "Treasury: to zero");
        require(amount > 0, "Treasury: withdraw zero");

        IERC20 asset = IERC20(token);
        uint256 balanceBefore = asset.balanceOf(address(this));
        require(balanceBefore >= amount, "Treasury: insufficient balance");

        if (token == address(zirToken)) {
            require(balanceBefore - amount >= requiredReserve(), "Treasury: reserve breach");
        }

        asset.safeTransfer(to, amount);
        if (token == address(zirToken)) {
            _syncZirBalance();
        }
        emit Withdrawn(token, to, amount);
    }

    function withdrawForModule(address to, uint256 amount)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(to != address(0), "Treasury: to zero");
        require(amount > 0, "Treasury: withdraw zero");
        require(!moduleAllowanceFuseActive, "Treasury: module fuse active");

        ModuleAllowance storage config = moduleAllowances[msg.sender];
        if (config.allowanceZir6 != type(uint256).max) {
            require(config.allowanceZir6 >= amount, "Treasury: allowance exceeded");
            config.allowanceZir6 -= amount;
        }

        _enforceDailyLimit(config, amount);

        uint256 balance = zirToken.balanceOf(address(this));
        require(balance >= amount, "Treasury: insufficient balance");
        require(balance - amount >= requiredReserve(), "Treasury: reserve breach");

        zirToken.safeTransfer(to, amount);
        _syncZirBalance();
        emit Withdrawn(address(zirToken), to, amount);
    }

    function onPlatformFeeReceived(uint256 amountZir6)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(amountZir6 > 0, "Treasury: fee zero");

        uint256 balanceBefore = zirToken.balanceOf(address(this));
        require(balanceBefore >= zirBalanceCache, "Treasury: balance desync");
        uint256 actualFee = balanceBefore - zirBalanceCache;
        require(actualFee == amountZir6, "Treasury: fee mismatch");

        uint256 burnAmount = (actualFee * platformFeeBurnPct) / PCT_BASE;
        uint256 rewardAmount = (actualFee * platformFeeRewardPct) / PCT_BASE;
        uint256 retainedAmount = actualFee - burnAmount - rewardAmount;

        if (rewardAmount > 0) {
            rewardLiability += rewardAmount;
            emit RewardLiabilityUpdated(rewardLiability - rewardAmount, rewardLiability);
        }

        if (burnAmount > 0) {
            zir.burnFromTreasury(burnAmount);
        }

        _syncZirBalance();

        emit PlatformFeeRouted(burnAmount, rewardAmount, retainedAmount);
    }

    function burnSurplus()
        external
        onlyTreasurer
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        uint256 balance = zirToken.balanceOf(address(this));
        uint256 required = requiredReserve();
        uint256 threshold = surplusBurnThreshold > required ? surplusBurnThreshold : required;
        require(balance > threshold, "Treasury: no surplus");

        uint256 amountToBurn = balance - threshold;
        zir.burnFromTreasury(amountToBurn);
        _syncZirBalance();
        emit SurplusBurned(amountToBurn, zirBalanceCache);
    }

    function triggerQuarterlyBurn(uint256 minUsd, uint16 maxBpsOfFree)
        external
        onlyTreasurer
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(maxBpsOfFree <= QUARTERLY_BURN_MAX_BPS, "Treasury: max bps too high");
        uint256 freeBal = freeBalance();
        require(freeBal > 0, "Treasury: no free balance");

        uint256 burnAmount = (freeBal * maxBpsOfFree) / BPS;
        require(burnAmount > 0, "Treasury: burn zero");

        if (minUsd > 0) {
            require(address(priceOracle) != address(0), "Treasury: oracle missing");
            uint256 usdValue = priceOracle.convertToUsd(burnAmount);
            require(usdValue >= minUsd, "Treasury: below min usd");
        }

        zir.burnFromTreasury(burnAmount);
        _syncZirBalance();
        emit QuarterlyBurnTriggered(burnAmount, minUsd, maxBpsOfFree);
    }

    function triggerBuyback()
        external
        onlyTreasurer
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(address(priceOracle) != address(0), "Treasury: oracle missing");
        uint256 balance = zirToken.balanceOf(address(this));
        uint256 usdValue = priceOracle.convertToUsd(balance);
        require(usdValue >= buybackThresholdUsd, "Treasury: threshold not met");

        uint256 amountToBurn = freeBalance();
        require(amountToBurn > 0, "Treasury: no free balance");

        zir.burnFromTreasury(amountToBurn);
        _syncZirBalance();
        emit BuybackTriggered(amountToBurn, usdValue, buybackThresholdUsd);
    }

    function assessLiquidityAndAdjustFee(uint256 annualOutflow, uint256 targetFeeRate)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.TREASURY)
    {
        require(block.timestamp - lastFeeAdjustmentAt >= feeCooldown, "Treasury: cooldown active");

        uint16 currentRate = zir.feeRateBps();
        uint16 boundedTarget = uint16(targetFeeRate > type(uint16).max ? type(uint16).max : targetFeeRate);
        if (boundedTarget < minFeeRateBps) boundedTarget = minFeeRateBps;
        if (boundedTarget > maxFeeRateBps) boundedTarget = maxFeeRateBps;

        uint256 required = requiredReserve();
        uint256 balance = zirToken.balanceOf(address(this));
        uint256 reserveRatioBps = required == 0 ? type(uint256).max : (balance * BPS) / required;

        uint16 newRate = currentRate;
        uint8 action;

        if (required == 0) {
            if (currentRate != boundedTarget) {
                newRate = boundedTarget;
                action = 3;
            }
        } else if (reserveRatioBps < liquidityIncreaseThresholdBps && currentRate < maxFeeRateBps) {
            uint16 candidate = currentRate + feeStepBps;
            if (candidate > maxFeeRateBps) candidate = maxFeeRateBps;
            newRate = candidate;
            action = 1;
        } else if (reserveRatioBps > liquidityDecreaseThresholdBps && currentRate > minFeeRateBps) {
            uint16 candidate = currentRate > feeStepBps ? currentRate - feeStepBps : minFeeRateBps;
            if (candidate < minFeeRateBps) candidate = minFeeRateBps;
            newRate = candidate;
            action = 2;
        } else if (currentRate != boundedTarget) {
            newRate = boundedTarget;
            action = 3;
        }

        if (newRate != currentRate) {
            zir.setFeeRate(newRate);
            lastFeeAdjustmentAt = block.timestamp;
        }

        emit LiquidityAssessed(reserveRatioBps, currentRate, newRate, annualOutflow, boundedTarget, action);
    }

    function _enforceDailyLimit(ModuleAllowance storage config, uint256 amount) internal {
        if (config.dailyLimitZir6 == 0) {
            return;
        }

        uint64 start = config.dailyWindowStart;
        if (start == 0 || block.timestamp >= start + 1 days) {
            require(amount <= config.dailyLimitZir6, "Treasury: daily limit exceeded");
            config.dailyWindowStart = uint64(block.timestamp);
            config.dailySpentZir6 = amount;
        } else {
            uint256 newSpent = config.dailySpentZir6 + amount;
            require(newSpent <= config.dailyLimitZir6, "Treasury: daily limit exceeded");
            config.dailySpentZir6 = newSpent;
        }
    }

    function _syncZirBalance() internal {
        zirBalanceCache = zirToken.balanceOf(address(this));
    }

    // ========== Views ==========

    function requiredReserve() public view returns (uint256) {
        return (rewardLiability * safetyMarginBps) / BPS;
    }

    function freeBalance() public view returns (uint256) {
        uint256 balance = zirToken.balanceOf(address(this));
        uint256 required = requiredReserve();
        if (balance <= required) {
            return 0;
        }
        return balance - required;
    }
}
