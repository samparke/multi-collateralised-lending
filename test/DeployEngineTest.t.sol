// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Coin} from "../src/Coin.sol";
import {Engine} from "../src/Engine.sol";
import {DeployEngine} from "../script/DeployEngine.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERCMintFail} from "../test/mocks/MockERCMintFail.sol";
import {MockFailTransfer} from "../test/mocks/MockFailTransfer.sol";
import {MockFailTransferFrom} from "./mocks/MockFailTransferFrom.sol";

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
    address[] public tokenAddresses;
    address[] public priceFeed;

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

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
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

        uint256 contractWethBalance = ERC20Mock(weth).balanceOf(address(engine));
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

    function testDepositMoreThanZeroRevert() public {
        vm.expectRevert(Engine.Engine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }

    function testDepositNotAcceptedTokenRevert() public {
        vm.startPrank(user);
        vm.expectRevert(Engine.Engine__UnacceptedToken.selector);
        engine.depositCollateral(address(0), amountCollateral);
        vm.stopPrank();
    }

    function testDepositInsufficientBalanceRevert() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), 101 ether);
        vm.expectRevert(Engine.Engine__InsufficientBalance.selector);
        engine.depositCollateral(weth, 101 ether);
        vm.stopPrank();
    }

    function testDepositAndMintCoinIncreasesUserDepositMappingAndCoinBalance() public {
        uint256 userStartingDepositAmount = engine.getCollateralAmountUserDeposited(user, weth);
        uint256 userStartingMintBalance = coin.balanceOf(user);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintCoin(weth, amountCollateral);
        vm.stopPrank();

        uint256 userDepositAmount = engine.getCollateralAmountUserDeposited(user, weth);
        uint256 userMintBalance = coin.balanceOf(user);

        assertGt(userDepositAmount, userStartingDepositAmount);
        assertGt(userMintBalance, userStartingMintBalance);
    }

    // redeem

    function testRedeemCollateralBalancenIncreasesAndMappingDecreases() public depositCollateral {
        uint256 userCollateralBalanceBeforeRedeeming = ERC20Mock(weth).balanceOf(user);
        uint256 userMappingDepositedBeforeRedeeming = engine.getCollateralAmountUserDeposited(user, weth);
        console.log("user mapping", userMappingDepositedBeforeRedeeming);
        vm.startPrank(user);
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 userCollateralBalanceAfterRedeeming = ERC20Mock(weth).balanceOf(user);
        uint256 userMappingDepositedAfterRedeeming = engine.getCollateralAmountUserDeposited(user, weth);

        assertGt(userCollateralBalanceAfterRedeeming, userCollateralBalanceBeforeRedeeming);
        assertGt(userMappingDepositedBeforeRedeeming, userMappingDepositedAfterRedeeming);
    }

    function testRedeemMoreThanDepositBalance() public depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(Engine.Engine__RedeemAmountHigherThanDeposited.selector);
        engine.redeemCollateral(weth, amountCollateral + 1);
        vm.stopPrank();
    }

    // mint

    function testMintNeedsMoreThanZeroRevert() public {
        vm.expectRevert(Engine.Engine__MustBeMoreThanZero.selector);
        engine.mintCoin(0);
    }

    function testMintFailRevert() public {
        MockERCMintFail token = new MockERCMintFail();
        priceFeed = [wethUsdPriceFeed];
        tokenAddresses = [weth];
        Engine mockEngine = new Engine(priceFeed, tokenAddresses, address(token));

        vm.startPrank(user);
        vm.expectRevert(Engine.Engine__MintFailed.selector);
        mockEngine.mintCoin(1);
        vm.stopPrank();
    }

    // burn

    function testBurnNeedsMoreThanZeroRevert() public {
        vm.expectRevert(Engine.Engine__MustBeMoreThanZero.selector);
        engine.burnCoin(0);
    }

    function testBurnFailRevert() public {
        MockFailTransferFrom token = new MockFailTransferFrom();
        priceFeed = [wethUsdPriceFeed];
        tokenAddresses = [weth];
        Engine mockEngine = new Engine(priceFeed, tokenAddresses, address(token));
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockEngine), amountCollateral);
        mockEngine.depositCollateral(weth, amountCollateral);
        mockEngine.mintCoin(1);
        vm.expectRevert(Engine.Engine__TransferFailed.selector);
        mockEngine.burnCoin(1);
        vm.stopPrank();
    }
}
