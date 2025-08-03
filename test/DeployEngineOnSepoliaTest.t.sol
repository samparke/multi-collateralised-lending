// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Coin} from "../src/Coin.sol";
import {Engine} from "../src/Engine.sol";
import {DeployEngine} from "../script/DeployEngine.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    address liquidatior = makeAddr("liquidatior");
    uint256 public AMOUNT_MINT = 100 ether;
    uint256 public amountCollateral = 10 ether;
    address[] public tokenAddresses;
    address[] public priceFeed;
    uint256 sepoliaFork;

    function setUp() public {
        sepoliaFork = vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        deployer = new DeployEngine();
        (engine, coin, config) = deployer.run();
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, amountCollateral);
    }

    function testActiveSepoliaFork() public view {
        assertEq(vm.activeFork(), sepoliaFork);
    }

    function testTokenAndPriceFeedAddressesAreTheSepoliAddresses() public view {
        assertEq(weth, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
        assertEq(wbtc, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        assertEq(wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
    }
}
