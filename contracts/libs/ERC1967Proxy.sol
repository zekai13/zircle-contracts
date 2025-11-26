// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Upgrade} from "./ERC1967Upgrade.sol";
import {Address} from "./Address.sol";

/// @notice Minimal ERC1967 proxy compatible with UUPS implementations.
contract ERC1967Proxy is ERC1967Upgrade {
    constructor(address logic, bytes memory data) payable {
        require(logic != address(0), "Proxy: logic zero");
        _upgradeTo(logic);
        if (data.length > 0) {
            Address.functionDelegateCall(logic, data);
        }
    }

    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable virtual {
        _fallback();
    }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function _fallback() internal virtual {
        _delegate(_getImplementation());
    }

    function _delegate(address implementation_) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
