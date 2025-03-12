// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HookMiner
/// @notice Utility for mining hook addresses with specific flags
library HookMiner {
    /// @notice Find a salt that will produce a hook address with the desired flags
    /// @param deployer The address that will deploy the hook
    /// @param flags The desired flags for the hook address
    /// @param creationCode The creation code of the hook contract
    /// @param constructorArgs The constructor arguments for the hook contract
    /// @param salt An optional salt to start mining from
    /// @return hookAddress The mined hook address
    /// @return initCode The initialization code for the hook
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        bytes32 salt
    ) internal pure returns (address hookAddress, bytes memory initCode) {
        // Concatenate the creation code and constructor args
        initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        
        // Keep mining until we find a hook address with the correct flags
        uint256 nonce = 0;
        while (true) {
            // Calculate the hook address using CREATE2
            hookAddress = computeAddress(deployer, salt, initCodeHash);
            
            // Check if the hook address has the correct flags
            if (uint160(hookAddress) & 0xFFFF == flags) {
                // We found a valid hook address
                break;
            }
            
            // Increment the nonce and try again
            nonce++;
            salt = bytes32(nonce);
        }
        
        return (hookAddress, initCode);
    }
    
    /// @notice Compute the address of a contract deployed using CREATE2
    /// @param deployer The address that will deploy the contract
    /// @param salt The salt used for the deployment
    /// @param initCodeHash The keccak256 hash of the contract's initialization code
    /// @return The computed address
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            deployer,
                            salt,
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
    
    /// @notice Compute the salt that will produce a specific hook address
    /// @param deployer The address that will deploy the hook
    /// @param flags The desired flags for the hook address
    /// @param creationCode The creation code of the hook contract
    /// @param constructorArgs The constructor arguments for the hook contract
    /// @param targetAddress The target hook address to match
    /// @return salt The computed salt
    function computeSalt(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        address targetAddress
    ) internal pure returns (bytes32) {
        // Concatenate the creation code and constructor args
        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(initCode);
        
        // Try different salts until we find the one that produces the target address
        for (uint256 i = 0; i < 1000000; i++) {
            bytes32 salt = bytes32(i);
            address computedAddress = computeAddress(deployer, salt, initCodeHash);
            
            if (computedAddress == targetAddress) {
                return salt;
            }
        }
        
        revert("Salt not found");
    }
}
