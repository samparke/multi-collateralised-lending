// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Coin} from "../src/Coin.sol";
import {Engine} from "../src/Engine.sol";
import {DeployEngine} from "../script/DeployEngine.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployEngineTest is Test {
    DeployEngine deployer;
    Engine engine;
    Coin coin;
    HelperConfig config;
    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address user = makeAddr("user");
    uint256 public constant AMOUNT_MINT = 100 ether;

    function setUp() public {
        // the deployer is the deploy engine contract
        deployer = new DeployEngine();
        // because DeployEngine returns Engine, Coin and HelperConfig from the run function
        // after the run function in DeployEngine (deployer), the appropriate (and thus addresses configurations) chain will be identified.
        (engine, coin, config) = deployer.run();
        // we can then get the address for weth and wethUsdPriceFeed the correct configurated addresses
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, AMOUNT_MINT);
    }

    function testGetCollateralTokensAreWethAndWbtc() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }
}
