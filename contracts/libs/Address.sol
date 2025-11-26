// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal address utilities needed for upgradeable pattern.
library Address {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        require(success, "Address: delegate call failed");
        return returndata;
    }
}
