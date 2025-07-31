// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Coin is ERC20, ERC20Burnable, Ownable, AccessControl {
    // errors
    error Coin__MustBeMoreThanZero();
    error Coin__CannotBeZeroAddress();

    // state variables
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // modifiers
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert Coin__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("Coin", "COIN") Ownable(msg.sender) {
        grantMintAndBurnRole(msg.sender);
    }

    function grantMintAndBurnRole(address _user) public onlyOwner {
        grantRole(MINT_AND_BURN_ROLE, _user);
    }

    function mint(address _user, uint256 _amount)
        external
        moreThanZero(_amount)
        onlyRole(MINT_AND_BURN_ROLE)
        returns (bool)
    {
        if (_user == address(0)) {
            revert Coin__CannotBeZeroAddress();
        }
        _mint(_user, _amount);
        return true;
    }
}
