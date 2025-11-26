// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Address} from "./Address.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {IERC1822Proxiable} from "../interfaces/external/IERC1822Proxiable.sol";

/// @notice Minimal ERC1967 upgrade utilities extracted from OpenZeppelin.
abstract contract ERC1967Upgrade {
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    // keccak256("eip1967.proxy.rollback") - 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    event Upgraded(address indexed implementation);

    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        }
    }

    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data, bool forceCall) internal {
        if (StorageSlot.getBooleanSlot(_ROLLBACK_SLOT).value) {
            _setImplementation(newImplementation);
        } else {
            try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
                require(slot == _IMPLEMENTATION_SLOT, "ERC1967: unsupported proxiableUUID");
            } catch {
                revert("ERC1967: new implementation is not UUPS");
            }
            _upgradeTo(newImplementation);
            if (data.length > 0 || forceCall) {
                Address.functionDelegateCall(newImplementation, data);
            }
        }
    }
}
