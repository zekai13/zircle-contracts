// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEscrow {
    enum Mode {
        BuyerPay,
        VaultPay
    }

    enum Status {
        None,
        Locked,
        Shipped,
        Completed,
        Refunded,
        Disputed,
        Resolved,
        Extended
    }

    struct Deal {
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
        Status status;
        bytes32 carrierCode;
        bytes32 trackingHash;
        string metaURI;
    }

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
    ) external;

    function lockFromVault(
        bytes32 orderNo,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint64 shipBy,
        uint64 autoReleaseAt
    ) external;

    function confirmShipment(
        bytes32 orderNo,
        bytes32 carrierCode,
        bytes32 trackingHash,
        string calldata metaURI
    ) external;

    function confirmReceipt(bytes32 orderNo) external;

    function releaseIfTimeout(bytes32 orderNo) external;

    function requestRefund(bytes32 orderNo, bytes32 reasonHash) external;

    function openDispute(bytes32 orderNo, bytes32 reasonHash) external;

    function resolveDispute(bytes32 orderNo, uint16 sellerPayoutBps) external;

    function extendEscrow(bytes32 orderNo, uint64 newAutoReleaseAt) external;

    function getDeal(bytes32 orderNo) external view returns (Deal memory);
}
