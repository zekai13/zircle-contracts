// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {PriceOracle} from "../../contracts/modules/oracle/PriceOracle.sol";
import {AggregatorV3Interface} from "../../contracts/interfaces/external/AggregatorV3Interface.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockAggregator is AggregatorV3Interface {
    uint8 private immutable _decimals;
    int256 private _answer;
    uint80 private _roundId;
    uint256 private _updatedAt;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _answer = initialAnswer;
        _roundId = 1;
        _updatedAt = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = _roundId;
        answer = _answer;
        startedAt = _updatedAt;
        updatedAt = _updatedAt;
        answeredInRound = _roundId;
    }

    function setAnswer(int256 answer, uint256 updatedAt) external {
        _answer = answer;
        _updatedAt = updatedAt;
        _roundId += 1;
    }
}

contract PriceOracleHarness is PriceOracle {
    constructor()
        PriceOracle(
            address(0),
            address(0),
            AggregatorV3Interface(address(0)),
            0,
            0,
            0,
            0
        )
    {}

    function forceState(uint256 priceE18, uint64 syncAt, uint64 oracleTimestamp) external {
        lastPriceE18 = priceE18;
        lastSyncedAt = syncAt;
        lastOracleTimestamp = oracleTimestamp;
    }
}

contract OracleTest is TestBase {
    AccessController private controller;
    FeatureFlags private flags;
    MockAggregator private aggregator;
    PriceOracleHarness private oracle;

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
        aggregator = new MockAggregator(8, 1_500_000_00); // 1.5 USD per ZIR
        address oracleProxy = deployProxy(
            address(new PriceOracleHarness()),
            abi.encodeWithSelector(
                PriceOracle.initialize.selector,
                controllerProxy,
                flagsProxy,
                aggregator,
                120,
                300,
                0,
                0
            )
        );
        oracle = PriceOracleHarness(oracleProxy);
    }

    function _enableFeature() private {
        flags.setFlag(FeatureFlagKeys.ORACLE, true);
    }

    function test_ORA_01_PriceGuards() public {
        _enableFeature();

        callAndExpectRevert(
            address(oracle),
            abi.encodeWithSignature("latestPrice()"),
            "ORA-01: latestPrice should revert before sync"
        );

        oracle.syncPrice();
        uint256 cachedPrice = oracle.latestPrice();
        assertEq(cachedPrice, oracle.lastPriceE18(), "ORA-01: cached price mismatch");

        // Negative price detection
        aggregator.setAnswer(-1, block.timestamp);
        callAndExpectRevert(
            address(oracle),
            abi.encodeWithSignature("latestPrice()"),
            "ORA-01: negative feed should revert"
        );

        // Restore positive price and sync
        aggregator.setAnswer(1_500_000_00, block.timestamp);
        oracle.syncPrice();

        // Exceeding price jump beyond threshold -> revert
        aggregator.setAnswer(2_500_000_00, block.timestamp);
        callAndExpectRevert(
            address(oracle),
            abi.encodeWithSignature("latestPrice()"),
            "ORA-01: price jump beyond threshold should revert"
        );

        // Stale price detection using harness override
        vm.warp(block.timestamp + oracle.expirySec() + 10);
        oracle.forceState(oracle.lastPriceE18(), uint64(block.timestamp - oracle.expirySec() - 1), oracle.lastOracleTimestamp());
        callAndExpectRevert(
            address(oracle),
            abi.encodeWithSignature("latestPrice()"),
            "ORA-01: stale cached price should revert"
        );
    }

    function test_ORA_02_ConversionsAndFeeQuote() public {
        _enableFeature();
        aggregator.setAnswer(2_500_000_00, block.timestamp);
        oracle.syncPrice();

        uint256 priceE18 = oracle.latestPrice();
        assertEq(priceE18, 2_500_000_000000000000, "ORA-02: normalized price incorrect");

        uint256 zirAmount = 10 * 1_000_000; // 10 ZIR
        uint256 usdAmount = oracle.convertToUsd(zirAmount);
        assertEq(usdAmount, 25_000_000_000000000000, "ORA-02: ZIR->USD conversion mismatch");

        uint256 zirRecovered = oracle.convertFromUsd(usdAmount);
        assertEq(zirRecovered, zirAmount, "ORA-02: USD->ZIR conversion should round trip");

        oracle.setFeeConfig(1_000_000_000000000000, 100); // 1 USD fixed + 1%
        uint256 feeZir = oracle.quoteFee(zirAmount);
        // Expected fee: (1 USD + 0.25 USD) / 2.5 = 0.5 ZIR -> 500000 micro
        assertEq(feeZir, 500_000, "ORA-02: fee quote mismatch");
    }
}
