// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVesting {
    function claim(address account) external returns (uint256);
}
