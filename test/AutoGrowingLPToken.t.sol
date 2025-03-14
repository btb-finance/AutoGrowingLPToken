// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AutoGrowingLPTokenV4} from "../src/token.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract AutoGrowingLPTokenTest is Test {
    AutoGrowingLPTokenV4 public token;
    IPoolManager public poolManager;
    address public owner;
    address public devWallet;
    
    function setUp() public {
        // Deploy a new pool manager
        poolManager = new PoolManager(address(this));
        
        // Set up owner and dev wallet addresses
        owner = address(this);
        devWallet = address(0x123);
        
        // Calculate hook address with the correct flags
        (address hookAddress, bytes memory initCode) = HookMiner.find(
            address(this),
            uint160(
                Hooks.BEFORE_SWAP_FLAG | 
                Hooks.AFTER_SWAP_FLAG | 
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | 
                Hooks.AFTER_ADD_LIQUIDITY_FLAG
            ),
            type(AutoGrowingLPTokenV4).creationCode,
            abi.encode(
                "AutoGrowingLPToken",
                "AGLP",
                devWallet,
                address(poolManager),
                owner
            ),
            bytes32(uint256(0))
        );
        
        // Deploy the token contract with the mined address
        vm.record();
        token = new AutoGrowingLPTokenV4{salt: bytes32(uint256(0))}(
            "AutoGrowingLPToken",
            "AGLP",
            devWallet,
            poolManager,
            owner
        );
        
        // Verify the hook address matches the expected address
        assertEq(address(token), hookAddress, "Hook address mismatch");
    }
    
    function testTokenInitialization() public {
        // Test token initialization
        assertEq(token.name(), "AutoGrowingLPToken", "Token name mismatch");
        assertEq(token.symbol(), "AGLP", "Token symbol mismatch");
        assertEq(token.owner(), owner, "Token owner mismatch");
    }
    
    function testTokenPurchase() public {
        // Test token purchase
        uint256 initialBalance = token.balanceOf(address(this));
        
        // Purchase tokens with 1 ETH
        (bool success, ) = address(token).call{value: 1 ether}("");
        assertTrue(success, "Token purchase failed");
        
        // Check that tokens were minted
        uint256 newBalance = token.balanceOf(address(this));
        assertTrue(newBalance > initialBalance, "No tokens were minted");
    }
}
