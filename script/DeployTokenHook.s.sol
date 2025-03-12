// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {AutoGrowingLPTokenV4} from "../src/token.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

/// @notice Deploys the AutoGrowingLPTokenV4 Hook contract
contract DeployTokenHook is Script {
    // Configuration parameters
    string public constant TOKEN_NAME = "AutoGrowingLPToken";
    string public constant TOKEN_SYMBOL = "AGLP";
    address public constant DEV_WALLET = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Using the second anvil account
    uint160 public constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // 1:1 price
    
    // PoolManager address (already deployed)
    address public constant POOL_MANAGER_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    
    // CREATE2 Deployer address (used for deterministic deployments)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Default anvil private key for first account
    uint256 constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        // Get the script sender address
        address scriptSender = vm.addr(ANVIL_PRIVATE_KEY);
        console.log("Script sender:", scriptSender);
        
        // Get the flags directly from the contract's getHookPermissions function
        // These must match exactly with what's returned by getHookPermissions()
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
            Hooks.AFTER_SWAP_FLAG
        );
        
        console.log("Using hook flags:", uint256(flags));
        
        // Prepare constructor arguments - set the script sender as the owner
        bytes memory constructorArgs = abi.encode(
            TOKEN_NAME, 
            TOKEN_SYMBOL, 
            scriptSender, // Set the script sender as the dev wallet
            IPoolManager(POOL_MANAGER_ADDRESS),
            scriptSender // Set the script sender as the owner
        );
        
        // Mine a hook address with the correct flags
        (address hookAddress, bytes memory initCode) = HookMiner.find(
            CREATE2_DEPLOYER, // Use the CREATE2_DEPLOYER as the deployer
            flags, 
            type(AutoGrowingLPTokenV4).creationCode, 
            constructorArgs,
            bytes32(uint256(block.timestamp)) // Use current timestamp as salt for uniqueness
        );
        
        console.log("Mined hook address:", hookAddress);
        
        // Check if the contract already exists at the target address
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(hookAddress)
        }
        
        // Only deploy if the contract doesn't exist yet
        if (codeSize == 0) {
            // Extract the salt that was used to find the hook address
            bytes32 salt = bytes32(0);
            bytes32 initCodeHash = keccak256(initCode);
            for (uint256 i = 0; i < 1000000; i++) {
                salt = bytes32(i);
                address computedAddress = address(
                    uint160(
                        uint256(
                            keccak256(
                                abi.encodePacked(
                                    bytes1(0xff),
                                    CREATE2_DEPLOYER,
                                    salt,
                                    initCodeHash
                                )
                            )
                        )
                    )
                );
                
                if (computedAddress == hookAddress) {
                    break;
                }
            }
            
            console.log("Using salt:", uint256(salt));
            
            // Start the broadcast to record and send transactions
            vm.startBroadcast(ANVIL_PRIVATE_KEY);
            
            // Deploy the hook using CREATE2 with the calculated salt
            AutoGrowingLPTokenV4 hook = new AutoGrowingLPTokenV4{salt: salt}(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                scriptSender, // Dev wallet
                IPoolManager(POOL_MANAGER_ADDRESS),
                scriptSender // Owner
            );
            
            // Verify the deployment was successful
            require(address(hook) == hookAddress, "Hook deployment failed");
            console.log("Hook deployed at:", address(hook));
            
            // Initialize the token with a pool
            hook.initializePool(INITIAL_SQRT_PRICE);
            console.log("Pool initialized with sqrt price:", INITIAL_SQRT_PRICE);
            
            // End the broadcast
            vm.stopBroadcast();
        } else {
            console.log("Hook already deployed at:", hookAddress);
        }
    }
}
