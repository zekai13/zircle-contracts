// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {IERC20} from "../../contracts/interfaces/IERC20.sol";
import {Escrow} from "../../contracts/modules/escrow/Escrow.sol";
import {IEscrow} from "../../contracts/interfaces/IEscrow.sol";

contract MockERC20 is IERC20 {
    string public constant name = "MockToken";
    string public constant symbol = "MTK";
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        require(current >= value, "ALLOWANCE");
        _allowances[from][msg.sender] = current - value;
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external {
        _totalSupply += value;
        _balances[to] += value;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(_balances[from] >= value, "BALANCE");
        _balances[from] -= value;
        _balances[to] += value;
    }
}

contract EscrowTest is Test {
    Escrow escrow;
    AccessController controller;
    FeatureFlags flags;
    MockERC20 token;

    address buyer;
    address seller;
    address vault;
    address feeRecipient;

    function setUp() public {
        controller = new AccessController(address(this), address(0), address(0), address(0), address(this));
        controller.grantRole(Roles.ROLE_MANAGER, address(this));
        controller.grantRole(Roles.ROLE_ARBITER, address(this));
        controller.grantRole(Roles.ROLE_PAUSER, address(this));
        controller.grantRole(Roles.ROLE_VAULT_CALLER, address(this));
        controller.grantRole(Roles.ROLE_SHIP_EXECUTOR, address(this));

        flags = new FeatureFlags(address(controller));
        flags.setFlag(FeatureFlagKeys.ESCROW, true);

        escrow = new Escrow();
        escrow.initialize(address(controller), address(flags));

        token = new MockERC20();
        buyer = address(0xB0B);
        seller = address(0xB0C);
        vault = address(0xB0D);
        feeRecipient = address(0xFEE);

        controller.grantRole(Roles.ROLE_MANAGER, address(this));
        controller.grantRole(Roles.ROLE_ARBITER, address(this));
        controller.grantRole(Roles.ROLE_VAULT_CALLER, address(this));
        controller.grantRole(Roles.ROLE_SHIP_EXECUTOR, seller);

        escrow.setFeeRecipient(feeRecipient);
        escrow.setFeeBps(500); // 5%
        escrow.setVault(vault);
        escrow.setAllowedToken(address(token), true);
        escrow.setMaxExtensionCount(1);

        flags.setFlag(FeatureFlagKeys.ESCROW, true);

        token.mint(buyer, 1_000 ether);
        token.mint(vault, 1_000 ether);
    }

    function testLockFundsCompleteFlow() public {
        uint256 amount = 100 ether;
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.lockFunds(
            bytes32("order-1"),
            buyer,
            seller,
            address(token),
            amount,
            uint64(block.timestamp + 3 days),
            uint64(block.timestamp + 7 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        IEscrow.Deal memory deal = escrow.getDeal(bytes32("order-1"));
        assertEq(deal.amount, amount);
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Locked));
        assertGt(deal.createdAt, 0, "createdAt missing");
        assertEq(deal.feeBpsSnapshot, 500, "fee snapshot");

        vm.prank(seller);
        escrow.confirmShipment(bytes32("order-1"), bytes32("SF"), keccak256(bytes("TRACK123")), "ipfs://meta");

        deal = escrow.getDeal(bytes32("order-1"));
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Shipped));
        assertGt(deal.shippedAt, 0);

        vm.prank(buyer);
        escrow.confirmReceipt(bytes32("order-1"));

        deal = escrow.getDeal(bytes32("order-1"));
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Completed));
        assertGt(deal.releasedAt, 0, "releasedAt missing");

        assertEq(token.balanceOf(seller), 95 ether);
        assertEq(token.balanceOf(feeRecipient), 5 ether);
    }

    function testFeeSnapshotRespectedAfterFeeChange() public {
        bytes32 orderA = bytes32("order-snapshot-A");
        uint256 amount = 100 ether;

        vm.startPrank(buyer);
        token.approve(address(escrow), type(uint256).max);
        escrow.lockFunds(
            orderA,
            buyer,
            seller,
            address(token),
            amount,
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 6 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.prank(seller);
        escrow.confirmShipment(orderA, bytes32("SF"), keccak256(bytes("TRACK-A")), "");

        // Increase fee for future orders
        escrow.setFeeBps(1_000);

        bytes32 orderB = bytes32("order-snapshot-B");
        vm.startPrank(buyer);
        escrow.lockFunds(
            orderB,
            buyer,
            seller,
            address(token),
            amount,
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 6 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.prank(seller);
        escrow.confirmShipment(orderB, bytes32("SF"), keccak256(bytes("TRACK-B")), "");

        vm.prank(buyer);
        escrow.confirmReceipt(orderA);
        vm.prank(buyer);
        escrow.confirmReceipt(orderB);

        assertEq(token.balanceOf(seller), 95 ether + 90 ether, "seller payout");

        IEscrow.Deal memory dealA = escrow.getDeal(orderA);
        IEscrow.Deal memory dealB = escrow.getDeal(orderB);
        assertEq(dealA.feeBpsSnapshot, 500, "snapshot A");
        assertEq(dealB.feeBpsSnapshot, 1_000, "snapshot B");
    }

    function testReleaseIfTimeout() public {
        bytes32 orderNo = bytes32("order-2");
        uint256 amount = 50 ether;
        vm.startPrank(buyer);
        token.approve(address(escrow), amount);
        escrow.lockFunds(
            orderNo,
            buyer,
            seller,
            address(token),
            amount,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.prank(seller);
        escrow.confirmShipment(orderNo, bytes32("SF"), keccak256(bytes("TRACK")), "");

        vm.warp(block.timestamp + 3 days);
        escrow.releaseIfTimeout(orderNo);

        IEscrow.Deal memory deal = escrow.getDeal(orderNo);
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Completed));
        assertGt(deal.releasedAt, 0, "releasedAt");
        assertEq(token.balanceOf(seller), 47.5 ether);
    }

    function testRequestRefundAfterShipBy() public {
        bytes32 orderNo = bytes32("order-3");
        vm.startPrank(buyer);
        token.approve(address(escrow), 40 ether);
        escrow.lockFunds(
            orderNo,
            buyer,
            seller,
            address(token),
            40 ether,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 5 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        vm.prank(buyer);
        escrow.requestRefund(orderNo, keccak256("late"));

        IEscrow.Deal memory deal = escrow.getDeal(orderNo);
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Refunded));
        assertEq(token.balanceOf(buyer), 1_000 ether);
    }

    function testVaultFundedFlow() public {
        bytes32 orderNo = bytes32("order-4");
        vm.prank(vault);
        token.approve(address(escrow), 80 ether);

        escrow.lockFromVault(
            orderNo,
            buyer,
            seller,
            address(token),
            80 ether,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 5 days)
        );

        IEscrow.Deal memory deal = escrow.getDeal(orderNo);
        assertEq(deal.amount, 80 ether);
        assertEq(uint8(deal.mode), uint8(IEscrow.Mode.VaultPay));

        vm.prank(seller);
        escrow.confirmShipment(orderNo, bytes32("YD"), keccak256(bytes("TRACK-VAULT")), "");
    }

    function testOpenAndResolveDispute() public {
        bytes32 orderNo = bytes32("order-5");
        vm.startPrank(buyer);
        token.approve(address(escrow), 60 ether);
        escrow.lockFunds(
            orderNo,
            buyer,
            seller,
            address(token),
            60 ether,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 5 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.prank(seller);
        escrow.confirmShipment(orderNo, bytes32("SF"), keccak256(bytes("TRACK-1")), "");

        vm.prank(buyer);
        escrow.openDispute(orderNo, keccak256("quality"));

        vm.prank(address(this));
        escrow.resolveDispute(orderNo, 6_000);

        IEscrow.Deal memory deal = escrow.getDeal(orderNo);
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Resolved));
        assertGt(deal.releasedAt, 0, "releasedAt");
        // Seller gets 60% of net (60 - 3 fee = 57, seller 34.2)
        assertEq(token.balanceOf(seller), 34.2 ether);
        assertEq(token.balanceOf(buyer), 1_000 ether - 60 ether + 22.8 ether);
        assertEq(token.balanceOf(feeRecipient), 3 ether);
    }

    function testExtendEscrow() public {
        bytes32 orderNo = bytes32("order-6");
        vm.startPrank(buyer);
        token.approve(address(escrow), 10 ether);
        escrow.lockFunds(
            orderNo,
            buyer,
            seller,
            address(token),
            10 ether,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 3 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.prank(buyer);
        escrow.extendEscrow(orderNo, uint64(block.timestamp + 5 days));

        IEscrow.Deal memory deal = escrow.getDeal(orderNo);
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Locked));
        assertEq(deal.autoReleaseAt, uint64(block.timestamp + 5 days));
        assertEq(deal.extensionCount, 1);
        assertGt(deal.createdAt, 0, "createdAt");

        vm.expectRevert(Escrow.EscrowExtensionLimitReached.selector);
        vm.prank(buyer);
        escrow.extendEscrow(orderNo, uint64(block.timestamp + 7 days));
    }

    function testTimeBoundsEnforced() public {
        escrow.setTimeBounds(uint64(1 days), uint64(5 days), uint64(3 days), uint64(12 days));

        vm.startPrank(buyer);
        token.approve(address(escrow), type(uint256).max);
        vm.expectRevert(Escrow.EscrowShipWindowTooShort.selector);
        escrow.lockFunds(
            bytes32("order-too-short"),
            buyer,
            seller,
            address(token),
            10 ether,
            uint64(block.timestamp + 6 hours),
            uint64(block.timestamp + 4 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.expectRevert(Escrow.EscrowReleaseWindowTooShort.selector);
        escrow.lockFunds(
            bytes32("order-release-short"),
            buyer,
            seller,
            address(token),
            10 ether,
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 2 days + 12 hours),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.expectRevert(Escrow.EscrowReleaseWindowTooLong.selector);
        escrow.lockFunds(
            bytes32("order-release-long"),
            buyer,
            seller,
            address(token),
            10 ether,
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 20 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        escrow.lockFunds(
            bytes32("order-time-ok"),
            buyer,
            seller,
            address(token),
            10 ether,
            uint64(block.timestamp + 3 days),
            uint64(block.timestamp + 9 days),
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopPrank();

        IEscrow.Deal memory deal = escrow.getDeal(bytes32("order-time-ok"));
        assertEq(uint8(deal.status), uint8(IEscrow.Status.Locked));
        assertGt(deal.createdAt, 0, "createdAt");
    }
}
