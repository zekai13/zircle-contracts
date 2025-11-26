// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    function onPlatformFeeReceived(uint256 amountZir) external;
    function assessLiquidityAndAdjustFee(uint256 annualOutflow, uint256 targetFeeRate) external;
    function withdrawForModule(address to, uint256 amount) external;
}
