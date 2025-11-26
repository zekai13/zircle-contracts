// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "./Initializable.sol";
import {Context} from "./Context.sol";

/// @notice Upgradeable EIP712 helper storing hashed domain parameters.
abstract contract EIP712 is Initializable, Context {
    bytes32 private _hashedName;
    bytes32 private _hashedVersion;
    bytes32 private _typeHash;
    uint256[50] private __gap;

    constructor(string memory name, string memory version) {
        if (bytes(name).length != 0 || bytes(version).length != 0) {
            _initEIP712(name, version);
        }
    }

    function __EIP712_init(string memory name, string memory version) internal onlyInitializing {
        __Context_init();
        __EIP712_init_unchained(name, version);
    }

    function __EIP712_init_unchained(string memory name, string memory version) internal onlyInitializing {
        _initEIP712(name, version);
    }

    function _initEIP712(string memory name, string memory version) private {
        require(_typeHash == bytes32(0), "EIP712: already initialized");
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));
        _typeHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(abi.encode(_typeHash, _hashedName, _hashedVersion, block.chainid, address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }
}
