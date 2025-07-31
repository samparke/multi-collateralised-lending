// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Coin} from "../src/Coin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Engine {
    // errors
    error Engine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();

    // state variables
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amountDeposited)) private s_collateralDeposited;
    mapping(address user => uint256) private s_coinMinted;
    address[] private collateralTokens;
    Coin private immutable i_coin;

    /**
     *
     * @param _priceFeedAddresses the chainlink price address for the token. For example, ETH/USD for WETH
     * @param _tokenAddresses the token address for the wrapped token. For example, WETH/USD on sepolia is 0x694AA1769357215DE4FAC081bf1f309aDC325306
     * @param _coin our ERC20 stablecoin users are receiving
     * @dev we want to ensure price feeds and token address are configured properly (i.e. the correct price feed is mapped with the correct token address).
     * to do this, when we initialise the contract, we must ensure the token address and price feed addresses being entered are the same length,
     * meaning each price feed address is aligned with the correct token address (1:1). If they were different legnths, its likely they've been entered incorrectly
     */
    constructor(address[] memory _priceFeedAddresses, address[] memory _tokenAddresses, address _coin) {
        if (_priceFeedAddresses.length != _tokenAddresses.length) {
            revert Engine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        // here we input the token and price feed address with the same index (given we've already checked the lengths are the same) into the price feed mapping
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            // we then push the tokenAddress into the collateralToken array too
            collateralTokens.push(_tokenAddresses[i]);
        }
        i_coin = Coin(_coin);
    }

    // getter functions

    /**
     * @notice fetches the collateral tokens accepted in this protocol. For example, WETH
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return collateralTokens;
    }

    /**
     * @notice fetches the collateral amount the user deposited. For example, user 1 might have deposited 1 WETH and user 2 might have deposited 5 WETH
     * @param _user the user we want to see the collateral deposited amount for
     * @param _token the specific token we want to see how much they deposited
     */
    function getCollateralAmountUserDeposited(address _user, address _token) external view returns (uint256) {
        return s_collateralDeposited[_user][_token];
    }

    /**
     * @notice fetches the coin amount minted for a specific user
     * @param _user the user we want to see how much coin has been minted for
     */
    function getUserCoinMinted(address _user) external view returns (uint256) {
        return s_coinMinted[_user];
    }
}
