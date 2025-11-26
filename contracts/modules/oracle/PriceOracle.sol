// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../interfaces/external/AggregatorV3Interface.sol";
import {ModuleBase} from "../../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {Common} from "../../libs/Common.sol";
import {DecimalMath} from "../../libs/DecimalMath.sol";

/// @title Price Oracle
/// @notice Wraps Chainlink feeds and caches normalized prices for the protocol.
contract PriceOracle is ModuleBase, Common {
    AggregatorV3Interface public feed;
    uint8 public feedDecimals;
    uint256 public feedScalingFactor;

    uint256 public expirySec;
    uint16 public maxPriceChangeBps;

    uint256 public lastPriceE18;
    uint64 public lastSyncedAt;
    uint64 public lastOracleTimestamp;

    uint256 public feeUsdFixedE18;
    uint16 public feePctBps;

    uint256 public nativeUsdPriceE18;

    event PriceSynced(uint256 priceE18, uint64 indexed oracleTimestamp, uint64 indexed syncedAt);
    event MaxPriceChangeUpdated(uint16 previousBps, uint16 newBps);
    event ExpiryUpdated(uint256 previousExpiry, uint256 newExpiry);
    event FeeConfigUpdated(uint256 previousFixed, uint16 previousPct, uint256 newFixed, uint16 newPct);
    event NativeUsdPriceUpdated(uint256 previousPrice, uint256 newPrice);

    constructor(
        address accessController_,
        address featureFlags_,
        AggregatorV3Interface feed_,
        uint256 expirySec_,
        uint16 maxPriceChangeBps_,
        uint256 feeUsdFixedE18_,
        uint16 feePctBps_
    ) ModuleBase(address(0), address(0)) {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, feed_, expirySec_, maxPriceChangeBps_, feeUsdFixedE18_, feePctBps_);
        }
        _disableInitializers();
    }

    function initialize(
        address accessController_,
        address featureFlags_,
        AggregatorV3Interface feed_,
        uint256 expirySec_,
        uint16 maxPriceChangeBps_,
        uint256 feeUsdFixedE18_,
        uint16 feePctBps_
    ) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        require(address(feed_) != address(0), "Oracle: feed required");
        feed = feed_;
        uint8 decimals_ = feed_.decimals();
        require(decimals_ <= 18, "Oracle: decimals unsupported");
        feedDecimals = decimals_;
        feedScalingFactor = decimals_ == 18 ? 1 : 10 ** (18 - decimals_);
        _setExpiry(expirySec_);
        _setMaxPriceChange(maxPriceChangeBps_);
        _setFeeConfig(feeUsdFixedE18_, feePctBps_);
    }

    function syncPrice()
        external
        onlyManager
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ORACLE)
    {
        (uint256 normalizedPrice, uint64 updatedAt) = _readFeed();
        lastPriceE18 = normalizedPrice;
        lastSyncedAt = uint64(block.timestamp);
        lastOracleTimestamp = updatedAt;
        emit PriceSynced(normalizedPrice, updatedAt, lastSyncedAt);
    }

    function latestPrice() public view whenFeatureEnabled(FeatureFlagKeys.ORACLE) returns (uint256) {
        require(!paused(), "Oracle: paused");
        require(lastPriceE18 > 0, "Oracle: unsynced");
        require(block.timestamp - lastSyncedAt <= expirySec, "Oracle: price stale");

        (uint256 currentPrice, uint64 oracleTimestamp) = _readFeed();
        require(oracleTimestamp >= lastOracleTimestamp, "Oracle: feed stale");

        uint256 allowedChange = (lastPriceE18 * maxPriceChangeBps) / BPS;
        uint256 diff = currentPrice > lastPriceE18 ? currentPrice - lastPriceE18 : lastPriceE18 - currentPrice;
        require(diff <= allowedChange, "Oracle: price jump too large");

        return lastPriceE18;
    }

    function convertToUsd(uint256 zirAmount6) external view returns (uint256) {
        uint256 priceE18 = latestPrice();
        return DecimalMath.mulDiv(zirAmount6, priceE18, ZIR_DECIMALS);
    }

    function convertFromUsd(uint256 usdAmount18) public view returns (uint256) {
        uint256 priceE18 = latestPrice();
        require(priceE18 > 0, "Oracle: price zero");
        return DecimalMath.mulDiv(usdAmount18, ZIR_DECIMALS, priceE18);
    }

    function quoteFee(uint256 zirAmount6) external view returns (uint256) {
        uint256 priceE18 = latestPrice();
        uint256 usdAmount = DecimalMath.mulDiv(zirAmount6, priceE18, ZIR_DECIMALS);
        uint256 variableUsd = (usdAmount * feePctBps) / BPS;
        uint256 totalUsd = feeUsdFixedE18 + variableUsd;
        if (totalUsd == 0) {
            return 0;
        }
        return DecimalMath.mulDiv(totalUsd, ZIR_DECIMALS, priceE18);
    }

    function setExpiry(uint256 expirySec_) external onlyManager {
        _setExpiry(expirySec_);
    }

    function setMaxPriceChangeBps(uint16 maxPriceChangeBps_) external onlyManager {
        _setMaxPriceChange(maxPriceChangeBps_);
    }

    function setFeeConfig(uint256 feeUsdFixedE18_, uint16 feePctBps_) external onlyManager {
        _setFeeConfig(feeUsdFixedE18_, feePctBps_);
    }

    function setNativeUsdPrice(uint256 nativeUsdPriceE18_) external onlyManager {
        emit NativeUsdPriceUpdated(nativeUsdPriceE18, nativeUsdPriceE18_);
        nativeUsdPriceE18 = nativeUsdPriceE18_;
    }

    function _setExpiry(uint256 expirySec_) internal {
        require(expirySec_ >= 60 && expirySec_ <= 300, "Oracle: expiry out of range");
        emit ExpiryUpdated(expirySec, expirySec_);
        expirySec = expirySec_;
    }

    function _setMaxPriceChange(uint16 maxPriceChangeBps_) internal {
        require(maxPriceChangeBps_ >= 1 && maxPriceChangeBps_ <= 1_000, "Oracle: change bps invalid");
        emit MaxPriceChangeUpdated(maxPriceChangeBps, maxPriceChangeBps_);
        maxPriceChangeBps = maxPriceChangeBps_;
    }

    function _setFeeConfig(uint256 feeUsdFixedE18_, uint16 feePctBps_) internal {
        emit FeeConfigUpdated(feeUsdFixedE18, feePctBps, feeUsdFixedE18_, feePctBps_);
        feeUsdFixedE18 = feeUsdFixedE18_;
        feePctBps = feePctBps_;
    }

    function _readFeed() internal view returns (uint256 priceE18, uint64 updatedAt) {
        (uint80 roundId, int256 answer, , uint256 updatedAt_, uint80 answeredInRound) = feed.latestRoundData();
        require(answer > 0, "Oracle: invalid price");
        require(updatedAt_ > 0, "Oracle: round incomplete");
        require(answeredInRound >= roundId, "Oracle: stale round");
        priceE18 = _normalizePrice(uint256(answer));
        updatedAt = uint64(updatedAt_);
    }

    function _normalizePrice(uint256 answer) internal view returns (uint256) {
        return answer * feedScalingFactor;
    }

    uint256[44] private __gap;
}
