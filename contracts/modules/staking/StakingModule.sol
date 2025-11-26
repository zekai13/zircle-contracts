// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {Common} from "../../libs/Common.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {SafeTransferLib} from "../../libs/SafeTransferLib.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IZIR} from "../../interfaces/IZIR.sol";
import {IReputation} from "../../interfaces/IReputation.sol";

/// @title StakingModule
/// @notice Handles staking, reward accrual, and reputation multipliers.
contract StakingModule is ModuleBase, Common {
    using SafeTransferLib for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 accruedReward;
        uint64 cooldownEnd;
        uint16 multiplierBps;
    }

    IZIR public zir;
    IReputation public reputation;
    uint256 public rewardRate; // ZIR6 per second
    uint256 public accRewardPerShare; // 1e18 precision
    uint64 public lastRewardTimestamp;
    uint64 public cooldownPeriod;
    uint256 public totalStaked;

    mapping(address => UserInfo) public userInfo;
    mapping(uint8 => uint256) public yearlyRewardRate;

    uint16 public constant MIN_MULTIPLIER_BPS = 8_000; // 0.8x
    uint16 public constant BASE_MULTIPLIER_BPS = 10_000; // 1.0x
    uint16 public constant MAX_MULTIPLIER_BPS = 12_000; // 1.2x

    event PoolUpdated(uint256 accRewardPerShare, uint64 timestamp);
    event Stake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event CooldownUpdated(uint64 previous, uint64 current);
    event RewardRateUpdated(uint256 previous, uint256 current);
    event ReputationUpdated(address indexed user, uint16 multiplierBps);

    constructor(address accessController_, address featureFlags_, address zirToken_, address reputation_)
        ModuleBase(address(0), address(0))
    {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, zirToken_, reputation_);
        }
        _disableInitializers();
    }

    function initialize(
        address accessController_,
        address featureFlags_,
        address zirToken_,
        address reputation_
    ) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        require(zirToken_ != address(0), "Staking: ZIR required");
        zir = IZIR(zirToken_);
        reputation = IReputation(reputation_);

        rewardRate = 1_585_489; // default Y1 rate in micro ZIR
        yearlyRewardRate[1] = rewardRate;
        cooldownPeriod = 3 days;
        lastRewardTimestamp = uint64(block.timestamp);
    }

    // ========= configuration =========

    function setCooldownPeriod(uint64 newCooldown)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        emit CooldownUpdated(cooldownPeriod, newCooldown);
        cooldownPeriod = newCooldown;
    }

    function setYearlyRewardRate(uint8 scheduleId, uint256 rate)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        yearlyRewardRate[scheduleId] = rate;
    }

    function setYearlySchedule(uint8 scheduleId)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        uint256 rate = yearlyRewardRate[scheduleId];
        require(rate > 0, "Staking: rate not set");
        emit RewardRateUpdated(rewardRate, rate);
        _updatePool();
        rewardRate = rate;
    }

    function setReputation(address reputation_) external onlyManager {
        reputation = IReputation(reputation_);
    }

    // ========= user actions =========

    function stake(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        require(amount > 0, "Staking: amount zero");
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        _refreshMultiplier(msg.sender, user);
        if (user.amount > 0) {
            _accrueReward(user);
            uint256 claimed = _claimAccruedReward(user, msg.sender);
            if (claimed > 0) {
                emit RewardClaimed(msg.sender, claimed);
            }
        }

        IERC20(address(zir)).safeTransferFrom(msg.sender, address(this), amount);
        user.amount += amount;
        totalStaked += amount;

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
        user.cooldownEnd = uint64(block.timestamp + cooldownPeriod);
        _refreshMultiplier(msg.sender, user);

        emit Stake(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        require(amount > 0, "Staking: amount zero");
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Staking: insufficient balance");
        require(block.timestamp >= user.cooldownEnd, "Staking: cooldown");

        _updatePool();

        _refreshMultiplier(msg.sender, user);
        _accrueReward(user);
        uint256 claimed = _claimAccruedReward(user, msg.sender);
        if (claimed > 0) {
            emit RewardClaimed(msg.sender, claimed);
        }

        user.amount -= amount;
        totalStaked -= amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;

        IERC20(address(zir)).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function claimReward()
        external
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        _refreshMultiplier(msg.sender, user);
        _accrueReward(user);
        uint256 claimed = _claimAccruedReward(user, msg.sender);
        require(claimed > 0, "Staking: nothing to claim");

        emit RewardClaimed(msg.sender, claimed);
    }

    function emergencyWithdraw()
        external
        nonReentrant
        whenFeatureEnabled(FeatureFlagKeys.STAKING)
    {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "Staking: nothing staked");

        user.accruedReward = 0;
        totalStaked -= amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.cooldownEnd = 0;

        IERC20(address(zir)).safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // ========= views =========

    function pendingReward(address account) external view returns (uint256) {
        UserInfo storage user = userInfo[account];
        uint256 _acc = accRewardPerShare;
        if (block.timestamp > lastRewardTimestamp && totalStaked > 0) {
            uint256 reward = rewardRate * (block.timestamp - lastRewardTimestamp);
            _acc += (reward * 1e18) / totalStaked;
        }
        uint256 base = ((user.amount * _acc) / 1e18) - user.rewardDebt;
        if (base == 0) {
            return user.accruedReward;
        }
        uint16 multiplier = user.multiplierBps;
        if (address(reputation) != address(0)) {
            multiplier = _fetchMultiplier(account);
        }
        if (multiplier == 0) {
            multiplier = BASE_MULTIPLIER_BPS;
        }
        return (base * multiplier) / BASE_MULTIPLIER_BPS + user.accruedReward;
    }

    // ========= internal =========

    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTimestamp = uint64(block.timestamp);
            return;
        }

        uint256 reward = rewardRate * (block.timestamp - lastRewardTimestamp);
        accRewardPerShare += (reward * 1e18) / totalStaked;
        lastRewardTimestamp = uint64(block.timestamp);

        emit PoolUpdated(accRewardPerShare, lastRewardTimestamp);
    }

    function _fetchMultiplier(address account) internal view returns (uint16) {
        if (address(reputation) == address(0)) {
            return BASE_MULTIPLIER_BPS;
        }
        (int256 score, bool underPenalty) = reputation.getReputation(account);
        uint256 clampScore = score <= 0 ? 0 : uint256(score) > 10_000 ? 10_000 : uint256(score);
        uint16 multiplier = uint16(
            MIN_MULTIPLIER_BPS + ((clampScore * (MAX_MULTIPLIER_BPS - MIN_MULTIPLIER_BPS)) / 10_000)
        );
        if (underPenalty && multiplier > BASE_MULTIPLIER_BPS) {
            multiplier = BASE_MULTIPLIER_BPS;
        }
        return multiplier;
    }

    function _refreshMultiplier(address account, UserInfo storage user) internal {
        uint16 multiplier = _fetchMultiplier(account);
        if (user.multiplierBps != multiplier) {
            user.multiplierBps = multiplier;
            emit ReputationUpdated(account, multiplier);
        }
    }

    function _safeReward(address to, uint256 amount) internal {
        uint256 balance = IERC20(address(zir)).balanceOf(address(this));
        require(balance >= amount, "Staking: insufficient reward balance");
        IERC20(address(zir)).safeTransfer(to, amount);
    }

    function _accrueReward(UserInfo storage user) internal {
        uint256 base = ((user.amount * accRewardPerShare) / 1e18) - user.rewardDebt;
        if (base > 0) {
            uint256 scaled = (base * user.multiplierBps) / BASE_MULTIPLIER_BPS;
            user.accruedReward += scaled;
        }
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e18;
    }

    function _claimAccruedReward(UserInfo storage user, address to) internal returns (uint256 claimed) {
        uint256 available = _availableRewards();
        if (available == 0 || user.accruedReward == 0) {
            return 0;
        }
        uint256 claimable = user.accruedReward <= available ? user.accruedReward : available;
        _safeReward(to, claimable);
        user.accruedReward -= claimable;
        return claimable;
    }

    function _availableRewards() internal view returns (uint256) {
        uint256 balance = IERC20(address(zir)).balanceOf(address(this));
        return balance > totalStaked ? balance - totalStaked : 0;
    }
    uint256[45] private __gap;
}
