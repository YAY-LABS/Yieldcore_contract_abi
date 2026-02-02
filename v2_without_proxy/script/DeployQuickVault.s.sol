// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @title DeployQuickVault
/// @notice Deploy a test vault with 10-minute interest intervals
contract DeployQuickVault is Script {
    function run() external {
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddress);

        // Quick test vault parameters
        uint256 collectionDuration = 5 minutes;
        uint256 termDuration = 30 minutes;
        uint256 interestStartTime = block.timestamp + collectionDuration;
        uint256 maturityTime = interestStartTime + termDuration;

        // 3 interest periods at 10-minute intervals
        uint256[] memory periodEndDates = new uint256[](3);
        periodEndDates[0] = interestStartTime + 10 minutes;
        periodEndDates[1] = interestStartTime + 20 minutes;
        periodEndDates[2] = interestStartTime + 30 minutes;

        // Payment dates: 2 minutes after each period end
        uint256[] memory paymentDates = new uint256[](3);
        paymentDates[0] = interestStartTime + 12 minutes;
        paymentDates[1] = interestStartTime + 22 minutes;
        paymentDates[2] = interestStartTime + 32 minutes;

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "Quick Test Vault",
            symbol: "ycQUICK",
            collectionStartTime: 0, // 0 = immediate deposit allowed
            collectionEndTime: block.timestamp + collectionDuration,
            interestStartTime: interestStartTime,
            termDuration: termDuration,
            fixedAPY: 1500, // 15%
            minDeposit: 1e6, // 1 USDC
            maxCapacity: 100_000e6, // 100k USDC
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        console2.log("=== Deploying Quick Test Vault ===");
        console2.log("Collection Duration: 5 minutes");
        console2.log("Term Duration: 30 minutes");
        console2.log("Interest Periods: 3 (10-min intervals)");
        console2.log("Fixed APY: 15%");
        console2.log("Min Deposit: 1 USDC");
        console2.log("");

        address vault = vaultFactory.createVault(params);

        vm.stopBroadcast();

        console2.log("=== Vault Created ===");
        console2.log("Vault Address:", vault);
        console2.log("Collection Ends:", block.timestamp + collectionDuration);
        console2.log("Interest Starts:", interestStartTime);
        console2.log("Maturity:", maturityTime);
    }
}
