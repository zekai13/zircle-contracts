// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

/// @notice Minimal safe transfer helpers covering non-compliant tokens.
library SafeTransferLib {
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, amount), "SafeTransfer: transferFrom failed");
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, amount), "SafeTransfer: transfer failed");
    }

    function _callOptionalReturn(IERC20 token, bytes memory data, string memory error) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, error);
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), error);
        }
    }
}
