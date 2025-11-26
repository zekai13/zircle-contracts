// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";

/// @dev Simplified Initializable context similar to OpenZeppelin's ContextUpgradeable.
abstract contract Context is Initializable {
    function __Context_init() internal onlyInitializing {}

    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
