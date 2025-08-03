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
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

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
        ERC20Mock(weth).mint(user, amountCollateral);
    }

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    // constructor tests

    function testEngineIsInitialisedWithDifferentLengthTokenAndPriceFeeds() public {
        priceFeed = [wethUsdPriceFeed];
        tokenAddresses = [weth, wbtc];
        Coin token = new Coin();
        vm.expectRevert(Engine.Engine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new Engine(priceFeed, tokenAddresses, address(token));
    }

    // getter tests

    function testGetCollateralTokensAreWethAndWbtc() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    function testGetLiquidationPrecision() public view {
        assertEq(engine.getLiquidationPrecision(), 100);
    }

    function testGetLiquidationBonus() public view {
        assertEq(engine.getLiquidationBonus(), 10);
    }

    function testGetLiquidationThreshold() public view {
        assertEq(engine.getLiquidationThreshold(), 50);
    }

    function testGetMinimumHealthFactor() public view {
        assertEq(engine.getMinimumHealthFactor(), 1e18);
    }

    function testGetPrecision() public view {
        assertEq(engine.getPrecision(), 1e18);
    }

    function testGetAdditionalPriceFeedPrecision() public view {
        assertEq(engine.getAdditionalPriceFeedPrecision(), 1e10);
    }

    function testGetUserCoinHasMinted() public depositCollateral {
        vm.prank(user);
        engine.mintCoin(amountCollateral);

        assertEq(engine.getCoinUserHasMinted(user), amountCollateral);
    }

    function testGetAccountInformation() public depositCollateral {
        vm.prank(user);
        engine.mintCoin(1 ether);
        (uint256 totalCoinMinted, uint256 collateralValue) = engine.getAccountInformation(user);

        uint256 expectedAmountMinted = 1 ether;
        uint256 expectedCollateralValue = 2000 * 10 ether;
        assertEq(totalCoinMinted, expectedAmountMinted);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetTokenValueInUsd() public view {
        uint256 expectedTokenValueInUsd = 2000e18;
        assertEq(engine.getTokenValueInUsd(weth, 1 ether), expectedTokenValueInUsd);
    }

    function testGetAccountCollateralValueInUsd() public depositCollateral {
        uint256 expectedAccountValueInUsd = 2000e18 * 10;
        assertEq(engine.getAccountCollateralValueInUsd(user), expectedAccountValueInUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedTokenAmount = 1e18;
        assertEq(engine.getTokenAmountFromUsd(weth, 2000e18), expectedTokenAmount);
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

    function testDepositCollateralTransferFromFail() public {
        // because this test is trying to fail the transfer function in the deposit collateral function,
        // we are trying to make the weth transfer fail
        // therefore, the weth is the mock fail token in this instance
        MockFailTransferFrom mockCollateral = new MockFailTransferFrom();
        mockCollateral.mint(user, amountCollateral);
        priceFeed = [wethUsdPriceFeed];
        tokenAddresses = [address(mockCollateral)];
        Engine mockEngine = new Engine(priceFeed, tokenAddresses, address(coin));

        vm.startPrank(user);
        ERC20Mock(address(mockCollateral)).approve(address(mockEngine), amountCollateral);
        vm.expectRevert(Engine.Engine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockCollateral), amountCollateral);
        vm.stopPrank();
    }

    // redeem

    function testRedeemCollateralBalancenIncreasesAndMappingDecreases() public depositCollateral {
        uint256 userCollateralBalanceBeforeRedeeming = ERC20Mock(weth).balanceOf(user);
        uint256 userMappingDepositedBeforeRedeeming = engine.getCollateralAmountUserDeposited(user, weth);
        console.log("user mapping", userMappingDepositedBeforeRedeeming);
        vm.startPrank(user);
        engine.redeemCollateral(weth, amountCollateral);
        console.log("user health factor", engine.getUserHealthFactor(user));
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

    function testRedeemFail() public {
        MockFailTransfer token = new MockFailTransfer();
        priceFeed = [wethUsdPriceFeed];
        tokenAddresses = [address(token)];
        Engine mockEngine = new Engine(priceFeed, tokenAddresses, address(token));
        token.mint(user, amountCollateral);
        vm.startPrank(user);
        ERC20Mock(address(token)).approve(address(mockEngine), amountCollateral);
        mockEngine.depositCollateral(address(token), amountCollateral);
        vm.expectRevert(Engine.Engine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(token), 1 ether);
        console.log("user balance after redeeming", ERC20Mock(weth).balanceOf(user));
        vm.stopPrank();
    }

    function testRedeemCollateralForCoinIncreasesUsersCollateralBalanceAndDecreasesCoinBalance()
        public
        depositCollateral
    {
        uint256 userCollateralBalanceBeforeRedeeming = ERC20Mock(weth).balanceOf(user);
        uint256 userMappingDepositedBeforeRedeeming = engine.getCollateralAmountUserDeposited(user, weth);
        vm.startPrank(user);
        console.log("user health factor", engine.getUserHealthFactor(user));
        engine.mintCoin(amountCollateral);
        console.log("user health factor", engine.getUserHealthFactor(user));
        uint256 userCoinBalanceBeforeRedeeming = coin.balanceOf(user);

        // note: this commented-out function with revert because the user does not burn the coin they minted - breaking the health factor
        // engine.redeemCollateral(weth, amountCollateral);

        IERC20(coin).approve(address(engine), amountCollateral);
        engine.redeemCollateralForCoin(weth, (amountCollateral / 2), (amountCollateral / 2));

        vm.stopPrank();
        uint256 userCollateralBalanceAfterRedeeming = ERC20Mock(weth).balanceOf(user);
        uint256 userMappingDepositedAfterRedeeming = engine.getCollateralAmountUserDeposited(user, weth);
        uint256 userCoinBalanceAfterRedeeming = coin.balanceOf(user);

        assertGt(userCollateralBalanceAfterRedeeming, userCollateralBalanceBeforeRedeeming);
        assertGt(userMappingDepositedBeforeRedeeming, userMappingDepositedAfterRedeeming);
        assertGt(userCoinBalanceBeforeRedeeming, userCoinBalanceAfterRedeeming);
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

    // health factor tests

    function testUserHealthFactorCanBeBroken() public depositCollateral {
        vm.startPrank(user);
        engine.mintCoin(AMOUNT_MINT);

        // drops down to $5
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(5e8);
        assertLt(engine.getUserHealthFactor(user), 1 ether);

        vm.expectPartialRevert(Engine.Engine__BrokenHealthFactor.selector);
        engine.mintCoin(1 ether);
        vm.stopPrank();
    }

    function testHealthFactorIsWorkingProperly() public depositCollateral {
        vm.startPrank(user);
        engine.mintCoin(amountCollateral);
        vm.stopPrank();

        // we deposited 10 ether priced at 2000
        // collateralAdjustedForThreshold = ((20,000 * 50) / 100) = 10,000
        // just see the 50 and 100 calculation as dividing 20,000 by half, because 200% collateralisation - meaning we need double
        // the calculation above, for simplicity sake, was done in normal decimals. This is purely for us to understand

        // here (10,000e18), we use ether decimals so the calculation is correct
        // the calculation: ((collateralAdjusted * PRECISION) / totalCoinMinted);
        // (10,000e18 * 1e18) / totalDscMinted (10e18)
        // this is equivalent to: 10,000e18 / 10e18 (10,000 / 10) = 1,000
        // then, 1,000 * 1e18 to scale it to ether decimals
        uint256 userHealthFactor = engine._healthFactor(user);
        assertEq(engine.getUserHealthFactor(user), 1000 ether);
        assertEq(engine.getUserHealthFactor(user), userHealthFactor);
    }

    // liquidation tests
    function testCannotLiquidateGoodHealthFactor() public depositCollateral {
        ERC20Mock(weth).mint(liquidatior, 100 ether);
        vm.startPrank(user);
        engine.mintCoin(amountCollateral);
        vm.stopPrank();
        vm.prank(liquidatior);
        vm.expectRevert(Engine.Engine__HealthFactorIsOk.selector);
        engine.liquidate(user, weth, 1 ether);
    }
}
