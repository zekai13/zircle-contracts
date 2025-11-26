// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";

/// @dev Basic reentrancy guard similar to OpenZeppelin's upgradeable implementation.
abstract contract ReentrancyGuard is Initializable {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;
    uint256[49] private __gap;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}
