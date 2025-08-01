// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MockERCMintFail is ERC20, ERC20Burnable, Ownable, AccessControl {
    // errors
    error Coin__MustBeMoreThanZero();
    error Coin__CannotMintToZeroAddress();
    error Coin__BalanceMustBeMoreThanBurnAmount();

    // state variables

    // modifiers
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert Coin__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("Coin", "COIN") Ownable(msg.sender) {}

    function mint(address _user, uint256 _amount) external moreThanZero(_amount) returns (bool) {
        if (_user == address(0)) {
            revert Coin__CannotMintToZeroAddress();
        }
        _mint(_user, _amount);
        return false;
    }

    function burn(uint256 _amount) public override moreThanZero(_amount) {
        if (balanceOf(msg.sender) < _amount) {
            revert Coin__BalanceMustBeMoreThanBurnAmount();
        }
        super.burn(_amount);
    }
}
