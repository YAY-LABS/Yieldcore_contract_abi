// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @title DeployMockUSDC
/// @notice Deploy Mock USDC for testing on Sepolia
/// @dev Run with: forge script script/DeployMockUSDC.s.sol:DeployMockUSDC --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
contract DeployMockUSDC is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Deploying Mock USDC ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDC with 6 decimals (same as real USDC)
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "mUSDC", 6);

        console2.log("Mock USDC deployed at:", address(mockUSDC));

        // Mint initial supply to deployer (100M USDC for testing)
        uint256 initialSupply = 100_000_000e6; // 100M USDC
        mockUSDC.mint(deployer, initialSupply);
        console2.log("Minted", initialSupply / 1e6, "USDC to deployer");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Deployment Complete ===");
        console2.log("Mock USDC Address:", address(mockUSDC));
        console2.log("Update ASSET_ADDRESS in .env to:", address(mockUSDC));
    }
}

/// @title MintMockUSDC
/// @notice Mint additional Mock USDC for testing
/// @dev Run with: forge script script/DeployMockUSDC.s.sol:MintMockUSDC --rpc-url $SEPOLIA_RPC_URL --broadcast
contract MintMockUSDC is Script {
    function run() external {
        address mockUSDCAddress = vm.envAddress("ASSET_ADDRESS");
        address recipient = vm.envOr("MINT_RECIPIENT", vm.envAddress("ADMIN_ADDRESS"));
        uint256 amount = vm.envOr("MINT_AMOUNT", uint256(10_000e6)); // Default 10k USDC

        console2.log("=== Minting Mock USDC ===");
        console2.log("Mock USDC:", mockUSDCAddress);
        console2.log("Recipient:", recipient);
        console2.log("Amount:", amount / 1e6, "USDC");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockUSDC = MockERC20(mockUSDCAddress);
        mockUSDC.mint(recipient, amount);

        vm.stopBroadcast();

        console2.log("=== Mint Complete ===");
        console2.log("New balance:", mockUSDC.balanceOf(recipient) / 1e6, "USDC");
    }
}
