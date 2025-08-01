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
    uint256 public constant AMOUNT_MINT = 100 ether;
    uint256 public amountCollateral = 10 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

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

    // getter tests

    function testGetCollateralTokensAreWethAndWbtc() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    // deposit

    function testDepositWethAndUserMappingIncreases(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        ERC20Mock(weth).mint(user, amount);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();

        uint256 amountUserDeposited = engine.getCollateralAmountUserDeposited(user, weth);
        assertEq(amountUserDeposited, amount);
    }

    function testDepositAndContractBalanceIncreases(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        ERC20Mock(weth).mint(user, amount);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();

        uint256 contractWethBalance = ERC20Mock(weth).balanceOf(address(this));
        assertEq(contractWethBalance, amount);
    }

    function testDepositAndDepositEventFires(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        ERC20Mock(weth).mint(user, amount);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amount);
        vm.expectEmit(true, true, false, true);
        emit CollateralDeposited(address(user), address(weth), amount);
        engine.depositCollateral(weth, amount);
        vm.stopPrank();
    }
}
