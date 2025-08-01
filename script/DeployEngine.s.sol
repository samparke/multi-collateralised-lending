// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Coin} from "../src/Coin.sol";
import {Engine} from "../src/Engine.sol";

contract DeployEngine is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /**
     *
     * @return returns the deployed engine. we pass in the token and pricefeed addresses from our config (which will be determined by the chainId),
     * as well as the coin we deployed
     * @return returns the coin, which is be used in our engine contract to mint, burn etc
     * @return returns the config for testing
     */
    function run() external returns (Engine, Coin, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address weth, address wbtc, address wethUsdPriceFeed, address wbtcUsdPriceFeed, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        Coin coin = new Coin();
        Engine engine = new Engine(priceFeedAddresses, tokenAddresses, address(coin));
        coin.grantMintAndBurnRole(address(engine));
        coin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (engine, coin, config);
    }
}
