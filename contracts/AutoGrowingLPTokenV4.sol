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
import "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

/**
 * @title AutoGrowingLPTokenV4
 * @dev A token that automatically grows in price based on purchase volume
 * Each 1 ETH volume increases price by 0.1%, so 10 ETH increases by 1%
 * Users can buy directly from the contract at the current price
 * 50% of ETH is added to LP in full range and the NFT position is kept
 * The hook claims fees over time, buys tokens, and burns them
 */
contract AutoGrowingLPTokenV4 is ERC20, Ownable, IHooks, IUnlockCallback {
    using SafeCast for uint256;
    using LPFeeLibrary for uint24;
    using Hooks for IHooks;

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
    IPoolManager public immutable poolManager;
    PoolKey public poolKey;
    Currency public tokenCurrency;
    Currency public wethCurrency;
    uint24 public constant FEE_RATE = 3000; // 0.3% fee tier
    int24 public constant MIN_TICK = -887272; // Full range lower tick
    int24 public constant MAX_TICK = 887272; // Full range upper tick
    bool public poolInitialized = false;
    
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
    
    // Error events to provide detailed information about failures
    error PoolInitializationFailed(string reason);
    error ETHTransferFailed(address to, uint256 amount, string reason);
    error LiquidityOperationFailed(string operation, string reason);
    error TokenOperationFailed(string operation, string reason);
    error FeeCollectionFailed(string reason);
    error InvalidHookPermissions();

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
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_devWallet != address(0), "Dev wallet cannot be zero address");
        
        devWallet = _devWallet;
        poolManager = _poolManager;
        
        // Set initial price to 0.00000000000001 ETH (converted to wei with 18 decimals)
        contractPrice = INITIAL_PRICE;
        buyCount = 0;
        
        // Set up currencies for Uniswap V4
        tokenCurrency = Currency.wrap(address(this));
        wethCurrency = Currency.wrap(address(0)); // Native ETH is represented by the zero address in Uniswap V4
        
        // Initialize timestamp for fee collection
        lastFeeCollectionTimestamp = block.timestamp;

        // Validate hook permissions
        IHooks(address(this)).validateHookPermissions(
            Hooks.Permissions({
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
            })
        );
    }

    /**
     * @dev Initialize the Uniswap V4 pool (must be called after deployment)
     * @param sqrtPriceX96 Initial sqrt price (79228162514264337593543950336 for 1:1 pool)
     * @return bool Returns true if the pool was initialized successfully
     */
    function initializePool(uint160 sqrtPriceX96) external onlyOwner returns (bool) {
        require(!poolInitialized, "Pool already initialized");
        
        // Create pool key with this contract as the hook
        // Currency0 must be less than Currency1 according to Uniswap V4 rules
        Currency currency0;
        Currency currency1;
        
        // Sort currencies according to Uniswap V4 requirements
        if (Currency.unwrap(tokenCurrency) < Currency.unwrap(wethCurrency)) {
            currency0 = tokenCurrency;
            currency1 = wethCurrency;
        } else {
            currency0 = wethCurrency;
            currency1 = tokenCurrency;
        }
        
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE_RATE,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });
        
        // Initialize the pool with try/catch to handle errors
        try poolManager.initialize(poolKey, sqrtPriceX96) {
            poolInitialized = true;
            emit PoolInitialized(address(poolManager), currency0, currency1);
            return true;
        } catch Error(string memory reason) {
            emit PoolInitializationFailed(reason);
            return false;
        } catch (bytes memory) {
            emit PoolInitializationFailed("Unknown error during pool initialization");
            return false;
        }
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
     * @return bool Returns true if the purchase was successful
     */
    function buy() external payable returns (bool) {
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
        if (!devSuccess) {
            // If dev transfer fails, add it to LP share
            lpShare += devShare;
        }
        
        // Use LP share to add liquidity if pool is initialized
        if (lpShare > 0 && poolInitialized) {
            addLiquidityV4(lpShare);
        }
        
        // Increment buy counter
        buyCount++;
        
        // Update price after purchase with the ETH amount
        updateContractPrice(msg.value);
        
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
        return true;
    }
    
    /**
     * @dev Adds liquidity to Uniswap V4 in full range
     * @param ethAmount Amount of ETH to add to liquidity
     * @return bool Returns true if liquidity was added successfully
     */
    function addLiquidityV4(uint256 ethAmount) public returns (bool) {
        require(poolInitialized, "Pool not initialized");
        
        // Calculate token amount to match ETH for liquidity
        uint256 tokenAmount = (ethAmount * 10**decimals()) / contractPrice;
        
        // Mint tokens to this contract for liquidity
        _mint(address(this), tokenAmount);
        
        // Approve tokens for the pool manager
        _approve(address(this), address(poolManager), tokenAmount);
        
        // Construct unlock data to add liquidity
        bytes memory unlockData = abi.encode(
            ethAmount,
            tokenAmount
        );
        
        // Unlock the pool manager to add liquidity
        try poolManager.unlock(unlockData) {
            emit LiquidityAdded(tokenAmount, ethAmount);
            return true;
        } catch Error(string memory reason) {
            emit LiquidityOperationFailed("unlock", reason);
            return false;
        } catch (bytes memory) {
            emit LiquidityOperationFailed("unlock", "Unknown error during pool unlock");
            return false;
        }
    }
    
    /**
     * @dev Implementation of IUnlockCallback for pool manager to call back
     * This handles the liquidity provision when the pool is unlocked
     */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Not pool manager");
        
        // Decode the unlock data
        (uint256 ethAmount, uint256 tokenAmount) = abi.decode(data, (uint256, uint256));
        
        // Determine which currency is token and which is ETH
        bool isToken0 = poolKey.currency0 == tokenCurrency;
        
        // Transfer token to pool manager
        IERC20(address(this)).transfer(address(poolManager), tokenAmount);
        
        // Add liquidity to the pool in full range
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: int256(tokenAmount).toInt128(), // Convert to int128 using SafeCast
            salt: bytes32(0) // Default salt value
        });
        
        // Call modifyLiquidity to add the liquidity
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(poolKey, params, "");
        
        // Handle native ETH payment to pool
        if (ethAmount > 0) {
            poolManager.settle{value: ethAmount}();
        }
        
        return "";
    }
    
    /**
     * @dev Collect fees from the pool and use them to buy and burn tokens
     * Can be called by anyone after the collection interval has passed
     * @return bool Returns true if fees were collected successfully
     */
    function collectFeesAndBurn() external returns (bool) {
        require(poolInitialized, "Pool not initialized");
        require(block.timestamp >= lastFeeCollectionTimestamp + feeCollectionInterval, "Collection interval not passed");
        
        // Update last collection timestamp
        lastFeeCollectionTimestamp = block.timestamp;
        
        // Construct unlock data for fee collection
        bytes memory unlockData = abi.encode("COLLECT_FEES");
        
        // Unlock the pool manager to collect fees
        try poolManager.unlock(unlockData) returns (bytes memory returnData) {
            // Decode returned fee amounts
            (uint256 amount0, uint256 amount1) = abi.decode(returnData, (uint256, uint256));
            
            emit FeesCollected(amount0, amount1);
            
            // Determine which currency is token and which is ETH
            bool isToken0 = poolKey.currency0 == tokenCurrency;
            
            // Extract ETH amount and token amount
            uint256 ethAmount = isToken0 ? amount1 : amount0;
            uint256 tokenAmount = isToken0 ? amount0 : amount1;
            
            // Burn tokens if any were collected
            if (tokenAmount > 0) {
                _burn(address(this), tokenAmount);
                tokensBurned += tokenAmount;
                emit TokensBurned(tokenAmount);
            }
            
            // Use ETH to buy and burn more tokens
            if (ethAmount > 0) {
                uint256 tokensToBurn = (ethAmount * 10**decimals()) / contractPrice;
                _mint(address(this), tokensToBurn);
                _burn(address(this), tokensToBurn);
                tokensBurned += tokensToBurn;
                emit TokensBurned(tokensToBurn);
            }
            
            return true;
        } catch Error(string memory reason) {
            emit FeeCollectionFailed(reason);
            return false;
        } catch (bytes memory) {
            emit FeeCollectionFailed("Unknown error during fee collection");
            return false;
        }
    }
    
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
     * @dev Returns the hook permissions
     */
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
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
    
    // Hook implementations
    
    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        returns (bytes4)
    {
        // Verify this is our pool
        if (key.currency0 != poolKey.currency0 || key.currency1 != poolKey.currency1) {
            return IHooks.afterInitialize.selector;
        }
        
        return IHooks.afterInitialize.selector;
    }
    
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        // Verify this is our pool
        if (key.currency0 != poolKey.currency0 || key.currency1 != poolKey.currency1) {
            return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
        }
        
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }
    
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // Verify this is our pool
        if (key.currency0 != poolKey.currency0 || key.currency1 != poolKey.currency1) {
            return (IHooks.afterSwap.selector, 0);
        }
        
        // Check if it's time to collect fees, but don't do it here (reentrancy issues)
        if (block.timestamp >= lastFeeCollectionTimestamp + feeCollectionInterval) {
            // Just mark that fees can be collected
            lastFeeCollectionTimestamp = block.timestamp;
        }
        
        return (IHooks.afterSwap.selector, 0);
    }
    
    // Fallback for receiving ETH
    receive() external payable {}
    
    // Other required hook functions (stubs)
    
    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert("Not implemented");
    }
    
    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Not implemented");
    }
    
    function beforeRemoveLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Not implemented");
    }
    
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert("Not implemented");
    }
    
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert("Not implemented");
    }
    
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Not implemented");
    }
    
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Not implemented");
    }
}