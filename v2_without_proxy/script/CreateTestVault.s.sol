// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @title CreateTestVault
/// @notice Creates a short-term test vault for quick testing
/// @dev Collection: 30min, Term: 3hrs, Interest periods: 1hr each, APY: 30%
contract CreateTestVault is Script {
    function run() external {
        // Load config
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Base timestamp - use env or current time
        uint256 baseTime = vm.envOr("BASE_TIMESTAMP", block.timestamp);

        console2.log("=== Creating Short-Term Test Vault ===");
        console2.log("Base Timestamp:", baseTime);
        console2.log("");

        // Time settings
        uint256 collectionDuration = 30 minutes;
        uint256 termDuration = 3 hours;
        uint256 interestPeriod = 1 hours;
        uint256 months = termDuration / interestPeriod; // 3 periods

        // Vault params
        string memory name = "Test Vault (3hr)";
        string memory symbol = "tvRWA";
        uint256 fixedAPY = 3000;  // 30%
        uint256 minDeposit = 1e6; // 1 USDC
        uint256 maxCapacity = 1_000_000e6; // 1M USDC

        // Calculate timestamps
        uint256 collectionEndTime = baseTime + collectionDuration;
        uint256 interestStartTime = collectionEndTime;
        uint256 maturityTime = interestStartTime + termDuration;

        console2.log("=== Timeline ===");
        console2.log("Now (base):        ", baseTime);
        console2.log("Collection End:    ", collectionEndTime, "(+30min)");
        console2.log("Interest Start:    ", interestStartTime);
        console2.log("Maturity:          ", maturityTime, "(+3hr)");
        console2.log("");

        // Generate interest period dates (1hr intervals)
        uint256[] memory periodEndDates = new uint256[](months);
        uint256[] memory paymentDates = new uint256[](months);

        console2.log("=== Interest Periods ===");
        for (uint256 i = 0; i < months; i++) {
            periodEndDates[i] = interestStartTime + ((i + 1) * interestPeriod);
            paymentDates[i] = periodEndDates[i] + 5 minutes; // 5min after period end
            console2.log("Period", i + 1, "End:", periodEndDates[i]);
            console2.log("  Payment Date:", paymentDates[i]);
        }
        console2.log("");

        console2.log("=== Vault Config ===");
        console2.log("Name:", name);
        console2.log("Symbol:", symbol);
        console2.log("APY:", fixedAPY, "bps (30%)");
        console2.log("Min Deposit: 1 USDC");
        console2.log("Max Capacity: 1M USDC");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        VaultFactory factory = VaultFactory(vaultFactoryAddress);

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: name,
            symbol: symbol,
            collectionStartTime: 0, // 0 = immediate deposit allowed
            collectionEndTime: collectionEndTime,
            interestStartTime: interestStartTime,
            termDuration: termDuration,
            fixedAPY: fixedAPY,
            minDeposit: minDeposit,
            maxCapacity: maxCapacity,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        address vault = factory.createVault(params);

        vm.stopBroadcast();

        console2.log("=== Vault Created ===");
        console2.log("Vault Address:", vault);
        console2.log("");
        console2.log("=== Test Flow ===");
        console2.log("1. Deposit USDC (within 30min)");
        console2.log("2. Wait for collection to end");
        console2.log("3. Admin calls activateVault()");
        console2.log("4. Claim interest at each payment date (1hr intervals)");
        console2.log("5. After 3hrs, call matureVault() and withdraw");
    }
}
