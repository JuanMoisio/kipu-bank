// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Minimal mock compatible with Chainlink AggregatorV3Interface's latestRoundData
contract MockV3Aggregator {
    uint8 public decimals;
    int256 public answer;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        answer = _initialAnswer;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 _answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, answer, 0, block.timestamp, 0);
    }

    function updateAnswer(int256 _answer) external {
        answer = _answer;
    }
}
