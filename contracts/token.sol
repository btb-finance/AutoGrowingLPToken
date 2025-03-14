// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AutoGrowingLPToken
 * @dev A token that automatically grows in price based on purchase volume
 * Each 1 ETH volume increases price by 0.1%, so 10 ETH increases by 1%
 * Users can buy directly from the contract at the current price
 * 50% of ETH is added to LP and a portion of LP tokens are burned to increase locked liquidity
 */
contract AutoGrowingLPToken is ERC20, Ownable {
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
    
    // LP burning percentage (out of 100)
    uint256 public lpBurnPercentage = 100; // 100% of LP tokens are burned
    
    // Uniswap interfaces for LP management
    IUniswapV2Router02 public uniswapRouter;
    address public uniswapPair;
    address public weth;
    
    // Dead address for LP token burning
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // Events for transparency and monitoring
    event ContractPriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 buyCount, uint256 ethAmount);
    event WalletUpdated(string walletType, address oldWallet, address newWallet);
    event DistributionRatiosUpdated(uint256 devShareRatio, uint256 lpShareRatio);
    event TokensPurchased(address buyer, uint256 ethAmount, uint256 tokenAmount);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, uint256 lpTokens);
    event LPTokensBurned(uint256 amount);
    event RouterUpdated(address oldRouter, address newRouter);
    event LPBurnPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);

    /**
     * @dev Constructor sets up the token with initial parameters
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _devWallet Address of the developer wallet
     * @param _router Address of the Uniswap V2 Router
     * @param _initialSupply Initial token supply to mint to deployer (not used anymore)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _devWallet,
        address _router,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_devWallet != address(0), "Dev wallet cannot be zero address");
        require(_router != address(0), "Router cannot be zero address");
        
        devWallet = _devWallet;
        uniswapRouter = IUniswapV2Router02(_router);
        weth = uniswapRouter.WETH();
        
        // Set initial price to 0.00000000000001 ETH (converted to wei with 18 decimals)
        contractPrice = INITIAL_PRICE;
        buyCount = 0;
        
        // No initial tokens are minted - removed initial minting
        
        // Create Uniswap pair with WETH
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        uniswapPair = factory.createPair(address(this), weth);
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
     * @dev Update the Uniswap router (only owner)
     * @param _newRouter New Uniswap router address
     */
    function setUniswapRouter(address _newRouter) external onlyOwner {
        require(_newRouter != address(0), "Router cannot be zero address");
        
        address oldRouter = address(uniswapRouter);
        uniswapRouter = IUniswapV2Router02(_newRouter);
        weth = uniswapRouter.WETH();
        
        // Create new Uniswap pair
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapRouter.factory());
        uniswapPair = factory.createPair(address(this), weth);
        
        emit RouterUpdated(oldRouter, _newRouter);
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
     * @dev Update LP burn percentage (only owner)
     * @param _lpBurnPercentage New LP burn percentage (out of 100)
     */
    function setLPBurnPercentage(uint256 _lpBurnPercentage) external onlyOwner {
        require(_lpBurnPercentage <= 100, "Percentage must be <= 100");
        
        uint256 oldPercentage = lpBurnPercentage;
        lpBurnPercentage = _lpBurnPercentage;
        
        emit LPBurnPercentageUpdated(oldPercentage, _lpBurnPercentage);
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
            addLiquidityETH(lpShare);
        }
        
        // Increment buy counter
        buyCount++;
        
        // Update price after purchase with the ETH amount
        updateContractPrice(msg.value);
        
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }
    
    /**
     * @dev Adds liquidity to Uniswap and burns a portion of LP tokens
     * @param ethAmount Amount of ETH to add to liquidity
     */
    function addLiquidityETH(uint256 ethAmount) internal {
        // Calculate token amount to match ETH for liquidity
        uint256 tokenAmount = (ethAmount * 10**decimals()) / contractPrice;
        
        // Mint tokens to this contract for liquidity
        _mint(address(this), tokenAmount);
        
        // Approve the router to spend tokens
        _approve(address(this), address(uniswapRouter), tokenAmount);
        
        // Add liquidity to Uniswap
        (uint tokenAmountUsed, uint ethAmountUsed, uint liquidity) = uniswapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // Accept any amount of tokens
            0, // Accept any amount of ETH
            address(this),
            block.timestamp + 15 minutes
        );
        
        // Calculate amount of LP tokens to burn
        uint256 lpTokensToBurn = (liquidity * lpBurnPercentage) / 100;
        
        // Get the LP token contract
        IERC20 lpToken = IERC20(uniswapPair);
        
        // Burn LP tokens by sending to dead address
        lpToken.transfer(DEAD_ADDRESS, lpTokensToBurn);
        
        emit LiquidityAdded(tokenAmountUsed, ethAmountUsed, liquidity);
        emit LPTokensBurned(lpTokensToBurn);
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
     * @dev Get information about permanently locked liquidity
     * @return Amount of LP tokens burned and locked forever
     */
    function getTotalBurnedLPTokens() public view returns (uint256) {
        return IERC20(uniswapPair).balanceOf(DEAD_ADDRESS);
    }
    
    /**
     * @dev Get current reserves in the Uniswap liquidity pool
     * @return tokenReserve Current token balance in the pool
     * @return ethReserve Current ETH balance in the pool
     */
    function getPoolReserves() public view returns (uint256 tokenReserve, uint256 ethReserve) {
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(uniswapPair).getReserves();
        
        // Determine token order in the pair
        address token0 = IUniswapV2Pair(uniswapPair).token0();
        
        if (token0 == address(this)) {
            return (reserve0, reserve1);
        } else {
            return (reserve1, reserve0);
        }
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
     * @return _lpBurnPercentage Percentage of LP tokens that are burned (out of 100)
     */
    function getDistributionParams() public view returns (
        address _devWallet,
        uint256 _devShareRatio,
        uint256 _lpShareRatio,
        uint256 _lpBurnPercentage
    ) {
        return (devWallet, devShareRatio, lpShareRatio, lpBurnPercentage);
    }
    
    /**
     * @dev Get all Uniswap-related addresses in a single call
     * @return _router Address of the Uniswap router
     * @return _pair Address of the token-ETH trading pair
     * @return _weth Address of the wrapped ETH contract
     */
    function getUniswapDetails() public view returns (
        address _router,
        address _pair,
        address _weth
    ) {
        return (address(uniswapRouter), uniswapPair, weth);
    }
    
    /**
     * @dev Get the estimated market price from Uniswap (if liquidity exists)
     * @return Estimated market price with 18 decimals precision, or 0 if no liquidity
     */
    function getMarketPrice() public view returns (uint256) {
        (uint256 tokenReserve, uint256 ethReserve) = getPoolReserves();
        
        // Return 0 if no liquidity
        if (tokenReserve == 0) return 0;
        
        // Calculate price based on reserves
        // Price = ETH_reserve / token_reserve * 10^18
        return (ethReserve * 10**decimals()) / tokenReserve;
    }
    
    /**
     * @dev Compare contract price with market price
     * @return _contractPrice Current contract-defined price
     * @return _marketPrice Current market price from Uniswap (if available)
     * @return _pricePremium Premium percentage of contract price over market (in basis points)
     */
    function getPriceComparison() public view returns (
        uint256 _contractPrice,
        uint256 _marketPrice,
        int256 _pricePremium
    ) {
        _contractPrice = contractPrice;
        _marketPrice = getMarketPrice();
        
        // Calculate premium percentage in basis points
        if (_marketPrice > 0) {
            if (_contractPrice > _marketPrice) {
                _pricePremium = int256(((_contractPrice * 10000) / _marketPrice) - 10000);
            } else {
                _pricePremium = -int256(((_marketPrice * 10000) / _contractPrice) - 10000);
            }
        } else {
            _pricePremium = 0;
        }
    }
}