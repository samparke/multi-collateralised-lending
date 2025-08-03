// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Coin} from "../src/Coin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Engine {
    // errors
    error Engine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error Engine__TransferFailed();
    error Engine__MustBeMoreThanZero();
    error Engine__UnacceptedToken();
    error Engine__RedeemAmountHigherThanDeposited();
    error Engine__InsufficientBalance();
    error Engine__BrokenHealthFactor(uint256 healthFactor);
    error Engine__MintFailed();
    error Engine__HealthFactorIsOk();
    error Engine__HealthFactorNotImproved();

    // events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    // state variables
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amountDeposited)) private s_collateralDeposited;
    mapping(address user => uint256) private s_coinMinted;
    address[] private s_collateralTokens;
    Coin private immutable i_coin;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    // 50 (50%) is 200% collateralisation. when calculating the users current collateralisation, we multiply by 0.5 - leaving us with half of our collateral
    // therefore, we need double collateral to meet the standard (0.5 * 2 = 1)
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;

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

    // --------------------------------------------------------------------------------------------------------
    // DEPOSIT COLLATERAL
    // --------------------------------------------------------------------------------------------------------

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
        emit CollateralDeposited(msg.sender, _collateralTokenToDeposit, _amount);
        bool success = IERC20(_collateralTokenToDeposit).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }
    }

    /**
     * @notice this function allows the user to deposit collateral and mint in one transactiom
     * @param _collateralTokenToDeposit the specific token to deposit
     * @param _amount the amount to deposit, and thus to mint
     */
    function depositCollateralAndMintCoin(address _collateralTokenToDeposit, uint256 _amount) public {
        depositCollateral(_collateralTokenToDeposit, _amount);
        mintCoin(_amount);
    }

    /**
     * @notice this function trades in coin to allow the user to redeem their collateral
     * @param _tokenCollateralAddress the token we are redeeming
     * @param _amount the amount the redeem
     * @param burnAmount the amount we burn, to allow us to redeem the collateral. Before redeeming collateral, we must burn the COIN
     * this is what gives the protocol stability
     */
    function redeemCollateralForCoin(address _tokenCollateralAddress, uint256 _amount, uint256 burnAmount) public {
        burnCoin(burnAmount);
        redeemCollateral(_tokenCollateralAddress, _amount);
    }

    /**
     * @notice this is the redeem function for users to redeem the collateral deposited. This will be the function
     * called by general users and not liquidators
     * @param _collateralTokenToRedeem the specific token the user wants to redeem (such as wbtc, if they deposited wbtc)
     * @param _amount the amount to redeem
     */
    function redeemCollateral(address _collateralTokenToRedeem, uint256 _amount) public {
        // because the user is the one calling this, the _redeemCollateral '_from' will be the msg.sender, as well as the 'to'
        // we use the _from when reducing the mapping for deposited from the user, and _to when transfering the collateral
        // this contrasts when liquidating, where the from is the user we are liquiding (reducing their deposited amount and improving their health factor)
        // and to is the liquidator, who we transfer collateral to
        _redeemCollateral(_collateralTokenToRedeem, _amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice the internal function to transfer collateral to caller. This is the function called directly by liquidator
     * @param _collateralTokenToRedeem the specific token the user wants to redeem (such as wbtc, if they deposited wbtc)
     * @param _amount the amount to redeem
     */
    function _redeemCollateral(address _collateralTokenToRedeem, uint256 _amount, address _from, address _to)
        internal
    {
        if (s_collateralDeposited[_from][_collateralTokenToRedeem] < _amount) {
            revert Engine__RedeemAmountHigherThanDeposited();
        }
        s_collateralDeposited[_from][_collateralTokenToRedeem] -= _amount;
        emit CollateralRedeemed(_from, _to, _collateralTokenToRedeem, _amount);
        bool success = IERC20(_collateralTokenToRedeem).transfer(_to, _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }
    }

    /**
     * @notice mints user coin
     * @param _amount the amount of coin we are wanting to mint
     */
    function mintCoin(uint256 _amount) public moreThanZero(_amount) {
        // before allowing the user to mint, we must check their their health factor
        // if their health factor is below 1 (1e18), we do not allow them to mint
        _revertIfHealthFactorIsBroken(msg.sender);
        s_coinMinted[msg.sender] += _amount;
        bool success = i_coin.mint(msg.sender, _amount);
        if (!success) {
            revert Engine__MintFailed();
        }
    }

    /**
     * @notice this is a function for users to burn coin, with the goal to improve their collateralisation and health factor
     * because there are different situations where users burn coin (regular users improving their own health factor,
     * but also liquidators burning coin on behalf of another, we create an internal _burnCoin)
     * @param _amount the amount of coin we are burning
     */
    function burnCoin(uint256 _amount) public moreThanZero(_amount) {
        _burnCoin(msg.sender, msg.sender, _amount);
        // in theory, as burning would improve the users health factor, this function should never be called
        _revertIfHealthFactorIsBroken(msg.sender);
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

    // --------------------------------------------------------------------------------------------------------
    // HEALTH FACTOR
    // --------------------------------------------------------------------------------------------------------

    /**
     * @notice this function will revert any other function if the users health factor is broken.
     * For example, before minting we will see if the users health factor is good. If not, we revert using this function
     * @param _user the user we are assessing whether the health factor of
     */
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        // from our _calculateHealthFactor function, we will receive a value either above or below 1e18
        // above 1e18 is good, below is bad
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert Engine__BrokenHealthFactor(userHealthFactor);
        }
    }

    function _healthFactor(address _user) public view returns (uint256) {
        (uint256 totalCoinMinted, uint256 accountCollateralValue) = getAccountInformation(_user);
        return _calculateHealthFactor(totalCoinMinted, accountCollateralValue);
    }

    /**
     * @notice this function calculates the users health factor
     * @param totalCoinMinted this is the amount of Coin the user has minted
     * @param accountCollateralValue this is users account collateral value
     */
    function _calculateHealthFactor(uint256 totalCoinMinted, uint256 accountCollateralValue)
        internal
        pure
        returns (uint256)
    {
        // if the user has not minted anything, their health factor is great
        if (totalCoinMinted == 0) {
            return type(uint256).max;
        }

        // lets say a users wants to mint $50 worth of COIN. They would need it their collateral to be $100 to meet the collateralisation benchmark
        // therefore, collateralAdjusted = 100 * 50 (5000) / 100 = 50. They can mint $50 worth of COIN
        uint256 collateralAdjusted = (accountCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // we then scale this up to meet the same decimals as the totalCoinMinted
        // and finally divide by totalCoinMinted to get the users health factor
        // (50 * 1e18) / (50 * 1e18 - the amount of coin the user minted) = 1e18 (our MINIMUM_HEALTH_FACTOR)
        // the user is 200% collateralised, but only just
        return (collateralAdjusted * PRECISION) / totalCoinMinted;
    }

    /**
     *
     * @param _user the user we are getting the coin amount minted and account collateral value for
     * @return totalCoinMinted the amount of coin they have minted
     * @return collateralValueInUsd the collateral value of their account
     */
    function getAccountInformation(address _user)
        public
        view
        returns (uint256 totalCoinMinted, uint256 collateralValueInUsd)
    {
        totalCoinMinted = getCoinUserHasMinted(_user);
        collateralValueInUsd = getAccountCollateralValueInUsd(_user);
        return (totalCoinMinted, collateralValueInUsd);
    }

    /**
     * @notice this function gets the account collateral value
     * @param _user the user who's account we are calculating the collateral value for
     * @dev 1. we first get the length of the collateral tokens accepted in our protocol
     * 2. we loop through the tokens, calculate the current usd value for that token (for example, ETH may be $2000 at the time)
     * 3. we then multiple the token value by the number of tokens the user holds to get the token value that user holds
     * 4. for each token the user holds, this value is added to the account value.
     * @return accountValueInUsd is the total value for that account in usd
     */
    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 accountValueInUsd) {
        address[] memory collateralTokens = getCollateralTokens();
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 userTokenValueInUsd = getTokenValueInUsd(token, s_collateralDeposited[_user][token]);
            accountValueInUsd += userTokenValueInUsd;
        }
        return accountValueInUsd;
    }

    /**
     * @notice this function retrieves the usd price for a token
     * @param _token the token we are trying to calculate the value for
     * @dev we pass the price feed address (for example, weth: 0x694AA1769357215DE4FAC081bf1f309aDC325306) into the AggregatorV3Interface
     * now chainlink knows which token to retrieve the price for (and call the functions on)
     * we call "latestRoundData()", which, by itself, returns 5 values. Price is the second ('answer')
     * within the aggregator, it returns a int256 (instead of a uint256), so we convert it to a uint256 in our return
     */
    function getTokenValueInUsd(address _token, uint256 _amount) public view returns (uint256 tokenValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // chainlink returns the price in 8 decimals
        // we scale it up to 18 decimal places (by multiplying by ADDITIONAL_FEED_PRECISION (1e10, 10 decimal places))
        // then we multiply the now-1e18 price by the 1e18 amount the user has. If we didn't do these conversions,
        // you'd be multiplying incorrect value (due to confusion with decimal places)
        // we then scale it back down to usd by multiplying by PRECISION (1e18, 18 decimal places)
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * _amount) / PRECISION;
    }

    /**
     * @notice this function calculates the amount of tokens that could be purchased given an amount of usd in wei
     * @param _token the token we are getting the amount for
     * @param _usdAmountInWei the amount of usd in wei that equates to the amount of tokens
     */
    function getTokenAmountFromUsd(address _token, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // we scale the usd amount in wei (which is already in 18 decimal format) to 36 decimals)
        // we then divide this by price (scaled up to 18 decimals - as chainlink returns it in 8)
        // this leaves us with (usdamount (36 decimals) / price (18 decimals))
        // = token amount (18 decimals) - 18 decimals aligning with wei
        return ((_usdAmountInWei * PRECISION) / uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    // --------------------------------------------------------------------------------------------------------
    // LIQUIDATE
    // --------------------------------------------------------------------------------------------------------

    /**
     * @notice this function allows the liquidator to liquidate the user, redeeming the collateral (which equates to the debtToCover in COIN), plus a 10% bonus
     * @param _user the user we are liquidating
     * @param _tokenCollateralToLiquidate the specific token to liquidate, such as weth
     * @param _debtToCover this is the amount the liquidator wants to liquidate. It could be full or partial, and would be calculated off-chain
     * @dev how liquidation actually works:
     * lets say the user mints a certain amount of coin (pegged to $1). At this point, the user does not have any debt as their collateral value deposited is adequate
     * however, if the collateral amount drops, as they still hold the stablecoin which equates to the previous collateral value (before the price dropped),
     * they are now in debt. They owe collateral to make the value of collateral = stablecoin balance (in the protocol, not the users actual balance).
     * This is where overcollateralisation comes in.
     * we can take their collateral (from their overcollateralised position), give it to the liquidator, and burn the liquidators stablecoin
     * This ensures that there isn't too much stablecoin in circulation (our protocol is backed by enough collateral)
     * important note: the debt is created when the price drops. The liquidation is a mechanism to reduce the debt.
     * We give the liquidator the amount of debt the user owes in collateral value, and burn the liquidators stablecoin
     *
     */
    function liquidate(address _user, address _tokenCollateralToLiquidate, uint256 _debtToCover) external {
        uint256 userStartingHealthFactor = _healthFactor(_user);
        if (userStartingHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert Engine__HealthFactorIsOk();
        }
        // as the debtToCover (coin) is a stablecoin, it is passed as the usdAmountInWei
        // it asks the function: how much collateral is x stablecoin worth
        // it then gives this to the liquidator (plus a bonus), and the liquidator burns their debt to cover to balance it out
        uint256 tokenAmountFromUsd = getTokenAmountFromUsd(_tokenCollateralToLiquidate, _debtToCover);
        uint256 bonusCollateral = (tokenAmountFromUsd * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeemForLiquidator = tokenAmountFromUsd + bonusCollateral;

        _redeemCollateral(_tokenCollateralToLiquidate, totalCollateralToRedeemForLiquidator, _user, msg.sender);
        // only the public redeemCollateral function has a burnDsc call within it, not the _redeemCollateral. So we must call it
        // we pass the _user as we reduce their coin minted mapping, msg.sender because its the liquidator's coins we are burning
        // and the debtToCover (not the totalCollateralToRedeemForLiquidator), because we already calculates the conversion into collateral value
        _burnCoin(_user, msg.sender, _debtToCover);

        uint256 userEndingHealthFactor = _healthFactor(_user);
        if (userEndingHealthFactor >= userStartingHealthFactor) {
            revert Engine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // --------------------------------------------------------------------------------------------------------
    // GETTER
    // --------------------------------------------------------------------------------------------------------

    /**
     * @notice fetches the collateral tokens accepted in this protocol. For example, WETH
     * @return an array of the collateral tokens
     */
    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @notice fetches the coin amount minted for a specific user
     * @param _user the user we want to see how much coin has been minted for
     */
    function getCoinUserHasMinted(address _user) public view returns (uint256) {
        return s_coinMinted[_user];
    }

    /**
     * @notice this function gets the collateral amount the user has deposited
     * @param _user the user whose collateral amount deposited we want to know
     * @param _token the specific token we are finding the value for
     */
    function getCollateralAmountUserDeposited(address _user, address _token) external view returns (uint256) {
        return (s_collateralDeposited[_user][_token]);
    }

    /**
     * @notice this function gets the users health factor
     * @param _user the user whose health factor we are trying to identify
     */
    function getUserHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    /**
     * @notice this function retreives the precision
     */
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /**
     * @notice this function retreives the liquidation threshold
     */
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice this function retreives the liquidation bonus
     */
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /**
     * @notice this function retreives the liquidation precision
     */
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /**
     * @notice this function retreives the minimum health factor for the protocol
     */
    function getMinimumHealthFactor() external pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    /**
     * @notice this function retreives the additional price feed precision
     */
    function getAdditionalPriceFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }
}
