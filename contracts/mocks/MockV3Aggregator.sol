// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockV3Aggregator
/// @notice Lightweight Chainlink-style aggregator for testing price feeds.
contract MockV3Aggregator {
    uint8 public immutable decimals;
    int256 private _latestAnswer;
    uint256 private _updatedAt;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(uint8 decimals_, int256 initialAnswer) {
        decimals = decimals_;
        _latestAnswer = initialAnswer;
        _updatedAt = block.timestamp;
        emit AnswerUpdated(initialAnswer, 0, _updatedAt);
    }

    function updateAnswer(int256 newAnswer) external {
        _latestAnswer = newAnswer;
        _updatedAt = block.timestamp;
        emit AnswerUpdated(newAnswer, 0, _updatedAt);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 0;
        answer = _latestAnswer;
        startedAt = _updatedAt;
        updatedAt = _updatedAt;
        answeredInRound = 0;
    }

    function version() external pure returns (uint256) {
        return 4;
    }
}
