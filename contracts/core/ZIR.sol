// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Votes} from "../libs/ERC20Votes.sol";
import {ModuleBase} from "../libs/ModuleBase.sol";
import {Common} from "../libs/Common.sol";
import {FeatureFlagKeys} from "../libs/FeatureFlagKeys.sol";
import {Errors} from "../libs/Errors.sol";

/// @title ZIR Token
/// @notice Platform native ERC20 with fee splitting and burn logic.
contract ZIR is ERC20Votes, ModuleBase, Common {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * ZIR_DECIMALS;
    uint16 public constant MAX_FEE_BPS = 500;
    uint16 public constant MIN_BURN_RATIO = 50;
    uint16 public constant MAX_BURN_RATIO = 70;
    uint16 public constant MAX_REWARD_RATIO = 20;

    enum BurnAdjustmentReason {
        None,
        InflationHigh,
        InflationLow,
        Clamped
    }

    uint16 public feeRateBps;
    uint16 public burnRatioPct;
    uint16 public rewardRatioPct;

    address public treasury;

    mapping(address => bool) public feeExempt;
    mapping(address => bool) public blacklist;

    event FeeRateUpdated(uint16 previousRate, uint16 newRate);
    event RatiosUpdated(uint16 previousBurn, uint16 newBurn, uint16 previousReward, uint16 newReward);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event FeeExemptSet(address indexed account, bool isExempt);
    event BlacklistSet(address indexed account, bool isBlacklisted);
    event TransfersPaused(address indexed caller);
    event TransfersUnpaused(address indexed caller);
    event BurnRatioAutoAdjusted(uint16 previousRatio, uint16 newRatio, BurnAdjustmentReason reason);
    event FeeDistributed(uint256 burnAmount, uint256 treasuryAmount, uint256 rewardAmount);
    event TreasuryBurned(address indexed treasury, uint256 amount);

    constructor(address accessController_, address featureFlags_, address treasury_)
        ERC20Votes("", "", 0, "")
        ModuleBase(address(0), address(0))
    {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, treasury_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_, address treasury_) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        __ERC20Votes_init("Zircle Token", "ZIR", 6, "1");
        require(treasury_ != address(0), "ZIR: treasury zero address");
        treasury = treasury_;
        burnRatioPct = 55;
        rewardRatioPct = 20;
        feeRateBps = 0;

        feeExempt[treasury_] = true;
        _mint(treasury_, TOTAL_SUPPLY);
    }

    // ========= External configuration =========

    function setFeeRate(uint16 newRate) external onlyManager {
        require(newRate <= MAX_FEE_BPS, "ZIR: fee out of bounds");
        emit FeeRateUpdated(feeRateBps, newRate);
        feeRateBps = newRate;
    }

    function setRatios(uint16 newBurnRatio, uint16 newRewardRatio) external onlyManager {
        require(newBurnRatio >= MIN_BURN_RATIO && newBurnRatio <= MAX_BURN_RATIO, "ZIR: burn ratio out of bounds");
        require(newRewardRatio <= MAX_REWARD_RATIO, "ZIR: reward ratio out of bounds");
        require(newBurnRatio + newRewardRatio <= 100, "ZIR: ratio sum exceeds 100%");
        emit RatiosUpdated(burnRatioPct, newBurnRatio, rewardRatioPct, newRewardRatio);
        burnRatioPct = newBurnRatio;
        rewardRatioPct = newRewardRatio;
    }

    function setTreasury(address newTreasury) external onlyManager {
        require(newTreasury != address(0), "ZIR: treasury zero address");
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setExempt(address account, bool isExempt) external onlyManager {
        feeExempt[account] = isExempt;
        emit FeeExemptSet(account, isExempt);
    }

    function setBlacklist(address account, bool isBlacklisted) external onlyManager {
        blacklist[account] = isBlacklisted;
        emit BlacklistSet(account, isBlacklisted);
    }

    function autoAdjustBurnRatio(uint16 inflationBps) external onlyManager {
        uint16 oldRatio = burnRatioPct;
        uint16 newRatio = oldRatio;
        BurnAdjustmentReason reason = BurnAdjustmentReason.None;

        if (inflationBps > 200 && oldRatio + 5 <= MAX_BURN_RATIO) {
            newRatio = oldRatio + 5;
            reason = BurnAdjustmentReason.InflationHigh;
        } else if (inflationBps < 150 && oldRatio > MIN_BURN_RATIO) {
            if (oldRatio - 5 < MIN_BURN_RATIO) {
                newRatio = MIN_BURN_RATIO;
                reason = BurnAdjustmentReason.Clamped;
            } else {
                newRatio = oldRatio - 5;
                reason = BurnAdjustmentReason.InflationLow;
            }
        } else if (oldRatio == MAX_BURN_RATIO || oldRatio == MIN_BURN_RATIO) {
            reason = BurnAdjustmentReason.Clamped;
        }

        if (newRatio != oldRatio) {
            burnRatioPct = newRatio;
        }

        emit BurnRatioAutoAdjusted(oldRatio, burnRatioPct, reason);
    }

    function burnFromTreasury(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
    {
        require(msg.sender == treasury, "ZIR: caller not treasury");
        _burn(msg.sender, amount);
        emit TreasuryBurned(msg.sender, amount);
    }

    // ========= ERC20 overrides =========

    function pause() public override onlyPauser {
        super.pause();
        emit TransfersPaused(msg.sender);
    }

    function unpause() public override onlyPauser {
        super.unpause();
        emit TransfersUnpaused(msg.sender);
    }

    function approve(address spender, uint256 amount)
        public
        override
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
        returns (bool)
    {
        return super.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
        returns (bool)
    {
        return super.decreaseAllowance(spender, subtractedValue);
    }

    function transfer(address to, uint256 amount)
        public
        override
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
        returns (bool)
    {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ZIR_TOKEN)
        returns (bool)
    {
        uint256 currentAllowance = allowance(from, msg.sender);
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _transferWithFee(from, to, amount);
        unchecked {
            _approve(from, msg.sender, currentAllowance - amount);
        }
        return true;
    }

    // ========= Internal helpers =========

    function _transferWithFee(address from, address to, uint256 amount) internal {
        require(amount > 0, "ZIR: amount zero");
        if (blacklist[from] || blacklist[to]) {
            revert(Errors.BLACKLISTED);
        }

        if (feeRateBps == 0 || feeExempt[from] || feeExempt[to]) {
            _transfer(from, to, amount);
            return;
        }

        uint256 fee = (amount * feeRateBps) / BPS;
        if (fee >= amount) {
            revert(Errors.INVALID_PARAMS);
        }

        uint256 netAmount = amount - fee;
        _transfer(from, to, netAmount);

        uint256 burnAmount = (fee * burnRatioPct) / 100;
        uint256 rewardAmount = (fee * rewardRatioPct) / 100;
        uint256 treasuryAmount = fee - burnAmount - rewardAmount;

        if (treasuryAmount > 0) {
            _transfer(from, treasury, treasuryAmount);
        }

        if (rewardAmount > 0) {
            _transfer(from, treasury, rewardAmount);
        }

        if (burnAmount > 0) {
            _burn(from, burnAmount);
        }

        emit FeeDistributed(burnAmount, treasuryAmount, rewardAmount);
    }

    uint256[45] private __gap;
}
