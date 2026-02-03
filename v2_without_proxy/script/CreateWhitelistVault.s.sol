// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";
import {RWAVault} from "../src/vault/RWAVault.sol";

/// @title CreateWhitelistVault
/// @notice Creates a vault with whitelist and specific deposit caps
/// @dev Timeline (Feb 3, 2026 KST):
///      - Collection: 1pm ~ 4pm (whitelist until 3pm, then open)
///      - Interest Start: 5pm
///      - 3 rounds x 1 hour: 5pm-6pm, 6pm-7pm, 7pm-8pm
///      - Payments: 30min after each round (6:30pm, 7:30pm, 8:30pm)
///      - Withdrawal: 8:30pm
contract CreateWhitelistVault is Script {
    function run() external {
        // Load config
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Creating Whitelist Vault ===");
        console2.log("");

        // Timestamps (Feb 3, 2026 KST) - delayed by 1 hour
        uint256 collectionStartTime = 1770091200;  // 1pm KST
        uint256 collectionEndTime = 1770102000;    // 4pm KST
        uint256 interestStartTime = 1770105600;    // 5pm KST

        // 3 rounds x 1 hour
        uint256 termDuration = 3 hours;
        uint256 months = 3;

        // Period end dates (end of each 1-hour round)
        uint256[] memory periodEndDates = new uint256[](months);
        periodEndDates[0] = 1770109200;  // 6pm KST (Round 1 end)
        periodEndDates[1] = 1770112800;  // 7pm KST (Round 2 end)
        periodEndDates[2] = 1770116400;  // 8pm KST (Round 3 end / Maturity)

        // Payment dates (30 min after each round ends)
        uint256[] memory paymentDates = new uint256[](months);
        paymentDates[0] = 1770111000;   // 6:30pm KST
        paymentDates[1] = 1770114600;   // 7:30pm KST
        paymentDates[2] = 1770118200;   // 8:30pm KST

        // Withdrawal starts 30 min after maturity
        uint256 withdrawalStartTime = 1770118200;  // 8:30pm KST

        // Vault params
        string memory name = "YieldCore Whitelist Test";
        string memory symbol = "ycWL";
        uint256 fixedAPY = 1500;           // 15% APY
        uint256 minDeposit = 1000e6;       // 1,000 USDC
        uint256 maxCapacity = 1_000_000e6; // 1,000,000 USDC

        console2.log("=== Timeline (KST = UTC+9) ===");
        console2.log("Collection Start:  Feb 3 13:00 (1pm)");
        console2.log("Collection End:    Feb 3 16:00 (4pm)");
        console2.log("Interest Start:    Feb 3 17:00 (5pm)");
        console2.log("Round 1 End:       Feb 3 18:00 (6pm)");
        console2.log("Round 1 Payment:   Feb 3 18:30 (6:30pm)");
        console2.log("Round 2 End:       Feb 3 19:00 (7pm)");
        console2.log("Round 2 Payment:   Feb 3 19:30 (7:30pm)");
        console2.log("Round 3 End:       Feb 3 20:00 (8pm) = Maturity");
        console2.log("Withdrawal Start:  Feb 3 20:30 (8:30pm)");
        console2.log("");

        console2.log("=== Vault Config ===");
        console2.log("Name:", name);
        console2.log("Symbol:", symbol);
        console2.log("APY: 1500 bps (15%)");
        console2.log("Min Deposit: 1,000 USDC");
        console2.log("Max Per User: 100,000 USDC");
        console2.log("Max Capacity: 1,000,000 USDC");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        VaultFactory factory = VaultFactory(vaultFactoryAddress);

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: name,
            symbol: symbol,
            collectionStartTime: collectionStartTime,
            collectionEndTime: collectionEndTime,
            interestStartTime: interestStartTime,
            termDuration: termDuration,
            fixedAPY: fixedAPY,
            minDeposit: minDeposit,
            maxCapacity: maxCapacity,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: withdrawalStartTime
        });

        address vaultAddress = factory.createVault(params);
        RWAVault vault = RWAVault(vaultAddress);

        console2.log("=== Vault Created ===");
        console2.log("Vault Address:", vaultAddress);
        console2.log("");

        // Set user deposit caps (min 1000, max 100000 USDC)
        vault.setUserDepositCaps(1000e6, 100_000e6);
        console2.log("User deposit caps set: min 1,000 / max 100,000 USDC");

        // Enable whitelist
        vault.setWhitelistEnabled(true);
        console2.log("Whitelist enabled");

        // Add whitelisted addresses
        address[] memory whitelist = new address[](2);
        whitelist[0] = 0x0aeEadFba133b7d4C85cd154fA8e953093Ac1189;
        whitelist[1] = 0x1c5a21FF819F8B00970aF05c7f0D10F8DBb4704D;

        vault.addToWhitelist(whitelist);
        console2.log("Whitelisted addresses:");
        console2.log("  -", whitelist[0]);
        console2.log("  -", whitelist[1]);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Setup Complete ===");
        console2.log("");
        console2.log("=== Admin Actions Required ===");
        console2.log("1. At 3pm KST: call vault.setWhitelistEnabled(false) to open deposits");
        console2.log("2. After 4pm KST: call vault.activateVault()");
        console2.log("3. After 8pm KST: call vault.matureVault()");
    }
}
