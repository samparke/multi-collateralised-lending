// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Coin is ERC20, ERC20Burnable, Ownable, AccessControl {
    // errors
    error Coin__MustBeMoreThanZero();
    error Coin__CannotMintToZeroAddress();
    error Coin__BalanceMustBeMoreThanBurnAmount();

    // state variables
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // modifiers
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert Coin__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("Coin", "COIN") Ownable(msg.sender) {}

    /**
     * @notice grants access to accounts to mint and burn Coin
     * @param _user the user we are granting the mint and burn role, this will be the engine/vault
     */
    function grantMintAndBurnRole(address _user) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _user);
    }

    /**
     * @notice mints Coin after collateral is deposited
     * @param _user the user we are minting Coin to
     * @param _amount the amount of Coin we are minting
     */
    function mint(address _user, uint256 _amount)
        external
        moreThanZero(_amount)
        onlyRole(MINT_AND_BURN_ROLE)
        returns (bool)
    {
        if (_user == address(0)) {
            revert Coin__CannotMintToZeroAddress();
        }
        _mint(_user, _amount);
        return true;
    }

    /**
     * @notice burns Coin
     * @param _amount the amount of Coin we are burning
     */
    function burn(uint256 _amount) public override moreThanZero(_amount) onlyRole(MINT_AND_BURN_ROLE) {
        if (balanceOf(msg.sender) < _amount) {
            revert Coin__BalanceMustBeMoreThanBurnAmount();
        }
        super.burn(_amount);
    }
}
