// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";
import {RWAVault} from "../src/vault/RWAVault.sol";

/// @title CreateWhitelistVault
/// @notice Creates a vault with whitelist and specific deposit caps
/// @dev Timeline (Feb 4, 2026 KST):
///      - Collection: now ~ 3pm (whitelist until 1pm, then open)
///      - Interest Start: 4pm
///      - 3 rounds x 1 hour: 4pm-5pm, 5pm-6pm, 6pm-7pm
///      - Payments: 30min after each round (5:30pm, 6:30pm, 7:30pm)
///      - Withdrawal: 7:30pm
contract CreateWhitelistVault is Script {
    function run() external {
        // Load config
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Creating Whitelist Vault ===");
        console2.log("");

        // Timestamps (Feb 4, 2026 KST)
        uint256 collectionStartTime = 1770170400;  // 11am KST
        uint256 collectionEndTime = 1770184800;    // 3pm KST
        uint256 interestStartTime = 1770188400;    // 4pm KST

        // 3 rounds x 1 hour
        uint256 termDuration = 3 hours;
        uint256 months = 3;

        // Period end dates (end of each 1-hour round)
        uint256[] memory periodEndDates = new uint256[](months);
        periodEndDates[0] = 1770192000;  // 5pm KST (Round 1 end)
        periodEndDates[1] = 1770195600;  // 6pm KST (Round 2 end)
        periodEndDates[2] = 1770199200;  // 7pm KST (Round 3 end / Maturity)

        // Payment dates (30 min after each round ends)
        uint256[] memory paymentDates = new uint256[](months);
        paymentDates[0] = 1770193800;   // 5:30pm KST
        paymentDates[1] = 1770197400;   // 6:30pm KST
        paymentDates[2] = 1770201000;   // 7:30pm KST

        // Withdrawal starts 30 min after maturity
        uint256 withdrawalStartTime = 1770201000;  // 7:30pm KST

        // Vault params
        string memory name = "YieldCore Whitelist Test";
        string memory symbol = "ycWL";
        uint256 fixedAPY = 1500;           // 15% APY
        uint256 minDeposit = 1000e6;       // 1,000 USDC
        uint256 maxCapacity = 1_000_000e6; // 1,000,000 USDC

        console2.log("=== Timeline (KST = UTC+9) ===");
        console2.log("Collection Start:  Feb 4 11:00 (11am)");
        console2.log("Collection End:    Feb 4 15:00 (3pm)");
        console2.log("Interest Start:    Feb 4 16:00 (4pm)");
        console2.log("Round 1 End:       Feb 4 17:00 (5pm)");
        console2.log("Round 1 Payment:   Feb 4 17:30 (5:30pm)");
        console2.log("Round 2 End:       Feb 4 18:00 (6pm)");
        console2.log("Round 2 Payment:   Feb 4 18:30 (6:30pm)");
        console2.log("Round 3 End:       Feb 4 19:00 (7pm) = Maturity");
        console2.log("Withdrawal Start:  Feb 4 19:30 (7:30pm)");
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
        console2.log("1. At 1pm KST: call vault.setWhitelistEnabled(false) to open deposits");
        console2.log("2. After 3pm KST: call vault.activateVault()");
        console2.log("3. After 7pm KST: call vault.matureVault()");
    }
}
