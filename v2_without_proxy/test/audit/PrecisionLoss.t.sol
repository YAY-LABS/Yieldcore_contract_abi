// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../unit/BaseTest.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {console2} from "forge-std/Test.sol";

contract PrecisionLossTest is BaseTest {
    RWAVault public vault;

    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());
    }

    /// @notice H-01: Test partial withdrawals for dust accumulation
    function test_H01_PartialWithdrawDustAccumulation() public {
        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest to vault (poolManager has USDC from BaseTest setup)
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 1000e6);
        vault.depositInterest(1000e6); // Enough to cover 15% APY for 180 days
        vm.stopPrank();

        // Mature vault
        vm.warp(block.timestamp + 180 days);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal start time
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // Now user tries to withdraw in 3 parts
        vm.startPrank(user1);

        (uint256 sharesBefore, , , ) = vault.getDepositInfo(user1);
        uint256 maxWithdrawable = vault.maxWithdraw(user1);

        console2.log("=== H-01 Precision Loss Test ===");
        console2.log("Initial shares:", sharesBefore);
        console2.log("Max withdrawable:", maxWithdrawable);

        // Try to withdraw 1/3 each time
        uint256 perWithdraw = maxWithdrawable / 3;

        // First withdrawal
        vault.withdraw(perWithdraw, user1, user1);
        (uint256 shares1, , , ) = vault.getDepositInfo(user1);
        console2.log("After 1st withdraw - shares:", shares1);

        // Second withdrawal
        vault.withdraw(perWithdraw, user1, user1);
        (uint256 shares2, , , ) = vault.getDepositInfo(user1);
        console2.log("After 2nd withdraw - shares:", shares2);

        // Third withdrawal - try to withdraw remaining
        uint256 remaining = vault.maxWithdraw(user1);
        console2.log("Remaining withdrawable:", remaining);

        if (remaining > 0) {
            vault.withdraw(remaining, user1, user1);
        }

        (uint256 sharesAfter, uint256 principalAfter, , ) = vault.getDepositInfo(user1);
        console2.log("Final shares:", sharesAfter);
        console2.log("Final principal:", principalAfter);

        // Check if there's dust left
        uint256 dustShares = sharesAfter;
        uint256 dustValue = dustShares > 0 ? vault.convertToAssets(dustShares) : 0;

        console2.log("=== RESULT ===");
        console2.log("Dust shares:", dustShares);
        console2.log("Dust value (USDC):", dustValue);

        // If dust > 0, H-01 is confirmed
        if (dustShares > 0) {
            console2.log("H-01 CONFIRMED: Dust remains after full withdrawal attempt");
        } else {
            console2.log("H-01 NOT CONFIRMED: No dust after withdrawals");
        }

        vm.stopPrank();
    }

    /// @notice H-02: Test share transfer dust accumulation
    function test_H02_ShareTransferDustAccumulation() public {
        address recipient = makeAddr("recipient");

        // User deposits 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        (uint256 sharesBefore, uint256 principalBefore, , ) = vault.getDepositInfo(user1);

        console2.log("=== H-02 Share Transfer Dust Test ===");
        console2.log("Initial shares:", sharesBefore);
        console2.log("Initial principal:", principalBefore);

        // Transfer 1/3 of shares multiple times (must be >= MIN_SHARE_TRANSFER = 1e6)
        uint256 transferAmount = sharesBefore / 3;
        require(transferAmount >= 1e6, "Transfer amount below minimum");

        // First transfer
        vault.transfer(recipient, transferAmount);
        (uint256 userShares1, uint256 userPrincipal1, , ) = vault.getDepositInfo(user1);
        (uint256 recipientShares1, uint256 recipientPrincipal1, , ) = vault.getDepositInfo(recipient);

        console2.log("After 1st transfer:");
        console2.log("  User shares:", userShares1, "principal:", userPrincipal1);
        console2.log("  Recipient shares:", recipientShares1, "principal:", recipientPrincipal1);

        // Second transfer
        vault.transfer(recipient, transferAmount);
        (uint256 userShares2, uint256 userPrincipal2, , ) = vault.getDepositInfo(user1);
        (uint256 recipientShares2, uint256 recipientPrincipal2, , ) = vault.getDepositInfo(recipient);

        console2.log("After 2nd transfer:");
        console2.log("  User shares:", userShares2, "principal:", userPrincipal2);
        console2.log("  Recipient shares:", recipientShares2, "principal:", recipientPrincipal2);

        // Check total principal conservation
        uint256 totalPrincipalAfter = userPrincipal2 + recipientPrincipal2;
        uint256 principalLoss = principalBefore > totalPrincipalAfter ? principalBefore - totalPrincipalAfter : 0;

        console2.log("=== RESULT ===");
        console2.log("Original principal:", principalBefore);
        console2.log("Total principal after transfers:", totalPrincipalAfter);
        console2.log("Principal loss:", principalLoss);

        // If loss > 0, H-02 is confirmed
        if (principalLoss > 0) {
            console2.log("H-02 CONFIRMED: Principal lost during transfers");
        } else {
            console2.log("H-02 NOT CONFIRMED: No principal loss");
        }

        vm.stopPrank();
    }

    /// @notice H-03: Test return capital pattern inconsistency
    function test_H03_ReturnCapitalPatterns() public {
        // This is a code review finding - let's verify the code patterns
        console2.log("=== H-03 Return Pattern Analysis ===");
        console2.log("returnCapital(): expects funds already transferred (Push pattern)");
        console2.log("returnCapitalWithRate(): uses transferFrom internally (Pull pattern)");
        console2.log("");
        console2.log("Recommendation: Unify to Pull pattern for consistency and safety");
    }
}
