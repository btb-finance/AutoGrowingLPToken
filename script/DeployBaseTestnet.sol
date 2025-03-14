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
import "test/utils/HookMiner.sol"; // Import HookMiner properly - assuming it's a library

// Interface for the canonical CREATE2 factory (EIP-2470)
interface ISingletonFactory {
    function deploy(bytes memory _initCode, bytes32 _salt) external returns (address payable createdContract);
}

/// @notice Deploys the AutoGrowingLPTokenV4 Hook contract to Base Sepolia testnet
contract DeployBaseTestnet is Script {
    // Configuration parameters
    string public constant TOKEN_NAME = "AutoGrowingLPToken";
    string public constant TOKEN_SYMBOL = "AGLP";
    // Your deployer address from the private key: 0xbe2680DC1752109b4344DbEB1072fd8Cd880e54b
    address public constant DEV_WALLET = 0xbe2680DC1752109b4344DbEB1072fd8Cd880e54b;
    uint160 public constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // 1:1 price
    
    // Base Sepolia PoolManager address
    address public constant POOL_MANAGER_ADDRESS = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    
    // Canonical CREATE2 factory address (same on all EVM chains including Base Sepolia)
    address public constant SINGLETON_FACTORY = 0xce0042B868300000d44A59004Da54A005ffdcf9f;
    
    // Your private key - provided by user
    uint256 constant PRIVATE_KEY = 0x89266ff69e24130a10d24dfb80316a2c6f3e2304345e8796aa820a3a19f27589;

    function run() external {
        // Get the deployer address
        address deployer = vm.addr(PRIVATE_KEY);
        console.log("Deployer address:", deployer);
        
        // Get the flags directly from the contract's getHookPermissions function
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
            Hooks.AFTER_SWAP_FLAG
        );
        console.log("Using hook flags:", uint256(flags));
        
        // Prepare the bytecode and constructor args
        // This is the important change - pass deployer as the owner in the constructor
        bytes memory bytecode = type(AutoGrowingLPTokenV4).creationCode;
        bytes memory constructorArgs = abi.encode(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            DEV_WALLET,
            IPoolManager(POOL_MANAGER_ADDRESS),
            deployer  // Pass the deployer as the owner if needed
        );
        
        // Combine bytecode and constructor args
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        // Find a salt that will create an address with the correct flags
        // We need to manually implement the salt finding logic since we can't use the library directly
        bytes32 salt;
        address predictedAddress;
        uint256 startingSalt = uint256(keccak256(abi.encodePacked(block.timestamp, block.number, deployer))) % type(uint32).max;
        
        // Loop to find a salt that creates an address with the right flags
        for (uint256 i = 0; i < 1000000; i++) {
            bytes32 candidateSalt = bytes32(startingSalt + i);
            address computedAddress = computeCreate2Address(SINGLETON_FACTORY, candidateSalt, initCode);
            
            // Check if the address has the required hook flags
            if (uint160(computedAddress) & 0xFFFF == flags) {
                salt = candidateSalt;
                predictedAddress = computedAddress;
                break;
            }
        }
        
        require(predictedAddress != address(0), "Failed to find a valid salt");
        
        console.log("Found valid hook address:", predictedAddress);
        console.log("Using salt:", uint256(salt));
        
        // Check if address has code (already deployed)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predictedAddress)
        }
        
        // Start the broadcast to record and send transactions
        vm.startBroadcast(PRIVATE_KEY);
        
        address deployedAddress;
        if (codeSize > 0) {
            console.log("Contract already deployed at the predicted address");
            deployedAddress = predictedAddress;
        } else {
            // Deploy the contract using the canonical CREATE2 factory
            try ISingletonFactory(SINGLETON_FACTORY).deploy(initCode, salt) returns (address payable addr) {
                deployedAddress = addr;
                console.log("Hook deployed at:", deployedAddress);
            } catch Error(string memory reason) {
                console.log("Deployment failed:", reason);
                vm.stopBroadcast();
                return;
            } catch {
                console.log("Deployment failed with unknown error");
                vm.stopBroadcast();
                return;
            }
        }
        
        // Initialize the pool
        AutoGrowingLPTokenV4 token = AutoGrowingLPTokenV4(payable(deployedAddress));
        
        // Try to check who the owner is
        try token.owner() returns (address contractOwner) {
            console.log("Contract owner is:", contractOwner);
            if (contractOwner != deployer) {
                console.log("WARNING: You are not the owner of the contract!");
            }
        } catch {
            console.log("Failed to check contract owner");
        }
        
        // Check if pool is already initialized by calling the initializePool function
        try token.initializePool(INITIAL_SQRT_PRICE) {
            console.log("Pool initialized with sqrt price:", INITIAL_SQRT_PRICE);
        } catch Error(string memory reason) {
            console.log("Pool initialization failed:", reason);
            // Print the error message directly to help debug
            console.log(reason);
        } catch {
            console.log("Pool initialization failed with unknown error");
        }
        
        // End the broadcast
        vm.stopBroadcast();
    }
    
    // Helper function to compute CREATE2 address
    function computeCreate2Address(address factory, bytes32 salt, bytes memory bytecode) internal pure returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        bytes32 _data = keccak256(
            abi.encodePacked(bytes1(0xff), factory, salt, bytecodeHash)
        );
        return address(uint160(uint256(_data)));
    }
}