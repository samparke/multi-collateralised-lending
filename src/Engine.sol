// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Coin} from "../src/Coin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Engine {
    // errors
    error Engine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error Engine__TransferFailed();
    error Engine__MustBeMoreThanZero();
    error Engine__UnacceptedToken();
    error Engine__RedeemAmountHigherThanDeposited();
    error Engine__InsufficientBalance();

    // state variables
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amountDeposited)) private s_collateralDeposited;
    mapping(address user => uint256) private s_coinMinted;
    address[] private s_collateralTokens;
    Coin private immutable i_coin;

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert Engine__MustBeMoreThanZero();
        }
        _;
    }

    /**
     * @notice this modifier is used when a user deposits collateral. It checks whether the token they are depositing is accepted in our protocol
     * @param _token this is the token they are depositing
     * @dev if the _token they are depositing is address(0) (0x000000...), it means we have not assigned it a token address
     * remember, we assigned weth the address 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 and wbtc 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063 (sepolia)
     * therefore, if the token they are depositing does not have any of these addresses, we have not initalised it, meaning it will be address(0)
     */
    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert Engine__UnacceptedToken();
        }
        _;
    }

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
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_coin = Coin(_coin);
    }

    // core functions

    /**
     * @notice this function allows the user to deposit collateral. This will increase their health factor and allow them to mint COIN (if they wish)
     * @param _collateralTokenToDeposit this is the collateral token the user is depositing. For example, weth or wbtc.
     * @param _amount the amount of collateral they are depositing. For example, 1 weth.
     */
    function depositCollateral(address _collateralTokenToDeposit, uint256 _amount)
        public
        moreThanZero(_amount)
        isAllowedToken(_collateralTokenToDeposit)
    {
        if (IERC20(_collateralTokenToDeposit).balanceOf(msg.sender) < _amount) {
            revert Engine__InsufficientBalance();
        }
        s_collateralDeposited[msg.sender][_collateralTokenToDeposit] += _amount;
        bool success = IERC20(_collateralTokenToDeposit).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }
    }

    function depositCollateralAndMintCoin(address _collateralTokenToDeposit, uint256 _amount) external {
        if (IERC20(_collateralTokenToDeposit).balanceOf(msg.sender) < _amount) {
            revert Engine__InsufficientBalance();
        }
        s_collateralDeposited[msg.sender][_collateralTokenToDeposit] += _amount;
        depositCollateral(_collateralTokenToDeposit, _amount);
        // mint coin
    }

    function redeemCollateral(address _collateralTokenToRedeem, uint256 _amount) external {
        if (s_collateralDeposited[msg.sender][_collateralTokenToRedeem] < _amount) {
            revert Engine__RedeemAmountHigherThanDeposited();
        }
        s_collateralDeposited[msg.sender][_collateralTokenToRedeem] -= _amount;
        IERC20(_collateralTokenToRedeem).transfer(msg.sender, _amount);
    }

    function mintCoin(uint256 _amount) external moreThanZero(_amount) {
        s_coinMinted[msg.sender] += _amount;
    }

    /**
     * @notice this is a function for users to burn coin, with the goal to improve their collateralisation and health factor
     * because there are different situations where users burn coin (regular users improving their own health factor,
     * but also liquidators burning coin on behalf of another, we create an internal _burnCoin)
     * @param _amount the amount of coin we are burning
     */
    function burnCoin(uint256 _amount) external moreThanZero(_amount) {
        _burnCoin(msg.sender, msg.sender, _amount);
    }

    /**
     *
     * @param _onBehalfOf this is the users who's coin minted is getting reduced and health factor is being improved
     * in the "burnCoin" function, which is called by typical users wanting to improve their health factor, this will be
     * the msg.sender. However, in the liquidate function, where liquidators are burning coin on behalf of another user,
     * this will be the users address
     * @param coinFrom The actual address we are burning coin from. In the regular "burnDsc" function, this will be the msg.sender,
     * but in the liquidate function, this will be the liquidator. Remember, the liquidator takes the users collateral,
     * and burns coin in replacement to ensure proper protocol token backing
     * @param _amount the amount of coin we are burning
     */
    function _burnCoin(address _onBehalfOf, address coinFrom, uint256 _amount) internal {
        s_coinMinted[_onBehalfOf] -= _amount;
        bool success = i_coin.transferFrom(coinFrom, address(this), _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }
        i_coin.burn(_amount);
    }

    // getter functions

    /**
     * @notice fetches the collateral tokens accepted in this protocol. For example, WETH
     * @return an array of the collateral tokens
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
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
