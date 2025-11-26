// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDistributor {
    function claim(uint256 amount, uint256 expiry, bytes calldata signature) external;
}
