// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

/// @notice Lightweight SafeERC20 helpers ensuring return value checks.
library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value), "SafeERC20: transfer failed");
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value),
            "SafeERC20: transferFrom failed"
        );
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value), "SafeERC20: approve failed");
    }

    function _callOptionalReturn(IERC20 token, bytes memory data, string memory error) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, error);
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), error);
        }
    }
}
