// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStaking {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimReward() external;
}
