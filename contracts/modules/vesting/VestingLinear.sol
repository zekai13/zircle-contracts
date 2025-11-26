// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {SafeERC20} from "../../libs/SafeERC20.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

/// @title VestingLinear
/// @notice Linear vesting schedule with optional replenishment.
contract VestingLinear is ModuleBase {
    using SafeERC20 for IERC20;

    struct Schedule {
        uint256 total;
        uint256 released;
        uint64 start;
        uint64 cliff;
        uint64 duration;
    }

    IERC20 public token;
    mapping(address => Schedule) public schedules;

    event ScheduleCreated(address indexed beneficiary, uint256 total, uint64 start, uint64 cliff, uint64 duration);
    event ScheduleUpdated(address indexed beneficiary, uint256 total, uint64 start, uint64 cliff, uint64 duration);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    constructor(address accessController_, address featureFlags_, address token_)
        ModuleBase(address(0), address(0))
    {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, token_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_, address token_) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        require(token_ != address(0), "VestingLinear: token zero");
        token = IERC20(token_);
    }

    function createOrUpdateSchedule(
        address beneficiary,
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration
    ) external onlyManager whenFeatureEnabled(FeatureFlagKeys.VESTING) {
        require(beneficiary != address(0), "VestingLinear: beneficiary zero");
        require(duration > 0, "VestingLinear: duration zero");
        require(cliff <= duration, "VestingLinear: cliff>duration");

        Schedule storage sched = schedules[beneficiary];
        if (sched.total == 0) {
            sched.start = start;
            sched.cliff = cliff;
            sched.duration = duration;
            emit ScheduleCreated(beneficiary, total, start, cliff, duration);
        } else {
            require(total >= sched.released, "VestingLinear: total < released");
            sched.start = start;
            sched.cliff = cliff;
            sched.duration = duration;
            emit ScheduleUpdated(beneficiary, total, start, cliff, duration);
        }
        sched.total = total;
    }

    function release() external nonReentrant whenFeatureEnabled(FeatureFlagKeys.VESTING) {
        Schedule storage sched = schedules[msg.sender];
        uint256 vested = _vestedAmount(sched.total, sched.start, sched.cliff, sched.duration, block.timestamp);
        require(vested > sched.released, "VestingLinear: nothing to release");

        uint256 releasable = vested - sched.released;
        sched.released = vested;
        token.safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, releasable);
    }

    function vestedAmount(address beneficiary) public view returns (uint256) {
        Schedule memory sched = schedules[beneficiary];
        return _vestedAmount(sched.total, sched.start, sched.cliff, sched.duration, block.timestamp);
    }

    function releasableAmount(address beneficiary) external view returns (uint256) {
        Schedule memory sched = schedules[beneficiary];
        uint256 vested = _vestedAmount(sched.total, sched.start, sched.cliff, sched.duration, block.timestamp);
        if (vested <= sched.released) {
            return 0;
        }
        return vested - sched.released;
    }

    function _vestedAmount(
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        uint256 timestamp
    ) internal pure returns (uint256) {
        if (total == 0) {
            return 0;
        }
        if (timestamp <= start) {
            return 0;
        }
        uint256 elapsed = timestamp - start;
        if (elapsed < cliff) {
            return 0;
        }
        if (elapsed >= duration) {
            return total;
        }
        return (total * elapsed) / duration;
    }

    uint256[45] private __gap;
}
