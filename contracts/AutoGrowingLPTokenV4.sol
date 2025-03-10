// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uniswap V4 imports
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/interfaces/IHooks.sol";
import "@uniswap/v4-core/src/libraries/Hooks.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/BalanceDelta.sol";
import "@uniswap/v4-core/src/types/Currency.sol";
import "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import "@uniswap/v4-core/src/libraries/SafeCast.sol";
import "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

// Import base hook implementation
import "./exmples/base/BaseHook.sol";
import "./exmples/utils/CurrencySettler.sol";

/**
 * @title AutoGrowingLPTokenV4
 * @dev A token that automatically grows in price based on purchase volume
 * Each 1 ETH volume increases price by 0.1%, so 10 ETH increases by 1%
 * Users can buy directly from the contract at the current price
 * 50% of ETH is added to LP in full range and the NFT position is kept
 * The hook claims fees over time, buys tokens, and burns them
 */
contract AutoGrowingLPTokenV4 is ERC20, Ownable, BaseHook {
    using SafeCast for uint256;
    using CurrencySettler for Currency;
    using LPFeeLibrary for uint24;

    // Token price state variables
    uint256 public contractPrice; // Current contract-defined price in ETH (18 decimals)
    uint256 public buyCount; // Counter for buys to track statistics
    uint256 public constant GROWTH_RATE_DENOMINATOR = 1000000;
    uint256 public constant ETH_PRICE_IMPACT_RATE = 1001000; // 0.1% per 1 ETH (1001000/1000000)
    uint256 public constant PRICE_DECIMALS = 18; // Decimals for price calculations
    
    // Initial price of 0.00000000000001 ETH (with 18 decimals)
    uint256 public constant INITIAL_PRICE = 10000; // 0.00000000000001 * 10^18

    // Distribution parameters
    address public devWallet; // Developer wallet for fee distribution
    
    // Distribution ratios (out of 1000 for precision)
    uint256 public devShareRatio = 500; // 50%
    uint256 public lpShareRatio = 500; // 50%
    
    // Uniswap V4 parameters
    PoolKey public poolKey;
    Currency public tokenCurrency;
    Currency public wethCurrency;
    uint24 public constant FEE_RATE = 3000; // 0.3% fee tier
    int24 public constant MIN_TICK = -887272; // Full range lower tick
    int24 public constant MAX_TICK = 887272; // Full range upper tick
    
    // Fee collection parameters
    uint256 public lastFeeCollectionTimestamp;
    uint256 public feeCollectionInterval = 1 days; // Collect fees once per day
    uint256 public tokensBurned; // Track total tokens burned from fees
    
    // Events for transparency and monitoring
    event ContractPriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 buyCount, uint256 ethAmount);
    event WalletUpdated(string walletType, address oldWallet, address newWallet);
    event DistributionRatiosUpdated(uint256 devShareRatio, uint256 lpShareRatio);
    event TokensPurchased(address buyer, uint256 ethAmount, uint256 tokenAmount);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount);
    event FeesCollected(uint256 amount0, uint256 amount1);
    event TokensBurned(uint256 amount);
    event PoolInitialized(address poolAddress, Currency token, Currency weth);

    /**
     * @dev Constructor sets up the token with initial parameters
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _devWallet Address of the developer wallet
     * @param _poolManager Address of the Uniswap V4 PoolManager
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _devWallet,
        IPoolManager _poolManager
    ) ERC20(_name, _symbol) Ownable(msg.sender) BaseHook(_poolManager) {
        require(_devWallet != address(0), "Dev wallet cannot be zero address");
        
        devWallet = _devWallet;
        
        // Set initial price to 0.00000000000001 ETH (converted to wei with 18 decimals)
        contractPrice = INITIAL_PRICE;
        buyCount = 0;
        
        // Set up currencies for Uniswap V4
        tokenCurrency = Currency.wrap(address(this));
        wethCurrency = Currency.wrap(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH address
        
        // Initialize timestamp for fee collection
        lastFeeCollectionTimestamp = block.timestamp;
    }

    /**
     * @dev Initialize the Uniswap V4 pool (must be called after deployment)
     * @param sqrtPriceX96 Initial sqrt price
     */
    function initializePool(uint160 sqrtPriceX96) external onlyOwner {
        // Create pool key with this contract as the hook
        poolKey = PoolKey({
            currency0: tokenCurrency,
            currency1: wethCurrency,
            fee: FEE_RATE,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });
        
        // Initialize the pool
        poolManager.initialize(poolKey, sqrtPriceX96);
        
        emit PoolInitialized(address(poolManager), tokenCurrency, wethCurrency);
    }

    /**
     * @dev Updates the contract price based on the ETH volume of the purchase
     * Each 1 ETH increases price by 0.1%
     * @param ethAmount Amount of ETH used in the purchase (in wei)
     * @return newPrice The updated contract price
     */
    function updateContractPrice(uint256 ethAmount) internal returns (uint256 newPrice) {
        uint256 oldPrice = contractPrice;
        
        // Calculate price increase factor based on ETH amount
        // Convert to whole ETH units (divide by 1e18) and scale to our base (multiply by 1M)
        uint256 ethInWholeUnits = (ethAmount * 1000000) / 1 ether;
        
        // Calculate growth factor: 1.0 + (0.001 * ethAmount)
        // For 1 ETH: 1.0 + 0.001 = 1.001 (0.1% increase)
        // For 10 ETH: 1.0 + 0.01 = 1.01 (1% increase)
        uint256 growthFactor = 1000000 + ((ETH_PRICE_IMPACT_RATE - 1000000) * ethInWholeUnits) / 1000000;
        
        // Apply the growth factor to the current price
        contractPrice = (contractPrice * growthFactor) / GROWTH_RATE_DENOMINATOR;
        
        // Emit event with ETH amount included
        emit ContractPriceUpdated(oldPrice, contractPrice, buyCount, ethAmount);
        
        return contractPrice;
    }
    
    /**
     * @dev Update the dev wallet address (only owner)
     * @param _newDevWallet New dev wallet address
     */
    function setDevWallet(address _newDevWallet) external onlyOwner {
        require(_newDevWallet != address(0), "Dev wallet cannot be zero address");
        
        address oldWallet = devWallet;
        devWallet = _newDevWallet;
        
        emit WalletUpdated("DevWallet", oldWallet, _newDevWallet);
    }

    /**
     * @dev Update distribution ratios (only owner)
     * @param _devShareRatio New dev share ratio (out of 1000)
     * @param _lpShareRatio New LP share ratio (out of 1000)
     */
    function setDistributionRatios(uint256 _devShareRatio, uint256 _lpShareRatio) external onlyOwner {
        require(_devShareRatio + _lpShareRatio == 1000, "Ratios must sum to 1000");
        
        devShareRatio = _devShareRatio;
        lpShareRatio = _lpShareRatio;
        
        emit DistributionRatiosUpdated(_devShareRatio, _lpShareRatio);
    }
    
    /**
     * @dev Update fee collection interval (only owner)
     * @param _interval New interval in seconds
     */
    function setFeeCollectionInterval(uint256 _interval) external onlyOwner {
        require(_interval > 0, "Interval must be greater than 0");
        feeCollectionInterval = _interval;
    }
    
    /**
     * @dev Get the current token price from the contract
     * @return Current contract price with 18 decimals precision
     */
    function getCurrentPrice() public view returns (uint256) {
        return contractPrice;
    }
    
    /**
     * @dev Buy tokens with ETH
     * This function allows users to buy tokens directly from the contract
     * Price increases based on purchase volume - each 1 ETH increases price by 0.1%
     */
    function buy() external payable {
        require(msg.value > 0, "Must send ETH to buy tokens");
        
        // Calculate token amount based on current price
        uint256 tokenAmount = (msg.value * 10**decimals()) / contractPrice;
        
        // Mint tokens to buyer
        _mint(msg.sender, tokenAmount);
        
        // Calculate shares
        uint256 devShare = (msg.value * devShareRatio) / 1000;
        uint256 lpShare = (msg.value * lpShareRatio) / 1000;
        
        // Transfer dev share
        (bool devSuccess, ) = devWallet.call{value: devShare}("");
        require(devSuccess, "Dev fee transfer failed");
        
        // Use LP share to add liquidity
        if (lpShare > 0) {
            addLiquidityV4(lpShare);
        }
        
        // Increment buy counter
        buyCount++;
        
        // Update price after purchase with the ETH amount
        updateContractPrice(msg.value);
        
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }
    
    /**
     * @dev Adds liquidity to Uniswap V4 in full range
     * @param ethAmount Amount of ETH to add to liquidity
     */
    function addLiquidityV4(uint256 ethAmount) internal {
        // Calculate token amount to match ETH for liquidity
        uint256 tokenAmount = (ethAmount * 10**decimals()) / contractPrice;
        
        // Mint tokens to this contract for liquidity
        _mint(address(this), tokenAmount);
        
        // Approve tokens for the pool manager
        _approve(address(this), address(poolManager), tokenAmount);
        
        // Add liquidity to the pool in full range
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: SafeCast.toInt128(int256(tokenAmount)), // Convert to int128 using SafeCast
            salt: bytes32(0) // Default salt value
        });
        
        // Add liquidity to the pool
        poolManager.modifyLiquidity(poolKey, params, "");
        
        // Transfer ETH to the pool manager
        (bool success, ) = address(poolManager).call{value: ethAmount}("");
        require(success, "ETH transfer to pool manager failed");
        
        emit LiquidityAdded(tokenAmount, ethAmount);
    }
    
    /**
     * @dev Collect fees from the pool and use them to buy and burn tokens
     * Can be called by anyone after the collection interval has passed
     */
    function collectFeesAndBurn() external {
        require(block.timestamp >= lastFeeCollectionTimestamp + feeCollectionInterval, "Collection interval not passed");
        
        // Update last collection timestamp
        lastFeeCollectionTimestamp = block.timestamp;
        
        // Collect fees from the pool by calling modifyLiquidity with zero liquidityDelta
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: 0, // Zero to collect fees without modifying liquidity
            salt: bytes32(0)
        });
        
        // The first BalanceDelta is for the caller (total of principal and fees)
        // The second BalanceDelta is the fee delta generated in the liquidity range
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(poolKey, params, "");
        
        // Extract amounts from the balance delta
        int128 amount0Delta = delta.amount0();
        int128 amount1Delta = delta.amount1();
        
        // Convert to uint256 if positive (we received tokens)
        uint256 amount0 = amount0Delta > 0 ? uint256(uint128(amount0Delta)) : 0;
        uint256 amount1 = amount1Delta > 0 ? uint256(uint128(amount1Delta)) : 0;
        
        emit FeesCollected(amount0, amount1);
        
        // Use collected ETH to buy and burn tokens
        if (amount1 > 0) { // Assuming amount1 is ETH/WETH
            uint256 tokensToBurn = (amount1 * 10**decimals()) / contractPrice;
            
            // Burn tokens
            _burn(address(this), tokensToBurn);
            tokensBurned += tokensToBurn;
            
            emit TokensBurned(tokensToBurn);
        }
    }
    
    /**
     * @dev Fallback to receive ETH
     */
    receive() external payable {}

    /**
     * @dev Calculate how many tokens user will receive for a given ETH amount
     * @param ethAmount Amount of ETH in wei
     * @return Amount of tokens user will receive
     */
    function getTokensForETH(uint256 ethAmount) public view returns (uint256) {
        return (ethAmount * 10**decimals()) / contractPrice;
    }
    
    /**
     * @dev Calculate how much ETH is needed for a given token amount
     * @param tokenAmount Amount of tokens
     * @return Amount of ETH needed in wei
     */
    function getETHForTokens(uint256 tokenAmount) public view returns (uint256) {
        return (tokenAmount * contractPrice) / 10**decimals();
    }
    
    /**
     * @dev Get information about tokens burned from fees
     * @return Amount of tokens burned from collected fees
     */
    function getTotalBurnedTokens() public view returns (uint256) {
        return tokensBurned;
    }
    
    /**
     * @dev Get comprehensive price growth statistics
     * @return initialPrice The starting price of the token
     * @return currentPrice The current price of the token
     * @return growthPercentage How much the price has grown in basis points (100 = 1%)
     * @return totalBuys Total number of purchases
     */
    function getPriceGrowthStats() public view returns (
        uint256 initialPrice,
        uint256 currentPrice,
        uint256 growthPercentage,
        uint256 totalBuys
    ) {
        initialPrice = INITIAL_PRICE;
        currentPrice = contractPrice;
        // Calculate growth in basis points (100 = 1%)
        growthPercentage = currentPrice > initialPrice ? 
            ((currentPrice * 10000) / INITIAL_PRICE) - 10000 : 0;
        totalBuys = buyCount;
    }
    
    /**
     * @dev Get all current distribution parameters in a single call
     * @return _devWallet Current developer wallet address
     * @return _devShareRatio Percentage of ETH going to dev (out of 1000)
     * @return _lpShareRatio Percentage of ETH going to liquidity (out of 1000)
     */
    function getDistributionParams() public view returns (
        address _devWallet,
        uint256 _devShareRatio,
        uint256 _lpShareRatio
    ) {
        return (devWallet, devShareRatio, lpShareRatio);
    }
    
    /**
     * @dev Implementation of the getHookPermissions function from BaseHook
     * Defines which hook functions are implemented
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * @dev Hook called after pool initialization
     */
    function _afterInitialize(address, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        // Verify this is our pool
        if (!(key.currency0 == tokenCurrency) && !(key.currency1 == tokenCurrency)) {
            return IHooks.afterInitialize.selector;
        }
        
        // Return the function selector to indicate success
        return IHooks.afterInitialize.selector;
    }
    
    /**
     * @dev Hook called after liquidity is added to the pool
     */
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        // Verify this is our pool
        if (!(key.currency0 == tokenCurrency) && !(key.currency1 == tokenCurrency)) {
            return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
        }
        
        // Return the function selector to indicate success
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }
    
    /**
     * @dev Hook called after a swap occurs in the pool
     * We can use this to track volume and potentially trigger fee collection
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Verify this is our pool
        if (!(key.currency0 == tokenCurrency) && !(key.currency1 == tokenCurrency)) {
            return (IHooks.afterSwap.selector, 0);
        }
        
        // Check if it's time to collect fees
        if (block.timestamp >= lastFeeCollectionTimestamp + feeCollectionInterval) {
            // We can't call collectFeesAndBurn directly from here due to reentrancy protection
            // Instead, we'll update the timestamp so it can be called after this transaction
            lastFeeCollectionTimestamp = block.timestamp;
        }
        
        // Return the function selector to indicate success
        return (IHooks.afterSwap.selector, 0);
    }
}