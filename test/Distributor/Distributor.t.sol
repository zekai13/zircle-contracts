// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {FeatureFlags} from "../../contracts/core/FeatureFlags.sol";
import {ZIR} from "../../contracts/core/ZIR.sol";
import {ZIRDistributor} from "../../contracts/support/Distributor.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {FeatureFlagKeys} from "../../contracts/libs/FeatureFlagKeys.sol";
import {TestBase} from "../utils/TestBase.sol";

contract DistributorTest is TestBase {
    uint256 private constant ONE_ZIR = 1_000_000;
    uint256 private constant SIGNER_PK = 0xA11CE;
    uint256 private constant USER_PK = 0xB0B;

    AccessController private controller;
    FeatureFlags private flags;
    ZIR private zir;
    ZIRDistributor private distributor;
    address private signer;
    address private user;

    function setUp() public {
        signer = vm.addr(SIGNER_PK);
        user = vm.addr(USER_PK);

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

        address zirProxy = deployProxy(
            address(new ZIR(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                ZIR.initialize.selector,
                controllerProxy,
                flagsProxy,
                address(this)
            )
        );
        zir = ZIR(zirProxy);
        flags.setFlag(FeatureFlagKeys.ZIR_TOKEN, true);

        address distributorProxy = deployProxy(
            address(new ZIRDistributor(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                ZIRDistributor.initialize.selector,
                controllerProxy,
                flagsProxy,
                zirProxy,
                signer
            )
        );
        distributor = ZIRDistributor(distributorProxy);
        flags.setFlag(FeatureFlagKeys.DISTRIBUTOR, true);

        bool seeded = zir.transfer(address(distributor), 1_000 * ONE_ZIR);
        assertTrue(seeded, "DIS-setup: funding distributor failed");
    }

    function test_DIS_01_ValidClaim() public {
        vm.warp(100);
        uint256 amount = 100 * ONE_ZIR;
        uint256 expiry = block.timestamp + 1 days;
        bytes memory sig = _signClaim(user, amount, 0, expiry);

        vm.prank(user);
        distributor.claim(amount, expiry, sig);

        assertEq(zir.balanceOf(user), amount, "DIS-01: claim amount incorrect");
    }

    function test_DIS_02_InvalidAndReplayClaims() public {
        vm.warp(100);
        uint256 amount = 50 * ONE_ZIR;
        uint256 expiry = block.timestamp - 10; // already expired
        bytes memory sigExpired = _signClaim(user, amount, 0, expiry);

        vm.prank(user);
        vm.expectRevert("Distributor: expired");
        distributor.claim(amount, expiry, sigExpired);

        expiry = block.timestamp + 1 days;
        bytes memory sig = _signClaim(user, amount, 0, expiry);

        vm.prank(user);
        distributor.claim(amount, expiry, sig);

        vm.prank(user);
        (bool reuseOk, bytes memory reuseData) = address(distributor).call(
            abi.encodeCall(distributor.claim, (amount, expiry, sig))
        );
        assertFalse(reuseOk, "DIS-02: replay should fail");
        bytes memory expectedReuse = abi.encodeWithSignature("Error(string)", "Distributor: digest used");
        assertEq(reuseData, expectedReuse, "DIS-02: replay revert mismatch");
    }

    function _signClaim(address account, uint256 amount, uint256 nonce, uint256 expiry) internal returns (bytes memory) {
        bytes32 typeHash = keccak256("Claim(address account,uint256 amount,uint256 nonce,uint256 expiry)");
        bytes32 structHash = keccak256(abi.encode(typeHash, account, amount, nonce, expiry));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZIRDistributor")),
                keccak256(bytes("1")),
                block.chainid,
                address(distributor)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }
}
