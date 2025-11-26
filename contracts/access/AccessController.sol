// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "../libs/AccessControl.sol";
import {Roles} from "../libs/Roles.sol";

/// @title AccessController
/// @notice Centralized role registry for protocol governance.
contract AccessController is AccessControl {
    constructor(address admin, address manager, address treasurer, address arbiter, address pauser) {
        if (admin != address(0)) {
            initialize(admin, manager, treasurer, arbiter, pauser);
        }
        _disableInitializers();
    }

    function initialize(
        address admin,
        address manager,
        address treasurer,
        address arbiter,
        address pauser
    ) public initializer {
        require(admin != address(0), "AccessController: admin zero address");
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, admin);

        _setRoleAdmin(Roles.ROLE_MANAGER, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.ROLE_TREASURER, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.ROLE_ARBITER, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.ROLE_PAUSER, DEFAULT_ADMIN_ROLE);

        if (manager != address(0)) {
            _setupRole(Roles.ROLE_MANAGER, manager);
        }
        if (treasurer != address(0)) {
            _setupRole(Roles.ROLE_TREASURER, treasurer);
        }
        if (arbiter != address(0)) {
            _setupRole(Roles.ROLE_ARBITER, arbiter);
        }
        if (pauser != address(0)) {
            _setupRole(Roles.ROLE_PAUSER, pauser);
        }
    }
}
