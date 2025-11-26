// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReputation {
    function recordTrade(address account) external returns (int256);
    function recordArbitrationWin(address account) external returns (int256);
    function recordArbitrationLoss(address account) external returns (int256);
    function adjustReputation(address account, int256 delta) external returns (int256);
    function getReputation(address account) external view returns (int256 score, bool underPenalty);
    function canReceiveBonus(address account) external view returns (bool);
}
