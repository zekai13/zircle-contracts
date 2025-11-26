// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IZIR {
    function burnFromTreasury(uint256 amount) external;
    function setFeeRate(uint16 bps) external;
    function setRatios(uint16 burnRatioPct, uint16 rewardRatioPct) external;
    function feeRateBps() external view returns (uint16);
}
