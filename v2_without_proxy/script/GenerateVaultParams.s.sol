// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @title GenerateVaultParams
/// @notice Helper script to generate vault parameters for Safe multisig proposals
/// @dev Run with: forge script script/GenerateVaultParams.s.sol -vvv
contract GenerateVaultParams is Script {
    function run() external view {
        // ============ CONFIGURE YOUR VAULT HERE ============

        string memory name = "Yaylabs Test Vault";
        string memory symbol = "YTV";

        // Time offsets from now (in minutes)
        uint256 collectionStartOffset = 10;   // +10분 후 예치 시작
        uint256 collectionEndOffset = 20;     // +20분 후 예치 마감
        uint256 interestStartOffset = 30;     // +30분 후 이자 시작

        // Interest periods (from now, in minutes)
        uint256[] memory periodEndOffsets = new uint256[](2);
        periodEndOffsets[0] = 60;   // +1시간 후 1차 이자 마감
        periodEndOffsets[1] = 90;   // +1시간 30분 후 2차 이자 마감

        uint256[] memory paymentOffsets = new uint256[](2);
        paymentOffsets[0] = 70;     // +1시간 10분 후 1차 이자 수령
        paymentOffsets[1] = 100;    // +1시간 40분 후 2차 이자 수령

        uint256 withdrawalOffset = 100;       // +1시간 40분 후 원금 수령

        // Vault settings
        uint256 fixedAPY = 1000;              // 10% APY (basis points)
        uint256 minDeposit = 100e6;           // 100 USDC minimum
        uint256 maxCapacity = 100_000e6;      // 100,000 USDC max

        // ============ END CONFIGURATION ============

        uint256 now_ = block.timestamp;

        // Calculate absolute timestamps
        uint256 collectionStartTime = now_ + (collectionStartOffset * 60);
        uint256 collectionEndTime = now_ + (collectionEndOffset * 60);
        uint256 interestStartTime = now_ + (interestStartOffset * 60);
        uint256 withdrawalStartTime = now_ + (withdrawalOffset * 60);
        uint256 termDuration = withdrawalStartTime - interestStartTime;

        uint256[] memory interestPeriodEndDates = new uint256[](periodEndOffsets.length);
        uint256[] memory interestPaymentDates = new uint256[](paymentOffsets.length);

        for (uint256 i = 0; i < periodEndOffsets.length; i++) {
            interestPeriodEndDates[i] = now_ + (periodEndOffsets[i] * 60);
            interestPaymentDates[i] = now_ + (paymentOffsets[i] * 60);
        }

        // Output
        console2.log("==============================================");
        console2.log("       VAULT PARAMETERS GENERATOR             ");
        console2.log("==============================================");
        console2.log("");
        console2.log("Current timestamp:", now_);
        console2.log("");

        console2.log("=== createVault Parameters ===");
        console2.log("");
        console2.log("name:", name);
        console2.log("symbol:", symbol);
        console2.log("collectionStartTime:", collectionStartTime);
        console2.log("collectionEndTime:", collectionEndTime);
        console2.log("interestStartTime:", interestStartTime);
        console2.log("termDuration:", termDuration);
        console2.log("fixedAPY:", fixedAPY);
        console2.log("minDeposit:", minDeposit);
        console2.log("maxCapacity:", maxCapacity);
        console2.log("withdrawalStartTime:", withdrawalStartTime);
        console2.log("");

        console2.log("interestPeriodEndDates:");
        for (uint256 i = 0; i < interestPeriodEndDates.length; i++) {
            console2.log("  [", i, "]:", interestPeriodEndDates[i]);
        }

        console2.log("");
        console2.log("interestPaymentDates:");
        for (uint256 i = 0; i < interestPaymentDates.length; i++) {
            console2.log("  [", i, "]:", interestPaymentDates[i]);
        }

        console2.log("");
        console2.log("=== For Safe Transaction Builder ===");
        console2.log("");
        console2.log("Copy this JSON for the params tuple:");
        console2.log("");

        // Print as JSON-like format
        string memory periodEndStr = _arrayToString(interestPeriodEndDates);
        string memory paymentStr = _arrayToString(interestPaymentDates);

        console2.log("{");
        console2.log('  "name": "%s",', name);
        console2.log('  "symbol": "%s",', symbol);
        console2.log('  "collectionStartTime": %d,', collectionStartTime);
        console2.log('  "collectionEndTime": %d,', collectionEndTime);
        console2.log('  "interestStartTime": %d,', interestStartTime);
        console2.log('  "termDuration": %d,', termDuration);
        console2.log('  "fixedAPY": %d,', fixedAPY);
        console2.log('  "minDeposit": %d,', minDeposit);
        console2.log('  "maxCapacity": %d,', maxCapacity);
        console2.log('  "interestPeriodEndDates": %s,', periodEndStr);
        console2.log('  "interestPaymentDates": %s,', paymentStr);
        console2.log('  "withdrawalStartTime": %d', withdrawalStartTime);
        console2.log("}");
        console2.log("");
    }

    function _arrayToString(uint256[] memory arr) internal pure returns (string memory) {
        if (arr.length == 0) return "[]";

        string memory result = "[";
        for (uint256 i = 0; i < arr.length; i++) {
            result = string.concat(result, vm.toString(arr[i]));
            if (i < arr.length - 1) {
                result = string.concat(result, ", ");
            }
        }
        result = string.concat(result, "]");
        return result;
    }
}
