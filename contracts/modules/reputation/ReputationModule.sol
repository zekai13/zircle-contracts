// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {Common} from "../../libs/Common.sol";

/// @title ReputationModule
/// @notice Tracks participant reputation with weekly decay and penalty windows.
contract ReputationModule is ModuleBase, Common {
    uint16 public constant DECAY_BPS = 50; // 0.5% weekly decay
    uint64 public constant MAX_DECAY_WEEKS = 260;
    int256 public constant TRADE_DELTA = 50;
    int256 public constant ARBITRATION_WIN_DELTA = 30;
    int256 public constant ARBITRATION_LOSS_DELTA = -100;

    enum ReputationReason {
        Manual,
        Trade,
        ArbitrationWin,
        ArbitrationLoss
    }

    struct ReputationData {
        int256 rawScore;
        uint64 lastUpdatedWeek;
        uint64 penaltyEndsAt;
    }

    mapping(address => bool) public authorizedModules;
    mapping(address => ReputationData) private _scores;

    uint64 public penaltyCooldown = 3 days;

    event ModuleAuthorizationUpdated(address indexed module, bool authorized);
    event PenaltyCooldownUpdated(uint64 previousCooldown, uint64 newCooldown);
    event ReputationUpdated(address indexed account, int256 delta, int256 newScore, ReputationReason reason);
    event PenaltyApplied(address indexed account, uint64 penaltyEndsAt);
    event PenaltyCleared(address indexed account);

    modifier onlyAuthorizedModule() {
        require(authorizedModules[msg.sender], "Reputation: module not authorized");
        _;
    }

    constructor(address accessController_, address featureFlags_) ModuleBase(address(0), address(0)) {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        __ReputationModule_init_unchained();
    }

    function __ReputationModule_init_unchained() internal onlyInitializing {
        penaltyCooldown = 3 days;
    }

    // ===== Module controls =====

    function authorizeModule(address module, bool authorized) external onlyManager {
        authorizedModules[module] = authorized;
        emit ModuleAuthorizationUpdated(module, authorized);
    }

    function setPenaltyCooldown(uint64 newCooldown) external onlyManager {
        require(newCooldown >= 1 days, "Reputation: cooldown too short");
        emit PenaltyCooldownUpdated(penaltyCooldown, newCooldown);
        penaltyCooldown = newCooldown;
    }

    // ===== Mutations =====

    function recordTrade(address account)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
        returns (int256)
    {
        return _updateReputation(account, TRADE_DELTA, ReputationReason.Trade, false);
    }

    function recordArbitrationWin(address account)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
        returns (int256)
    {
        return _updateReputation(account, ARBITRATION_WIN_DELTA, ReputationReason.ArbitrationWin, false);
    }

    function recordArbitrationLoss(address account)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
        returns (int256)
    {
        int256 newScore = _updateReputation(account, ARBITRATION_LOSS_DELTA, ReputationReason.ArbitrationLoss, true);
        return newScore;
    }

    function adjustReputation(address account, int256 delta)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
        returns (int256)
    {
        return _updateReputation(account, delta, ReputationReason.Manual, false);
    }

    function clearPenalty(address account)
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
    {
        ReputationData storage data = _scores[account];
        if (data.penaltyEndsAt != 0) {
            data.penaltyEndsAt = 0;
            emit PenaltyCleared(account);
        }
    }

    function applyDecay(address account)
        external
        onlyAuthorizedModule
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.REPUTATION)
        returns (int256)
    {
        ReputationData storage data = _scores[account];
        (int256 decayed, ) = _applyDecay(data);
        emit ReputationUpdated(account, 0, decayed, ReputationReason.Manual);
        return decayed;
    }

    // ===== Views =====

    function getReputation(address account) external view returns (int256 score, bool underPenalty) {
        ReputationData storage data = _scores[account];
        uint64 currentWeek = _currentWeek();
        uint64 lastWeek = data.lastUpdatedWeek;
        uint64 elapsed = lastWeek == 0 || currentWeek <= lastWeek ? 0 : currentWeek - lastWeek;
        score = _applyDecayValue(data.rawScore, elapsed);
        underPenalty = _currentTimestamp() < data.penaltyEndsAt && data.penaltyEndsAt != 0;
    }

    function canReceiveBonus(address account) external view returns (bool) {
        ReputationData storage data = _scores[account];
        return data.penaltyEndsAt == 0 || _currentTimestamp() >= data.penaltyEndsAt;
    }

    function rawScore(address account) external view returns (int256) {
        return _scores[account].rawScore;
    }

    function isPenaltyActive(address account) public view returns (bool) {
        ReputationData storage data = _scores[account];
        return data.penaltyEndsAt != 0 && _currentTimestamp() < data.penaltyEndsAt;
    }

    // ===== Internal helpers =====

    function _updateReputation(
        address account,
        int256 delta,
        ReputationReason reason,
        bool applyPenalty
    ) internal returns (int256 newScore) {
        ReputationData storage data = _scores[account];
        (int256 decayedScore, uint64 currentWeek) = _applyDecay(data);

        data.rawScore = decayedScore + delta;
        data.lastUpdatedWeek = currentWeek;
        newScore = data.rawScore;

        if (applyPenalty) {
            data.penaltyEndsAt = uint64(_currentTimestamp() + penaltyCooldown);
            emit PenaltyApplied(account, data.penaltyEndsAt);
        }

        emit ReputationUpdated(account, delta, newScore, reason);
    }

    function _applyDecay(ReputationData storage data) internal returns (int256 score, uint64 currentWeek) {
        currentWeek = _currentWeek();
        uint64 lastWeek = data.lastUpdatedWeek;
        uint64 elapsed = lastWeek == 0 || currentWeek <= lastWeek ? 0 : currentWeek - lastWeek;
        if (elapsed == 0) {
            score = data.rawScore;
            if (lastWeek == 0) {
                data.lastUpdatedWeek = currentWeek;
            }
            return (score, currentWeek);
        }

        score = _applyDecayValue(data.rawScore, elapsed);
        data.rawScore = score;
        data.lastUpdatedWeek = currentWeek;
    }

    function _applyDecayValue(int256 score, uint64 elapsedWeeks) internal pure returns (int256) {
        if (score == 0 || elapsedWeeks == 0) {
            return score;
        }
        if (elapsedWeeks >= MAX_DECAY_WEEKS) {
            return 0;
        }

        int256 current = score;
        int256 decayFactor = int256(uint256(BPS - DECAY_BPS));
        int256 base = int256(uint256(BPS));
        for (uint64 i = 0; i < elapsedWeeks; i++) {
            current = (current * decayFactor) / base;
        }
        return current;
    }

    function _currentTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _currentWeek() internal view virtual returns (uint64) {
        return uint64(_currentTimestamp() / 1 weeks);
    }

    uint256[45] private __gap;
}
