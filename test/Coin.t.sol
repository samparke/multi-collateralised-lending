// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Coin} from "../src/Coin.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CoinTest is Test {
    Coin coin;
    address user = makeAddr("user");
    uint256 amountMint = 10 ether;

    function setUp() public {
        coin = new Coin();
        coin.grantMintAndBurnRole(address(this));
    }

    // mint
    function testMintIncreasesUserBalance() public {
        console.log("this address", address(this));
        console.log("coin address", address(coin));
        console.log("coin owner", coin.owner());
        uint256 userBalanceBeforeMint = coin.balanceOf(user);
        coin.mint(user, amountMint);
        uint256 userBalanceAfterMint = coin.balanceOf(user);
        assertGt(userBalanceAfterMint, userBalanceBeforeMint);
    }

    function testMintMoreThanZeroRevert() public {
        vm.expectRevert(Coin.Coin__MustBeMoreThanZero.selector);
        coin.mint(user, 0);
    }

    function testMintWithoutRoleRevert() public {
        // this error is found within the IAccess interface, not Access Control
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        coin.mint(user, amountMint);
    }

    // burn
    function testBurnReducesBalance() public {
        coin.mint(address(this), amountMint);
        uint256 balance = coin.balanceOf(address(this));
        assertEq(balance, amountMint);

        coin.burn(1 ether);
        uint256 balanceAfterBurn = coin.balanceOf(address(this));
        assertLt(balanceAfterBurn, balance);
    }

    function testBurnMustBeMoreThanZeroRevert() public {
        vm.expectRevert(Coin.Coin__MustBeMoreThanZero.selector);
        coin.burn(0);
    }

    function testBurnWithoutRoleRevert() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        coin.burn(amountMint);
    }
}
