// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {Roles} from "../../libs/Roles.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IERC20Permit} from "../../interfaces/IERC20Permit.sol";
import {IEscrow} from "../../interfaces/IEscrow.sol";
import {SafeTransferLib} from "../../libs/SafeTransferLib.sol";

/// @title Escrow
/// @notice Minimal escrow tailored for buyer/vault funded marketplace flows.
contract Escrow is ModuleBase, IEscrow {
    using SafeTransferLib for IERC20;

    uint16 private constant BPS_DENOMINATOR = 10_000;

    error EscrowZeroAddress();
    error EscrowInvalidOrder();
    error EscrowOrderExists();
    error EscrowInvalidStatus();
    error EscrowSelfTrade();
    error EscrowAmountZero();
    error EscrowTokenZero();
    error EscrowInvalidTimeline();
    error EscrowPermitExpired();
    error EscrowVaultUnset();
    error EscrowVaultAllowanceLow();
    error EscrowVaultBalanceLow();
    error EscrowNotLocked();
    error EscrowAlreadyShipped();
    error EscrowNotSeller();
    error EscrowShipTimeout();
    error EscrowNotShipped();
    error EscrowNotBuyer();
    error EscrowPastAutoRelease();
    error EscrowNotDue();
    error EscrowNotAuthorized();
    error EscrowNotParty();
    error EscrowShipWindowOpen();
    error EscrowEmpty();
    error EscrowFeeRecipientUnset();
    error EscrowInvalidPct();
    error EscrowFeeTooHigh();
    error EscrowNotDisputed();
    error EscrowNotExtended();
    error EscrowInvalidExtensionLimit();
    error EscrowTokenNotAllowed();
    error EscrowShipWindowTooShort();
    error EscrowShipWindowTooLong();
    error EscrowReleaseWindowTooShort();
    error EscrowReleaseWindowTooLong();
    error EscrowExtensionLimitReached();
    error EscrowDisputeAfterDue();

    struct DealData {
        address buyer;
        address seller;
        address token;
        uint256 amount;
        uint64 shipBy;
        uint64 autoReleaseAt;
        uint64 createdAt;
        uint64 shippedAt;
        uint64 releasedAt;
        uint8 mode;
        uint8 extensionCount;
        uint16 feeBpsSnapshot;
        IEscrow.Status status;
        bytes32 carrierCode;
        bytes32 trackingHash;
        string metaURI;
    }

    mapping(bytes32 => DealData) private deals;

    address public feeRecipient;
    uint16 public feeBps;
    address public vault;
    uint64 public shipByMin;
    uint64 public shipByMax;
    uint64 public autoReleaseMin;
    uint64 public autoReleaseMax;
    uint8 public maxExtensionCount;

    mapping(address => bool) public allowedTokens;

    event FundsLocked(
        bytes32 indexed orderNo,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 amount,
        uint64 shipBy,
        uint64 autoReleaseAt,
        uint8 mode
    );
    event ShipmentConfirmed(
        bytes32 indexed orderNo,
        address indexed buyer,
        address indexed seller,
        bytes32 carrierCode,
        bytes32 trackingHash,
        string metaURI,
        uint64 shippedAt
    );
    event ReceiptConfirmed(
        bytes32 indexed orderNo,
        address indexed buyer,
        address indexed seller,
        uint256 payoutToSeller,
        uint256 fee,
        uint64 releasedAt
    );
    event RefundProcessed(
        bytes32 indexed orderNo,
        address indexed buyer,
        address indexed seller,
        uint256 refundToBuyer,
        bytes32 reasonHash,
        uint64 processedAt
    );
    event DisputeOpened(bytes32 indexed orderNo, address indexed buyer, address indexed seller, bytes32 reasonHash);
    event DisputeResolved(bytes32 indexed orderNo, address indexed buyer, address indexed seller, uint16 sellerPayoutBps);
    event EscrowExtended(
        bytes32 indexed orderNo,
        address indexed buyer,
        address indexed seller,
        uint64 oldAutoReleaseAt,
        uint64 newAutoReleaseAt,
        uint8 extensionCount
    );
    event AllowedTokenUpdated(address indexed token, bool allowed);
    event TimeBoundsUpdated(uint64 shipByMin, uint64 shipByMax, uint64 autoReleaseMin, uint64 autoReleaseMax);
    event ExtensionLimitUpdated(uint8 maxExtensionCount);

    constructor() ModuleBase(address(0), address(0)) {}

    function initialize(address accessController, address featureFlags) external initializer {
        __ModuleBase_init(accessController, featureFlags);
        maxExtensionCount = 1;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN
    //////////////////////////////////////////////////////////////*/

    function setFeeRecipient(address newRecipient) external onlyManager {
        if (newRecipient == address(0)) revert EscrowZeroAddress();
        feeRecipient = newRecipient;
    }

    function setFeeBps(uint16 newFeeBps) external onlyManager {
        if (newFeeBps > BPS_DENOMINATOR) revert EscrowFeeTooHigh();
        feeBps = newFeeBps;
    }

    function setVault(address newVault) external onlyManager {
        if (newVault == address(0)) revert EscrowZeroAddress();
        vault = newVault;
    }

    function setMaxExtensionCount(uint8 newMax) external onlyManager {
        if (newMax == 0) revert EscrowInvalidExtensionLimit();
        maxExtensionCount = newMax;
        emit ExtensionLimitUpdated(newMax);
    }

    function setAllowedToken(address token, bool allowed) external onlyManager {
        if (token == address(0)) revert EscrowTokenZero();
        allowedTokens[token] = allowed;
        emit AllowedTokenUpdated(token, allowed);
    }

    function setTimeBounds(
        uint64 shipByMin_,
        uint64 shipByMax_,
        uint64 autoReleaseMin_,
        uint64 autoReleaseMax_
    ) external onlyManager {
        if (shipByMax_ != 0 && shipByMax_ < shipByMin_) revert EscrowInvalidTimeline();
        if (autoReleaseMax_ != 0 && autoReleaseMax_ < autoReleaseMin_) revert EscrowInvalidTimeline();
        shipByMin = shipByMin_;
        shipByMax = shipByMax_;
        autoReleaseMin = autoReleaseMin_;
        autoReleaseMax = autoReleaseMax_;
        emit TimeBoundsUpdated(shipByMin, shipByMax, autoReleaseMin, autoReleaseMax);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function getDeal(bytes32 orderNo) external view override returns (IEscrow.Deal memory) {
        DealData storage internalDeal = deals[orderNo];
        return IEscrow.Deal({
            buyer: internalDeal.buyer,
            seller: internalDeal.seller,
            token: internalDeal.token,
            amount: internalDeal.amount,
            shipBy: internalDeal.shipBy,
            autoReleaseAt: internalDeal.autoReleaseAt,
            createdAt: internalDeal.createdAt,
            shippedAt: internalDeal.shippedAt,
            releasedAt: internalDeal.releasedAt,
            mode: internalDeal.mode,
            extensionCount: internalDeal.extensionCount,
            feeBpsSnapshot: internalDeal.feeBpsSnapshot,
            status: internalDeal.status,
            carrierCode: internalDeal.carrierCode,
            trackingHash: internalDeal.trackingHash,
            metaURI: internalDeal.metaURI
        });
    }

    /*//////////////////////////////////////////////////////////////
                          LOCK / FUND
    //////////////////////////////////////////////////////////////*/

    function lockFunds(
        bytes32 orderNo,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint64 shipBy,
        uint64 autoReleaseAt,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant whenNotPaused whenFeatureEnabled(FeatureFlagKeys.ESCROW) {
        if (permitDeadline != 0) {
            if (permitDeadline < block.timestamp) revert EscrowPermitExpired();
        }

        _lockFunds(orderNo, buyer, seller, token, amount, shipBy, autoReleaseAt, uint8(IEscrow.Mode.BuyerPay));

        if (permitDeadline != 0) {
            IERC20Permit(token).permit(buyer, address(this), amount, permitDeadline, v, r, s);
        }

        IERC20(token).safeTransferFrom(buyer, address(this), amount);
    }

    function lockFromVault(
        bytes32 orderNo,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint64 shipBy,
        uint64 autoReleaseAt
    )
        external
        override
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.ESCROW)
        onlyRole(Roles.ROLE_VAULT_CALLER)
    {
        if (vault == address(0)) revert EscrowVaultUnset();
        if (IERC20(token).allowance(vault, address(this)) < amount) revert EscrowVaultAllowanceLow();
        if (IERC20(token).balanceOf(vault) < amount) revert EscrowVaultBalanceLow();

        _lockFunds(orderNo, buyer, seller, token, amount, shipBy, autoReleaseAt, uint8(IEscrow.Mode.VaultPay));

        IERC20(token).safeTransferFrom(vault, address(this), amount);
    }

    function _lockFunds(
        bytes32 orderNo,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint64 shipBy,
        uint64 autoReleaseAt,
        uint8 mode
    ) internal {
        if (orderNo == bytes32(0)) revert EscrowInvalidOrder();
        if (deals[orderNo].status != IEscrow.Status.None) revert EscrowOrderExists();
        if (buyer == address(0) || seller == address(0)) revert EscrowZeroAddress();
        if (buyer == seller) revert EscrowSelfTrade();
        if (amount == 0) revert EscrowAmountZero();
        if (token == address(0)) revert EscrowTokenZero();
        if (!allowedTokens[token]) revert EscrowTokenNotAllowed();

        uint64 currentTime = uint64(block.timestamp);
        if (!(autoReleaseAt > shipBy && shipBy > currentTime)) revert EscrowInvalidTimeline();

        uint64 shipDelta = shipBy - currentTime;
        if (shipByMin != 0 && shipDelta < shipByMin) revert EscrowShipWindowTooShort();
        if (shipByMax != 0 && shipDelta > shipByMax) revert EscrowShipWindowTooLong();

        uint64 releaseDelta = autoReleaseAt - currentTime;
        if (autoReleaseMin != 0 && releaseDelta < autoReleaseMin) revert EscrowReleaseWindowTooShort();
        if (autoReleaseMax != 0 && releaseDelta > autoReleaseMax) revert EscrowReleaseWindowTooLong();

        deals[orderNo] = DealData({
            buyer: buyer,
            seller: seller,
            token: token,
            amount: amount,
            shipBy: shipBy,
            autoReleaseAt: autoReleaseAt,
            createdAt: currentTime,
            shippedAt: 0,
            releasedAt: 0,
            mode: mode,
            extensionCount: 0,
            feeBpsSnapshot: feeBps,
            status: IEscrow.Status.Locked,
            carrierCode: bytes32(0),
            trackingHash: bytes32(0),
            metaURI: ""
        });

        emit FundsLocked(orderNo, buyer, seller, token, amount, shipBy, autoReleaseAt, mode);
    }

    /*//////////////////////////////////////////////////////////////
                          SHIPMENT / RECEIPT
    //////////////////////////////////////////////////////////////*/

    function confirmShipment(
        bytes32 orderNo,
        bytes32 carrierCode,
        bytes32 trackingHash,
        string calldata metaURI
    ) external override whenNotPaused whenFeatureEnabled(FeatureFlagKeys.ESCROW) {
        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Locked) revert EscrowNotLocked();
        if (deal.shippedAt != 0) revert EscrowAlreadyShipped();
        if (!(msg.sender == deal.seller || accessController.hasRole(Roles.ROLE_SHIP_EXECUTOR, msg.sender)))
            revert EscrowNotSeller();
        if (block.timestamp > deal.shipBy) revert EscrowShipTimeout();

        deal.status = IEscrow.Status.Shipped;
        deal.shippedAt = uint64(block.timestamp);
        deal.carrierCode = carrierCode;
        deal.trackingHash = trackingHash;
        deal.metaURI = metaURI;

        emit ShipmentConfirmed(orderNo, deal.buyer, deal.seller, carrierCode, trackingHash, metaURI, deal.shippedAt);
    }

    function confirmReceipt(bytes32 orderNo) external override nonReentrant whenNotPaused {
        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Shipped) revert EscrowNotShipped();
        if (msg.sender != deal.buyer) revert EscrowNotBuyer();
        if (block.timestamp > deal.autoReleaseAt) revert EscrowPastAutoRelease();

        (uint256 sellerAmount, uint256 feeAmount, uint256 buyerAmount) = _payout(deal, BPS_DENOMINATOR);
        deal.status = IEscrow.Status.Completed;

        uint64 releasedAt = uint64(block.timestamp);
        deal.releasedAt = releasedAt;
        emit ReceiptConfirmed(orderNo, deal.buyer, deal.seller, sellerAmount, feeAmount, releasedAt);
        if (buyerAmount > 0) {
            emit RefundProcessed(orderNo, deal.buyer, deal.seller, buyerAmount, bytes32(0), releasedAt);
        }
    }

    function releaseIfTimeout(bytes32 orderNo) external override nonReentrant {
        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Shipped) revert EscrowNotShipped();
        if (block.timestamp < deal.autoReleaseAt) revert EscrowNotDue();

        (uint256 sellerAmount, uint256 feeAmount, uint256 buyerAmount) = _payout(deal, BPS_DENOMINATOR);
        deal.status = IEscrow.Status.Completed;

        uint64 releasedAt = uint64(block.timestamp);
        deal.releasedAt = releasedAt;
        emit ReceiptConfirmed(orderNo, deal.buyer, deal.seller, sellerAmount, feeAmount, releasedAt);
        if (buyerAmount > 0) {
            emit RefundProcessed(orderNo, deal.buyer, deal.seller, buyerAmount, bytes32(0), releasedAt);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               REFUND
    //////////////////////////////////////////////////////////////*/

    function requestRefund(bytes32 orderNo, bytes32 reasonHash) external override nonReentrant {
        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Locked) revert EscrowNotLocked();
        if (!(msg.sender == deal.buyer || accessController.hasRole(Roles.ROLE_ARBITER, msg.sender)))
            revert EscrowNotAuthorized();
        if (block.timestamp <= deal.shipBy) revert EscrowShipWindowOpen();

        uint256 refundAmount = deal.amount;
        if (refundAmount == 0) revert EscrowEmpty();
        deal.amount = 0;
        deal.status = IEscrow.Status.Refunded;
        deal.releasedAt = uint64(block.timestamp);

        IERC20(deal.token).safeTransfer(deal.buyer, refundAmount);
        emit RefundProcessed(orderNo, deal.buyer, deal.seller, refundAmount, reasonHash, uint64(block.timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                          DISPUTE HANDLING
    //////////////////////////////////////////////////////////////*/

    function openDispute(bytes32 orderNo, bytes32 reasonHash) external override {
        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Shipped) revert EscrowNotShipped();
        if (!(msg.sender == deal.buyer || msg.sender == deal.seller)) revert EscrowNotParty();
        if (block.timestamp >= deal.autoReleaseAt) revert EscrowDisputeAfterDue();

        deal.status = IEscrow.Status.Disputed;
        emit DisputeOpened(orderNo, deal.buyer, deal.seller, reasonHash);
    }

    function resolveDispute(bytes32 orderNo, uint16 sellerPayoutBps)
        external
        override
        nonReentrant
        onlyRole(Roles.ROLE_ARBITER)
    {
        if (sellerPayoutBps > BPS_DENOMINATOR) revert EscrowInvalidPct();

        DealData storage deal = deals[orderNo];
        if (deal.status != IEscrow.Status.Disputed) revert EscrowNotDisputed();

        (uint256 sellerAmount, uint256 feeAmount, uint256 buyerAmount) = _payout(deal, sellerPayoutBps);
        deal.status = IEscrow.Status.Resolved;

        uint64 releasedAt = uint64(block.timestamp);
        deal.releasedAt = releasedAt;
        emit DisputeResolved(orderNo, deal.buyer, deal.seller, sellerPayoutBps);
        emit ReceiptConfirmed(orderNo, deal.buyer, deal.seller, sellerAmount, feeAmount, releasedAt);
        if (buyerAmount > 0) {
            emit RefundProcessed(orderNo, deal.buyer, deal.seller, buyerAmount, bytes32(0), releasedAt);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              EXTENSION
    //////////////////////////////////////////////////////////////*/

    function extendEscrow(bytes32 orderNo, uint64 newAutoReleaseAt) external override whenNotPaused {
        DealData storage deal = deals[orderNo];
        if (
            !(deal.status == IEscrow.Status.Locked || deal.status == IEscrow.Status.Shipped)
        ) revert EscrowInvalidStatus();
        if (
            !(
                msg.sender == deal.buyer
                    || msg.sender == deal.seller
                    || accessController.hasRole(Roles.ROLE_ARBITER, msg.sender)
            )
        ) revert EscrowNotAuthorized();
        if (newAutoReleaseAt <= deal.autoReleaseAt) revert EscrowNotExtended();
        if (deal.extensionCount >= maxExtensionCount) revert EscrowExtensionLimitReached();

        uint64 releaseDelta = newAutoReleaseAt - uint64(block.timestamp);
        if (autoReleaseMin != 0 && releaseDelta < autoReleaseMin) revert EscrowReleaseWindowTooShort();
        if (autoReleaseMax != 0 && releaseDelta > autoReleaseMax) revert EscrowReleaseWindowTooLong();

        uint64 oldAutoReleaseAt = deal.autoReleaseAt;
        deal.autoReleaseAt = newAutoReleaseAt;
        deal.extensionCount += 1;

        emit EscrowExtended(orderNo, deal.buyer, deal.seller, oldAutoReleaseAt, newAutoReleaseAt, deal.extensionCount);
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _payout(DealData storage deal, uint16 sellerShareBps)
        internal
        returns (uint256 sellerAmount, uint256 feeAmount, uint256 buyerAmount)
    {
        if (deal.amount == 0) revert EscrowEmpty();
        if (feeRecipient == address(0)) revert EscrowFeeRecipientUnset();

        uint256 amount = deal.amount;
        deal.amount = 0;

        uint16 snapshotBps = deal.feeBpsSnapshot;
        if (snapshotBps == 0 && feeBps > 0) {
            snapshotBps = feeBps;
        }
        feeAmount = (amount * snapshotBps) / BPS_DENOMINATOR;
        uint256 net = amount - feeAmount;
        sellerAmount = (net * sellerShareBps) / BPS_DENOMINATOR;
        buyerAmount = net - sellerAmount;

        IERC20 token = IERC20(deal.token);
        if (feeAmount > 0) {
            token.safeTransfer(feeRecipient, feeAmount);
        }
        if (sellerAmount > 0) {
            token.safeTransfer(deal.seller, sellerAmount);
        }
        if (buyerAmount > 0) {
            token.safeTransfer(deal.buyer, buyerAmount);
        }
    }
}
