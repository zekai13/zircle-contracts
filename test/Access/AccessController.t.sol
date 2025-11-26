// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessController} from "../../contracts/access/AccessController.sol";
import {Roles} from "../../contracts/libs/Roles.sol";
import {TestBase} from "../utils/TestBase.sol";

contract UnauthorizedCaller {
    function attemptGrant(address target, bytes32 role, address account) external returns (bool success) {
        (success, ) = target.call(abi.encodeWithSignature("grantRole(bytes32,address)", role, account));
    }
}

contract AccessControllerTest is TestBase {
    AccessController private controller;
    address private constant MANAGER = address(0xBEEF);

    function setUp() public {
        address controllerProxy = deployProxy(
            address(new AccessController(address(0), address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                AccessController.initialize.selector,
                address(this),
                address(0),
                address(0),
                address(0),
                address(0)
            )
        );
        controller = AccessController(controllerProxy);
    }

    function test_ALL_01_RoleAuthorization() public {
        controller.grantRole(Roles.ROLE_MANAGER, MANAGER);
        assertTrue(controller.hasRole(Roles.ROLE_MANAGER, MANAGER), "ALL-01: manager role not granted");

        UnauthorizedCaller caller = new UnauthorizedCaller();
        bool success = caller.attemptGrant(address(controller), Roles.ROLE_TREASURER, address(0xCAFE));
        assertFalse(success, "ALL-01: unauthorized caller should not grant roles");
    }
}
