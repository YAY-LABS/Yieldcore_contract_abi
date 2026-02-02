// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @title CreateSuperVault
/// @notice Creates SuperVault for testing
/// @dev Collection: 15:00~24:00 KST, Interest Start: +12h, Term: 3 periods x 1h
contract CreateSuperVault is Script {
    function run() external {
        // Load config
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("=== Creating SuperVault ===");
        console2.log("");

        // KST = UTC + 9
        // Collection Start: 2026-02-02 15:00 KST = 2026-02-02 06:00 UTC
        // Collection End: 2026-02-03 00:00 KST = 2026-02-02 15:00 UTC
        // Interest Start: 2026-02-03 12:00 KST = 2026-02-03 03:00 UTC

        // Unix timestamps
        // Collection Start: 2026-02-02 15:00 KST = 2026-02-02 06:00 UTC = 1770012000
        // Collection End: 2026-02-03 00:00 KST = 2026-02-02 15:00 UTC = 1770044400
        // Interest Start: 2026-02-03 12:00 KST = 2026-02-03 03:00 UTC = 1770087600
        uint256 collectionStartTime = vm.envOr("COLLECTION_START_TIME", uint256(1770012000));
        uint256 collectionEndTime = vm.envOr("COLLECTION_END_TIME", uint256(1770044400));
        uint256 interestStartTime = vm.envOr("INTEREST_START_TIME", uint256(1770087600));

        // Term: 3 hours (3 periods x 1 hour each for testing)
        uint256 termDuration = 3 hours;
        uint256 interestPeriod = 1 hours;
        uint256 months = 3; // 3 interest periods

        // Vault params
        string memory name = "SuperVault Q1 2026";
        string memory symbol = "svRWA";
        uint256 fixedAPY = 1200;  // 12% APY
        uint256 minDeposit = 1e6; // 1 USDC
        uint256 maxCapacity = 1_000_000e6; // 1M USDC

        uint256 maturityTime = interestStartTime + termDuration;
        uint256 withdrawalStartTime = maturityTime;

        console2.log("=== Timeline (KST = UTC+9) ===");
        console2.log("Collection Start (UTC):", collectionStartTime);
        console2.log("Collection End (UTC):  ", collectionEndTime);
        console2.log("Interest Start (UTC):  ", interestStartTime);
        console2.log("Maturity (UTC):        ", maturityTime);
        console2.log("Term Duration:         ", termDuration, "seconds (3 hours)");
        console2.log("");

        // Generate interest period dates (1 hour intervals, 3 periods)
        uint256[] memory periodEndDates = new uint256[](months);
        uint256[] memory paymentDates = new uint256[](months);

        console2.log("=== Interest Periods (1 hour each) ===");
        for (uint256 i = 0; i < months; i++) {
            periodEndDates[i] = interestStartTime + ((i + 1) * interestPeriod);
            paymentDates[i] = periodEndDates[i]; // Payment available immediately at period end
            console2.log("Period", i + 1, "End:", periodEndDates[i]);
        }
        console2.log("");

        console2.log("=== Vault Config ===");
        console2.log("Name:", name);
        console2.log("Symbol:", symbol);
        console2.log("APY:", fixedAPY, "bps (12%)");
        console2.log("Min Deposit: 1 USDC");
        console2.log("Max Capacity: 1M USDC");
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

        address vault = factory.createVault(params);

        vm.stopBroadcast();

        console2.log("=== SuperVault Created ===");
        console2.log("Vault Address:", vault);
        console2.log("");
        console2.log("=== Test Flow ===");
        console2.log("1. Deposit USDC (15:00~24:00 KST today)");
        console2.log("2. Wait for collection to end (midnight KST)");
        console2.log("3. Admin calls activateVault() after interest start time");
        console2.log("4. Claim interest at each hour (3 times)");
        console2.log("5. After 3 hours, call matureVault() and withdraw");
    }
}
