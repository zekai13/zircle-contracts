// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ReputationModule} from "../../contracts/modules/reputation/ReputationModule.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract ReputationHarness is ReputationModule {
    uint256 private _mockTime;

    constructor() ReputationModule(address(0), address(0)) {}

    function setTime(uint256 newTime) external {
        _mockTime = newTime;
    }

    function advance(uint256 delta) external {
        _mockTime += delta;
    }

    function _currentTimestamp() internal view override returns (uint256) {
        return _mockTime;
    }
}

contract ReputationInvoker {
    ReputationModule private module;

    constructor(ReputationModule module_) {
        module = module_;
    }

    function trade(address account) external {
        module.recordTrade(account);
    }
}

contract ReputationTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    ReputationHarness private reputation;

    address private constant USER = address(0xBEEF);

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

        address reputationProxy = deployProxy(
            address(new ReputationHarness()),
            abi.encodeWithSelector(
                ReputationModule.initialize.selector,
                controllerProxy,
                flagsProxy
            )
        );
        reputation = ReputationHarness(reputationProxy);
        reputation.setTime(block.timestamp);

        flags.setFlag(FeatureFlagKeys.REPUTATION, true);
        reputation.authorizeModule(address(this), true);
    }

    function test_REP_01_DecayExtremes() public {
        reputation.setTime(1 weeks);
        reputation.recordTrade(USER);

        (int256 score, bool penalty) = reputation.getReputation(USER);
        assertEq(score, 50, "REP-01: initial score mismatch");
        assertFalse(penalty, "REP-01: penalty should be inactive");

        reputation.advance(1 weeks);
        (score, ) = reputation.getReputation(USER);
        assertEq(score, 49, "REP-01: score after one week decay incorrect");

        reputation.advance(260 weeks);
        (score, ) = reputation.getReputation(USER);
        assertEq(score, 0, "REP-01: score should decay to zero after long interval");
    }

    function test_REP_02_PenaltyWindow() public {
        reputation.setTime(10);
        reputation.recordTrade(USER);
        int256 scoreBefore = reputation.recordArbitrationLoss(USER);
        assertTrue(scoreBefore < 0, "REP-02: loss should drop score negative");
        assertFalse(reputation.canReceiveBonus(USER), "REP-02: bonus eligibility should be false during penalty");

        reputation.advance(reputation.penaltyCooldown());
        assertTrue(reputation.canReceiveBonus(USER), "REP-02: penalty should expire after cooldown");
        assertFalse(reputation.isPenaltyActive(USER), "REP-02: penalty flag should be cleared");
    }

    function test_REP_03_UnauthorizedModuleBlocked() public {
        ReputationInvoker invoker = new ReputationInvoker(reputation);

        (bool success, ) = address(invoker).call(abi.encodeWithSignature("trade(address)", USER));
        assertFalse(success, "REP-03: unauthorized module should revert");

        reputation.authorizeModule(address(invoker), true);
        reputation.setTime(block.timestamp);
        invoker.trade(USER);
        (int256 score, ) = reputation.getReputation(USER);
        assertEq(score, 50, "REP-03: authorized module should update reputation");
    }
}
