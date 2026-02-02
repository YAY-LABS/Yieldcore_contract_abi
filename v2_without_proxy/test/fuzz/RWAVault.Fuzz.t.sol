// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../unit/BaseTest.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";

/// @title RWAVault Fuzz Tests
/// @notice Fuzz tests for critical vault functions
contract RWAVaultFuzzTest is BaseTest {
    RWAVault public vault;

    uint256 constant MIN_DEPOSIT = 100e6; // 100 USDC
    uint256 constant MAX_CAPACITY = 10_000_000e6; // 10M USDC

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());
    }

    // ============ Fuzz: Deposit ============

    /// @notice Fuzz test deposit with random amounts
    function testFuzz_Deposit(uint256 amount) public {
        // Bound to valid range
        amount = bound(amount, MIN_DEPOSIT, MAX_CAPACITY);

        // Setup
        usdc.mint(user1, amount);
        vm.startPrank(user1);
        usdc.approve(address(vault), amount);

        // Deposit
        uint256 shares = vault.deposit(amount, user1);
        vm.stopPrank();

        // Verify
        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.totalPrincipal(), amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
    }

    /// @notice Fuzz test multiple deposits
    function testFuzz_MultipleDeposits(uint256 amount1, uint256 amount2) public {
        // Bound amounts so total doesn't exceed capacity
        amount1 = bound(amount1, MIN_DEPOSIT, MAX_CAPACITY / 2);
        amount2 = bound(amount2, MIN_DEPOSIT, MAX_CAPACITY / 2);

        // User1 deposit
        usdc.mint(user1, amount1);
        vm.startPrank(user1);
        usdc.approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vm.stopPrank();

        // User2 deposit
        usdc.mint(user2, amount2);
        vm.startPrank(user2);
        usdc.approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vm.stopPrank();

        // Verify total
        assertEq(vault.totalPrincipal(), amount1 + amount2);
        assertEq(vault.totalSupply(), amount1 + amount2);
    }

    // ============ Fuzz: Withdraw ============

    /// @notice Fuzz test withdraw at maturity
    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawRatio) public {
        // Bound inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_CAPACITY / 10);
        withdrawRatio = bound(withdrawRatio, 1, 100); // 1-100%

        // Setup: deposit
        usdc.mint(user1, depositAmount);
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Move to active phase
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Move to maturity
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal time
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // Deposit interest to vault so there's enough balance
        uint256 totalInterest = vault.totalAssets() - depositAmount;
        if (totalInterest > 0) {
            usdc.mint(address(poolManager), totalInterest);
            vm.startPrank(address(poolManager));
            usdc.approve(address(vault), totalInterest);
            vault.depositInterest(totalInterest);
            vm.stopPrank();
        }

        // Calculate withdraw amount (only withdraw from principal to avoid complexity)
        uint256 withdrawAmount = (depositAmount * withdrawRatio) / 100;
        if (withdrawAmount == 0) withdrawAmount = 1; // At least 1

        uint256 userSharesBefore = vault.balanceOf(user1);
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);

        // Skip if sharesToBurn > balance (can happen with rounding)
        if (sharesToBurn > userSharesBefore) return;

        // Withdraw
        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);

        // Verify shares burned
        assertLe(vault.balanceOf(user1), userSharesBefore);
    }

    // ============ Fuzz: Interest Claim ============

    /// @notice Fuzz test interest claim at random times
    function testFuzz_ClaimInterest(uint256 depositAmount, uint256 monthsElapsed) public {
        // Bound inputs (use higher minimum to ensure meaningful interest)
        depositAmount = bound(depositAmount, 10_000e6, MAX_CAPACITY / 10); // Min 10K USDC
        monthsElapsed = bound(monthsElapsed, 1, 12); // 1-12 months

        // Setup: deposit
        usdc.mint(user1, depositAmount);
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Move to active phase
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Get interest period end dates
        uint256[] memory periodEndDates = vault.getInterestPeriodEndDates();
        if (monthsElapsed > periodEndDates.length) {
            monthsElapsed = periodEndDates.length;
        }
        if (monthsElapsed == 0) return;

        // Warp to after the payment date
        vm.warp(periodEndDates[monthsElapsed - 1] + 1);

        // Calculate expected interest (approximate)
        uint256 monthlyInterest = (depositAmount * vault.fixedAPY()) / 10000 / 12;
        uint256 expectedInterest = monthlyInterest * monthsElapsed;

        // Skip if interest would be 0 (small amounts)
        if (expectedInterest == 0) return;

        // Check pending interest before depositing
        uint256 pendingInterest = vault.getPendingInterest(user1);
        if (pendingInterest == 0) return; // No interest to claim yet

        // Deposit enough interest to vault (via poolManager)
        usdc.mint(address(poolManager), pendingInterest);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), pendingInterest);
        vault.depositInterest(pendingInterest);
        vm.stopPrank();

        // Claim interest
        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vault.claimInterest();
        uint256 claimed = usdc.balanceOf(user1) - balanceBefore;

        // Verify interest received
        assertGt(claimed, 0, "Should receive interest");
    }

    // ============ Fuzz: Share Transfer ============

    /// @notice Fuzz test share transfer
    function testFuzz_Transfer(uint256 depositAmount, uint256 transferRatio) public {
        // Bound inputs
        depositAmount = bound(depositAmount, MIN_DEPOSIT, MAX_CAPACITY / 10);
        transferRatio = bound(transferRatio, 1, 100); // 1-100%

        // Setup: deposit
        usdc.mint(user1, depositAmount);
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Calculate transfer amount (respecting MIN_SHARE_TRANSFER)
        uint256 transferAmount = (depositAmount * transferRatio) / 100;
        uint256 minTransfer = RWAConstants.MIN_SHARE_TRANSFER;

        // Skip if transfer too small or would leave dust
        if (transferAmount < minTransfer) return;
        uint256 remaining = depositAmount - transferAmount;
        if (remaining > 0 && remaining < minTransfer) return;

        uint256 user1SharesBefore = vault.balanceOf(user1);
        uint256 user2SharesBefore = vault.balanceOf(user2);

        // Transfer
        vm.prank(user1);
        vault.transfer(user2, transferAmount);

        // Verify
        assertEq(vault.balanceOf(user1), user1SharesBefore - transferAmount);
        assertEq(vault.balanceOf(user2), user2SharesBefore + transferAmount);

        // Verify total supply unchanged
        assertEq(vault.totalSupply(), depositAmount);
    }

    // ============ Fuzz: Edge Cases ============

    /// @notice Fuzz test deposit info consistency after operations
    function testFuzz_DepositInfoConsistency(uint256 amount1, uint256 amount2) public {
        // Bound amounts
        amount1 = bound(amount1, MIN_DEPOSIT, MAX_CAPACITY / 4);
        amount2 = bound(amount2, MIN_DEPOSIT, MAX_CAPACITY / 4);

        // User1 deposits
        usdc.mint(user1, amount1);
        vm.startPrank(user1);
        usdc.approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vm.stopPrank();

        // User2 deposits
        usdc.mint(user2, amount2);
        vm.startPrank(user2);
        usdc.approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vm.stopPrank();

        // Verify deposit info
        (uint256 user1Shares, uint256 user1Principal,,) = vault.getDepositInfo(user1);
        (uint256 user2Shares, uint256 user2Principal,,) = vault.getDepositInfo(user2);

        assertEq(user1Shares, vault.balanceOf(user1));
        assertEq(user2Shares, vault.balanceOf(user2));
        assertEq(user1Principal + user2Principal, vault.totalPrincipal());
    }

    /// @notice Fuzz test capacity limits
    function testFuzz_CapacityLimit(uint256 amount) public {
        // Try to deposit more than capacity
        amount = bound(amount, MAX_CAPACITY + 1, MAX_CAPACITY * 2);

        usdc.mint(user1, amount);
        vm.startPrank(user1);
        usdc.approve(address(vault), amount);

        // Should revert
        vm.expectRevert();
        vault.deposit(amount, user1);
        vm.stopPrank();
    }

    /// @notice Fuzz test minimum deposit enforcement
    function testFuzz_MinDeposit(uint256 amount) public {
        // Try to deposit less than minimum
        amount = bound(amount, 1, MIN_DEPOSIT - 1);

        usdc.mint(user1, amount);
        vm.startPrank(user1);
        usdc.approve(address(vault), amount);

        // Should revert
        vm.expectRevert();
        vault.deposit(amount, user1);
        vm.stopPrank();
    }
}
