// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Chainlink aggregator mock for oracle unit tests
contract MockAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;

    constructor(int256 initialAnswer) {
        answer = initialAnswer;
        updatedAt = block.timestamp;
        roundId = 1;
    }

    function setRound(int256 newAnswer, uint256 newUpdatedAt) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
        roundId += 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint80 currentRound = roundId;
        return (currentRound, answer, updatedAt, updatedAt, currentRound);
    }
}
