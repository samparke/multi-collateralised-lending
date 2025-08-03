// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePriceFeed();

    uint256 private constant TIMEOUT = 3 hours;

    /**
     * @notice checks the last time the oracle output was given. If the time has been over 3 hours since updatedAt,
     * it is stale and should not be used in our protocol
     * @param _priceFeed the address of the price feed we are checking, such as weth
     */
    function staleCheckLatestRoundData(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            _priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePriceFeed();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
