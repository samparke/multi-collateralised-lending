// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address weth;
        address wbtc;
        address wethUsdPriceFeedAddress;
        address wbtcUsdPriceFeedAddress;
        uint256 deployerKey;
    }

    uint256 ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    // actual chainlink returns values in 8 decimal precision, so we must have the same for the mocks
    uint256 public constant DECIMALS = 8;
    // $2000 in 8 decimal precision (see getAnvilConfig below)
    uint256 ETH_USD_PRICE = 2000e8;
    uint256 BTC_USD_PRICE = 1000e8;
    NetworkConfig public activeNetworkConfig;

    // sepolia chain id is 11155111 (this will be the block.chainid automatically identified when we deploy to sepolia)
    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    /**
     * @notice if we deploy on the sepolia chain (identified by the chainid being 11155111), we use these configurations
     * note: as this is only practice, and not real production, the private key is said to be within my env file
     */
    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return (
            NetworkConfig({
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                wethUsdPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcUsdPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                deployerKey: vm.envUint("PRIVATE_KEY")
            })
        );
    }

    /**
     * @notice this is the configuration if we deploy to anvil (primary usage in testing)
     * we must create mocks as weth and wbtc do not exist in this test chain environment
     * the ERC20Mock has functions such as mint, burn etc - allowing us to mint collateral for our user to deposit
     * the MockV3Aggregator has prices passed into it, and will mimick the AggregatorV3Interface,
     * but instead of returning actual prices, will just return these values when we call getLatestRoundData etc
     *
     * as we are deploying these mock contracts, we must vm.startBroadcast etc - just like we'd do when deploying any other real contract
     * finally, we return this configuration so it can be set as our activeNetworkConfig in the constructor
     */
    function getAnvilConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 100e8);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 100e8);
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        vm.stopBroadcast();
        return (
            NetworkConfig({
                weth: wethMock,
                wbtc: wbtcMock,
                wethUsdPriceFeedAddress: wethUsdPriceFeed,
                wbtcUsdPriceFeedAddress: wbtcUsdPriceFeed,
                deployerKey: ANVIL_KEY
            })
        );
    }
}
