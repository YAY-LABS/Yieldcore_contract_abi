// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "../unit/BaseTest.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../src/libraries/RWAErrors.sol";

/// @title AdvancedAttackTest
/// @notice Advanced attack scenario tests for security verification
contract AdvancedAttackTest is BaseTest {
    RWAVault public vault;

    address public attacker = makeAddr("attacker");
    address public victim1 = makeAddr("victim1");
    address public victim2 = makeAddr("victim2");
    address public whale = makeAddr("whale");

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());

        usdc.mint(attacker, 10_000_000e6);
        usdc.mint(victim1, 1_000_000e6);
        usdc.mint(victim2, 1_000_000e6);
        usdc.mint(whale, 100_000_000e6);
    }

    // ============================================================================
    // DEFAULT PHASE ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Attempt large deposit just before default
    function test_Attack_DepositBeforeDefault() public {
        vm.startPrank(victim1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.warp(block.timestamp + 30 days);

        // Attacker tries to deposit in Active phase (should fail)
        vm.startPrank(attacker);
        usdc.approve(address(vault), 1_000_000e6);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.deposit(1_000_000e6, attacker);
        vm.stopPrank();

        // Result: Deposit blocked in Active phase
    }

    /// @notice Scenario: Share transfer after default - no duplicate interest
    function test_Attack_TransferAfterDefault_NoDuplicateInterest() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(victim1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, victim1);
        vm.stopPrank();

        vm.startPrank(victim2);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, victim2);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.warp(block.timestamp + 30 days);
        vm.prank(admin);
        vault.triggerDefault();

        uint256 maturity = vault.maturityTime();
        uint256 totalNeeded = vault.totalAssets();
        vm.startPrank(address(poolManager));
        usdc.mint(address(poolManager), totalNeeded);
        usdc.approve(address(vault), totalNeeded);
        vault.depositInterest(totalNeeded - vault.totalPrincipal());
        vm.stopPrank();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);

        vm.warp(maturity);

        uint256 vaultBalanceBefore = usdc.balanceOf(address(vault));

        uint256 victim1Shares = vault.balanceOf(victim1);
        vm.prank(victim1);
        vault.transfer(attacker, victim1Shares);

        vm.startPrank(attacker);
        uint256 attackerShares = vault.balanceOf(attacker);
        uint256 attackerReceived = vault.redeem(attackerShares, attacker, attacker);
        vm.stopPrank();

        vm.startPrank(victim2);
        uint256 victim2Shares = vault.balanceOf(victim2);
        uint256 victim2Received = vault.redeem(victim2Shares, victim2, victim2);
        vm.stopPrank();

        uint256 totalWithdrawn = attackerReceived + victim2Received;
        assertLe(totalWithdrawn, vaultBalanceBefore, "Total withdrawn exceeds vault balance!");

        console2.log("Vault balance before:", vaultBalanceBefore);
        console2.log("Attacker received:", attackerReceived);
        console2.log("Victim2 received:", victim2Received);
        console2.log("Total withdrawn:", totalWithdrawn);
    }

    /// @notice Scenario: Claim + redeem combination after default
    function test_Attack_ClaimThenRedeemAfterDefault() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(victim1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.warp(block.timestamp + 34 days);

        vm.prank(admin);
        vault.triggerDefault();

        uint256 totalNeeded = vault.totalAssets();
        uint256 currentBalance = usdc.balanceOf(address(vault));
        uint256 needToDeposit = totalNeeded > currentBalance ? totalNeeded - currentBalance + 1e6 : 0;

        vm.startPrank(address(poolManager));
        usdc.mint(address(poolManager), needToDeposit);
        usdc.approve(address(vault), needToDeposit);
        if (needToDeposit > 0) {
            vault.depositInterest(needToDeposit);
        }
        vm.stopPrank();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);

        vm.warp(maturity);

        uint256 balanceBefore = usdc.balanceOf(victim1);
        uint256 sharesBefore = vault.balanceOf(victim1);

        vm.startPrank(victim1);
        vault.claimInterest();

        uint256 sharesAfterClaim = vault.balanceOf(victim1);
        console2.log("Shares before claim:", sharesBefore);
        console2.log("Shares after claim:", sharesAfterClaim);
        console2.log("Shares burned for interest:", sharesBefore - sharesAfterClaim);

        vault.redeem(sharesAfterClaim, victim1, victim1);
        vm.stopPrank();

        uint256 totalReceived = usdc.balanceOf(victim1) - balanceBefore;
        console2.log("Total received:", totalReceived);
        console2.log("Original deposit:", depositAmount);

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        uint256 expectedMax = depositAmount + (monthlyInterest * 2);
        assertLe(totalReceived, expectedMax, "Received more than expected!");

        uint256 expectedMin = depositAmount + monthlyInterest - 1e6;
        assertGe(totalReceived, expectedMin, "Received less than expected!");
    }

    // ============================================================================
    // SHARE TRANSFER ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Attempt double claim after share transfer
    function test_Attack_DoubleClaim_AfterTransfer() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(victim1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 2);
        vault.depositInterest(monthlyInterest * 2);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days);

        vm.prank(victim1);
        vault.claimInterest();

        uint256 halfShares = vault.balanceOf(victim1) / 2;
        vm.prank(victim1);
        vault.transfer(attacker, halfShares);

        // victim1 tries to claim again (should fail - already claimed)
        vm.prank(victim1);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();

        // attacker tries to claim (should fail - inherited lastClaimMonth)
        vm.prank(attacker);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();

        // Result: lastClaimMonth transfer prevents double claim
    }

    /// @notice Scenario: Transfer before claim to avoid interest
    function test_Attack_TransferBeforeClaim() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(attacker);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, attacker);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest);
        vault.depositInterest(monthlyInterest);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days);

        // Attacker transfers shares before claiming
        uint256 shares = vault.balanceOf(attacker);
        vm.prank(attacker);
        vault.transfer(victim1, shares);

        // victim1 can claim the interest
        vm.prank(victim1);
        vault.claimInterest();

        // Attacker has no shares - cannot claim
        vm.prank(attacker);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();

        // Result: Receiver gets the interest (normal behavior)
    }

    // ============================================================================
    // PHASE TRANSITION ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Last-minute large deposit dilution attack
    function test_Attack_LastMinuteDeposit_Dilution() public {
        vm.startPrank(victim1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim1);
        vm.stopPrank();

        vm.startPrank(victim2);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim2);
        vm.stopPrank();

        // Whale deposits just before collection ends
        vm.warp(block.timestamp + 7 days - 1);
        vm.startPrank(whale);
        usdc.approve(address(vault), 9_000_000e6);
        vault.deposit(9_000_000e6, whale);
        vm.stopPrank();

        vm.warp(block.timestamp + 2);
        vm.prank(admin);
        vault.activateVault();

        uint256 victim1Shares = vault.balanceOf(victim1);
        uint256 victim2Shares = vault.balanceOf(victim2);
        uint256 whaleShares = vault.balanceOf(whale);
        uint256 totalShares = vault.totalSupply();

        console2.log("Victim1 shares:", victim1Shares);
        console2.log("Victim2 shares:", victim2Shares);
        console2.log("Whale shares:", whaleShares);
        console2.log("Total shares:", totalShares);

        // Shares should be proportional to deposit (1:1 initial)
        assertEq(victim1Shares, 100_000e6, "Victim1 should have proportional shares");
        assertEq(whaleShares, 9_000_000e6, "Whale should have proportional shares");

        // Result: No dilution attack possible in Collection phase (1:1 ratio)
    }

    /// @notice Scenario: Race condition around activateVault
    function test_Attack_ActivateRaceCondition() public {
        vm.startPrank(victim1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // Try deposit after collection ends (should fail)
        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);
        vm.expectRevert(RWAErrors.CollectionEnded.selector);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();

        vm.prank(admin);
        vault.activateVault();

        // Try deposit in Active phase (should fail)
        vm.startPrank(attacker);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();
    }

    // ============================================================================
    // INTEREST CALCULATION ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Precision attack at interest period boundary
    function test_Attack_InterestBoundaryPrecision() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(victim1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 interestStart = vault.interestStartTime();

        // Just before period boundary
        vm.warp(interestStart + 30 days - 1);
        uint256 assetsBefore = vault.totalAssets();

        // Just after period boundary
        vm.warp(interestStart + 30 days + 1);
        uint256 assetsAfter = vault.totalAssets();

        console2.log("Assets at 29d 23h 59m 59s:", assetsBefore);
        console2.log("Assets at 30d 0h 0m 1s:", assetsAfter);

        // No sudden jump at boundary
        uint256 diff = assetsAfter > assetsBefore ? assetsAfter - assetsBefore : assetsBefore - assetsAfter;
        assertLt(diff, 100e6, "Interest jump at boundary should be minimal");
    }

    /// @notice Scenario: Precision loss with small amounts
    function test_Attack_SmallAmountPrecisionLoss() public {
        // Min deposit
        vm.startPrank(attacker);
        usdc.approve(address(vault), 100e6);
        vault.deposit(100e6, attacker);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.warp(block.timestamp + 180 days);

        uint256 totalAssets = vault.totalAssets();
        uint256 expectedInterest = (100e6 * 1500 * 6) / (12 * 10_000);

        uint256 principal = 100e6;
        console2.log("Total assets:", totalAssets);
        console2.log("Principal:", principal);
        console2.log("Expected interest (6 months):", expectedInterest);

        // Interest should accrue even for small amounts
        assertGt(totalAssets, 100e6, "Interest should accrue even for small amounts");
    }

    // ============================================================================
    // CAP ALLOCATION ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Attempt to bypass allocated cap
    function test_Attack_BypassAllocatedCap() public {
        vm.prank(admin);
        vault.allocateCap(attacker, 50_000e6);

        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(50_000e6, attacker);

        // Try to exceed allocation (should fail)
        vm.expectRevert(RWAErrors.ExceedsUserDepositCap.selector);
        vault.deposit(100e6, attacker);
        vm.stopPrank();

        // Different address uses public pool
        address attacker2 = makeAddr("attacker2");
        usdc.mint(attacker2, 100_000e6);

        vm.startPrank(attacker2);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, attacker2); // Success (public pool)
        vm.stopPrank();

        // Result: Allocation applies only to specific address
    }

    /// @notice Scenario: Transfer to bypass cap after allocation
    function test_Attack_TransferToBypassCap() public {
        vm.prank(admin);
        vault.allocateCap(attacker, 10_000e6);

        vm.startPrank(attacker);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, attacker);
        vm.stopPrank();

        vm.startPrank(victim1);
        usdc.approve(address(vault), 500_000e6);
        vault.deposit(500_000e6, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // victim1 transfers shares to attacker
        uint256 victim1Shares = vault.balanceOf(victim1);
        vm.prank(victim1);
        vault.transfer(attacker, victim1Shares);

        uint256 attackerShares = vault.balanceOf(attacker);
        console2.log("Attacker total shares:", attackerShares);

        // Post-collection transfers allowed (secondary market)
        assertEq(attackerShares, 10_000e6 + 500_000e6, "Attacker should have all transferred shares");
    }

    // ============================================================================
    // MULTI-USER COMPLEX SCENARIOS
    // ============================================================================

    /// @notice Scenario: Complex multi-user interaction
    function test_Scenario_ComplexMultiUser() public {
        address[] memory users = new address[](5);
        uint256[] memory deposits = new uint256[](5);

        users[0] = makeAddr("complexUser0");
        users[1] = makeAddr("complexUser1");
        users[2] = makeAddr("complexUser2");
        users[3] = makeAddr("complexUser3");
        users[4] = makeAddr("complexUser4");

        deposits[0] = 100_000e6;
        deposits[1] = 250_000e6;
        deposits[2] = 100_000e6;
        deposits[3] = 300_000e6;
        deposits[4] = 175_000e6;

        uint256 totalDeposit = 0;

        uint256[] memory initialBalances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            usdc.mint(users[i], deposits[i]);
            initialBalances[i] = 0;
            vm.startPrank(users[i]);
            usdc.approve(address(vault), deposits[i]);
            vault.deposit(deposits[i], users[i]);
            vm.stopPrank();
            totalDeposit += deposits[i];
        }

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 totalMonthlyInterest = (totalDeposit * 1500) / (12 * 10_000);
        uint256 interestToDeposit = totalMonthlyInterest * 3;
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), interestToDeposit);
        vault.depositInterest(interestToDeposit);
        vm.stopPrank();

        // After 1 month: user0, user1 claim
        vm.warp(block.timestamp + 34 days);

        vm.prank(users[0]);
        vault.claimInterest();

        vm.prank(users[1]);
        vault.claimInterest();

        // user2 transfers half shares to user3
        uint256 user2Shares = vault.balanceOf(users[2]);
        vm.prank(users[2]);
        vault.transfer(users[3], user2Shares / 2);

        // After 2 months: user3, user4 claim
        vm.warp(block.timestamp + 34 days);

        vm.prank(users[3]);
        vault.claimInterest();

        vm.prank(users[4]);
        vault.claimInterest();

        // Trigger default
        vm.prank(admin);
        vault.triggerDefault();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);

        vm.warp(maturity);

        // All users redeem
        uint256 totalReceived = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 shares = vault.balanceOf(users[i]);
            if (shares > 0) {
                vm.prank(users[i]);
                uint256 received = vault.redeem(shares, users[i], users[i]);
                console2.log("User", i, "redeem received:", received);
            }
            uint256 userTotal = usdc.balanceOf(users[i]);
            totalReceived += userTotal;
            console2.log("User", i, "total balance:", userTotal);
        }

        uint256 vaultRemaining = usdc.balanceOf(address(vault));
        console2.log("Total received by users:", totalReceived);
        console2.log("Vault remaining:", vaultRemaining);
        console2.log("Total deposited (principal + interest):", totalDeposit + interestToDeposit);

        // === SECURITY ASSERTIONS ===

        // Fund conservation
        uint256 totalAccounted = totalReceived + vaultRemaining;
        uint256 totalInVault = totalDeposit + interestToDeposit;
        assertEq(totalAccounted, totalInVault, "CRITICAL: Fund conservation violated");

        // No user receives more than entitled
        for (uint256 i = 0; i < 5; i++) {
            uint256 userBalance = usdc.balanceOf(users[i]);
            uint256 userPrincipal = deposits[i];
            if (i == 2) {
                userPrincipal = deposits[2] / 2;
            } else if (i == 3) {
                userPrincipal = deposits[3] + (deposits[2] / 2);
            }
            uint256 maxExpected = (userPrincipal * 115) / 100; // principal + max 15% (1 year)
            assertLe(userBalance, maxExpected, "CRITICAL: User received more than entitled");
        }

        // Vault balance should not have large stuck amount
        uint256 maxAcceptableRemaining = totalDeposit / 10;
        assertLe(vaultRemaining, maxAcceptableRemaining, "Warning: Large amount stuck in vault");

        // Users should receive at least 90% of principal
        assertGe(totalReceived, (totalDeposit * 90) / 100, "Warning: Users received significantly less");
    }

    // ============================================================================
    // WITHDRAWAL TIMING ATTACK SCENARIOS
    // ============================================================================

    /// @notice Scenario: Withdraw before withdrawalStartTime
    function test_Attack_WithdrawBeforeStartTime() public {
        vm.startPrank(victim1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Before maturity (Active phase)
        vm.warp(block.timestamp + 170 days);
        vm.startPrank(victim1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.redeem(100_000e6, victim1, victim1);
        vm.stopPrank();

        // After maturity
        vm.warp(block.timestamp + 11 days);
        vm.prank(admin);
        vault.matureVault();

        uint256 maturity = vault.maturityTime();

        // Admin sets future withdrawalStartTime
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity + 7 days);

        // Deposit interest
        uint256 totalNeeded = vault.totalAssets();
        uint256 currentBalance = usdc.balanceOf(address(vault));
        uint256 needToDeposit = totalNeeded > currentBalance ? totalNeeded - currentBalance + 1e6 : 0;

        vm.startPrank(address(poolManager));
        usdc.mint(address(poolManager), needToDeposit);
        usdc.approve(address(vault), needToDeposit);
        if (needToDeposit > 0) {
            vault.depositInterest(needToDeposit);
        }
        vm.stopPrank();

        // Before withdrawalStartTime (should fail)
        vm.startPrank(victim1);
        vm.expectRevert(RWAErrors.WithdrawalNotAvailable.selector);
        vault.redeem(100_000e6, victim1, victim1);
        vm.stopPrank();

        // After withdrawalStartTime
        vm.warp(maturity + 7 days);

        vm.startPrank(victim1);
        vault.redeem(vault.balanceOf(victim1), victim1, victim1);
        vm.stopPrank();

        uint256 balance = usdc.balanceOf(victim1);
        assertGt(balance, 100_000e6, "Should receive principal + interest");
    }

    // ============================================================================
    // EDGE CASE: ZERO AND MAX VALUES
    // ============================================================================

    /// @notice Scenario: Deposit exactly to max capacity
    function test_EdgeCase_ExactMaxCapacity() public {
        uint256 maxCap = vault.maxCapacity();

        vm.startPrank(whale);
        usdc.approve(address(vault), maxCap);
        vault.deposit(maxCap, whale);
        vm.stopPrank();

        // Additional deposit should fail
        vm.startPrank(attacker);
        usdc.approve(address(vault), 100e6);
        vm.expectRevert(RWAErrors.VaultCapacityExceeded.selector);
        vault.deposit(100e6, attacker);
        vm.stopPrank();

        assertEq(vault.totalAssets(), maxCap, "Should be exactly at max capacity");
    }

    /// @notice Scenario: Zero share operations
    function test_EdgeCase_ZeroSharesOperations() public {
        vm.startPrank(victim1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, victim1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Attacker with no shares tries claimInterest
        vm.prank(attacker);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();

        vm.warp(block.timestamp + 180 days);
        vm.prank(admin);
        vault.matureVault();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);

        vm.warp(maturity);

        // Attacker with no shares tries redeem
        vm.startPrank(attacker);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.redeem(1, attacker, attacker);
        vm.stopPrank();
    }

    // ============================================================================
    // SECONDARY MARKET SCENARIOS
    // ============================================================================

    /// @notice Secondary market 1: Seller claimed interest before transfer, then default
    function test_SecondaryMarket_DefaultAfterTransfer_SellerClaimedInterest() public {
        address seller = makeAddr("seller");
        address buyer = makeAddr("buyer");
        uint256 depositAmount = 100_000e6;

        usdc.mint(seller, depositAmount);

        vm.startPrank(seller);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, seller);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 4);
        vault.depositInterest(monthlyInterest * 4);
        vm.stopPrank();

        // Month 1: seller claims
        vm.warp(block.timestamp + 34 days);
        vm.prank(seller);
        vault.claimInterest();
        uint256 sellerAfterClaim1 = usdc.balanceOf(seller);
        console2.log("Seller after 1st claim:", sellerAfterClaim1);

        // Month 2: seller claims
        vm.warp(block.timestamp + 30 days);
        vm.prank(seller);
        vault.claimInterest();
        uint256 sellerAfterClaim2 = usdc.balanceOf(seller);
        console2.log("Seller after 2nd claim:", sellerAfterClaim2);

        // Seller transfers to buyer
        uint256 sellerShares = vault.balanceOf(seller);
        console2.log("Seller shares before transfer:", sellerShares);
        vm.prank(seller);
        vault.transfer(buyer, sellerShares);

        // Default
        vm.prank(admin);
        vault.triggerDefault();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);
        vm.warp(maturity);

        // Buyer redeems
        uint256 buyerShares = vault.balanceOf(buyer);
        vm.prank(buyer);
        uint256 buyerReceived = vault.redeem(buyerShares, buyer, buyer);

        console2.log("=== RESULT ===");
        console2.log("Seller total received (claims):", sellerAfterClaim2);
        console2.log("Buyer received (redeem):", buyerReceived);
        console2.log("Combined:", sellerAfterClaim2 + buyerReceived);
        console2.log("Original deposit:", depositAmount);

        // Seller: ~2 months interest
        assertGe(sellerAfterClaim2, monthlyInterest * 2 - 1e6, "Seller should receive ~2 months interest");
        assertLe(sellerAfterClaim2, monthlyInterest * 2 + 1e6, "Seller should not receive more than 2 months");

        // Buyer: close to principal (interest already claimed)
        assertGe(buyerReceived, depositAmount * 90 / 100, "Buyer should receive close to principal");
    }

    /// @notice Secondary market 2: Seller never claimed before transfer, then default
    function test_SecondaryMarket_DefaultAfterTransfer_SellerNeverClaimed() public {
        address seller = makeAddr("seller2");
        address buyer = makeAddr("buyer2");
        uint256 depositAmount = 100_000e6;

        usdc.mint(seller, depositAmount);

        vm.startPrank(seller);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, seller);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 4);
        vault.depositInterest(monthlyInterest * 4);
        vm.stopPrank();

        // 2 months pass (seller doesn't claim)
        vm.warp(block.timestamp + 64 days);

        // Seller transfers without claiming
        uint256 sellerShares = vault.balanceOf(seller);
        console2.log("Seller shares (no claim):", sellerShares);
        vm.prank(seller);
        vault.transfer(buyer, sellerShares);

        uint256 sellerBalance = usdc.balanceOf(seller);
        console2.log("Seller USDC after transfer:", sellerBalance);

        // Default
        vm.prank(admin);
        vault.triggerDefault();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);
        vm.warp(maturity);

        // Buyer redeems
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 buyerShares = vault.balanceOf(buyer);
        vm.prank(buyer);
        vault.redeem(buyerShares, buyer, buyer);
        uint256 buyerTotal = usdc.balanceOf(buyer) - buyerBalanceBefore;

        console2.log("=== RESULT ===");
        console2.log("Seller received:", sellerBalance);
        console2.log("Buyer total received:", buyerTotal);
        console2.log("Original deposit:", depositAmount);

        // Seller: 0 (no claim)
        assertEq(sellerBalance, 0, "Seller should receive nothing (no claim before transfer)");

        // Buyer: principal + accrued interest
        assertGe(buyerTotal, depositAmount, "Buyer should receive at least principal");
    }

    /// @notice Secondary market 3: Normal maturity with seller claimed interest
    function test_SecondaryMarket_NormalMaturity_SellerClaimedInterest() public {
        address seller = makeAddr("seller3");
        address buyer = makeAddr("buyer3");
        uint256 depositAmount = 100_000e6;

        usdc.mint(seller, depositAmount);

        vm.startPrank(seller);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, seller);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 6);
        vault.depositInterest(monthlyInterest * 6);
        vm.stopPrank();

        // 3 months: seller claims each month
        for (uint256 i = 1; i <= 3; i++) {
            vm.warp(block.timestamp + 34 days);
            vm.prank(seller);
            vault.claimInterest();
        }
        uint256 sellerClaimedTotal = usdc.balanceOf(seller);
        console2.log("Seller claimed (3 months):", sellerClaimedTotal);

        // Seller transfers to buyer
        uint256 sellerShares = vault.balanceOf(seller);
        console2.log("Seller remaining shares after claims:", sellerShares);
        vm.prank(seller);
        vault.transfer(buyer, sellerShares);

        // Wait until maturity
        vm.warp(block.timestamp + 92 days);
        vm.prank(admin);
        vault.matureVault();

        uint256 maturity = vault.maturityTime();
        vm.warp(maturity);

        // Buyer redeems
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 buyerShares = vault.balanceOf(buyer);
        vm.prank(buyer);
        vault.redeem(buyerShares, buyer, buyer);
        uint256 buyerTotal = usdc.balanceOf(buyer) - buyerBalanceBefore;

        console2.log("=== RESULT ===");
        console2.log("Seller claimed (3 months interest):", sellerClaimedTotal);
        console2.log("Buyer total received:", buyerTotal);
        console2.log("Combined:", sellerClaimedTotal + buyerTotal);
        console2.log("Expected total (principal + 6mo interest):", depositAmount + monthlyInterest * 6);

        // Seller: ~3 months interest
        assertGe(sellerClaimedTotal, monthlyInterest * 3 - 1e6, "Seller should have ~3 months interest");

        // Buyer: close to principal
        assertGe(buyerTotal, depositAmount * 95 / 100, "Buyer should receive close to principal");

        // Combined: principal + most interest
        uint256 combined = sellerClaimedTotal + buyerTotal;
        assertGe(combined, depositAmount + monthlyInterest * 4, "Combined should cover principal + most interest");
    }

    /// @notice Secondary market 4: Normal maturity with seller never claimed
    function test_SecondaryMarket_NormalMaturity_SellerNeverClaimed() public {
        address seller = makeAddr("seller4");
        address buyer = makeAddr("buyer4");
        uint256 depositAmount = 100_000e6;

        usdc.mint(seller, depositAmount);

        vm.startPrank(seller);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, seller);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 6);
        vault.depositInterest(monthlyInterest * 6);
        vm.stopPrank();

        // 3 months pass (seller doesn't claim)
        vm.warp(block.timestamp + 94 days);

        // Seller transfers without claiming
        uint256 sellerShares = vault.balanceOf(seller);
        console2.log("Seller shares (no claim, 3 months):", sellerShares);
        vm.prank(seller);
        vault.transfer(buyer, sellerShares);

        uint256 sellerBalance = usdc.balanceOf(seller);

        // Buyer claims mid-term (month 4)
        vm.warp(block.timestamp + 34 days);
        vm.prank(buyer);
        vault.claimInterest();
        uint256 buyerClaimedMid = usdc.balanceOf(buyer);
        console2.log("Buyer claimed mid-term:", buyerClaimedMid);

        // Wait until maturity
        uint256 maturity = vault.maturityTime();
        vm.warp(maturity + 7 days);
        vm.prank(admin);
        vault.matureVault();

        // Buyer redeems
        uint256 buyerShares = vault.balanceOf(buyer);
        vm.prank(buyer);
        uint256 buyerRedeemed = vault.redeem(buyerShares, buyer, buyer);
        uint256 buyerTotal = usdc.balanceOf(buyer);

        console2.log("=== RESULT ===");
        console2.log("Seller received:", sellerBalance);
        console2.log("Buyer claimed mid-term:", buyerClaimedMid);
        console2.log("Buyer redeemed:", buyerRedeemed);
        console2.log("Buyer total:", buyerTotal);
        console2.log("Expected total (principal + 6mo interest):", depositAmount + monthlyInterest * 6);

        // Seller: 0 (no claim)
        assertEq(sellerBalance, 0, "Seller should receive nothing");

        // Buyer: principal + all 6 months interest
        uint256 expectedTotal = depositAmount + monthlyInterest * 6;
        assertGe(buyerTotal, expectedTotal - 1e6, "Buyer should receive all principal + interest");
    }

    /// @notice Secondary market 5: Partial transfer - both receive
    function test_SecondaryMarket_PartialTransfer_BothReceive() public {
        address seller = makeAddr("seller5");
        address buyer = makeAddr("buyer5");
        uint256 depositAmount = 100_000e6;

        usdc.mint(seller, depositAmount);

        vm.startPrank(seller);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, seller);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 6);
        vault.depositInterest(monthlyInterest * 6);
        vm.stopPrank();

        // 2 months: seller claims
        vm.warp(block.timestamp + 64 days);
        vm.prank(seller);
        vault.claimInterest();
        uint256 sellerClaimedInterest = usdc.balanceOf(seller);
        console2.log("Seller claimed (2 months):", sellerClaimedInterest);

        // Seller transfers 50% shares
        uint256 sellerShares = vault.balanceOf(seller);
        uint256 transferAmount = sellerShares / 2;
        console2.log("Seller shares before partial transfer:", sellerShares);
        console2.log("Transfer amount (50%):", transferAmount);

        vm.prank(seller);
        vault.transfer(buyer, transferAmount);

        // Maturity
        vm.warp(block.timestamp + 120 days);
        vm.prank(admin);
        vault.matureVault();

        uint256 maturity = vault.maturityTime();
        vm.warp(maturity);

        // Seller redeems (remaining 50%)
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        uint256 sellerRemainingShares = vault.balanceOf(seller);
        vm.prank(seller);
        vault.redeem(sellerRemainingShares, seller, seller);
        uint256 sellerTotal = usdc.balanceOf(seller);
        uint256 sellerRedeemed = sellerTotal - sellerBalanceBefore;

        // Buyer redeems
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        uint256 buyerShares = vault.balanceOf(buyer);
        vm.prank(buyer);
        vault.redeem(buyerShares, buyer, buyer);
        uint256 buyerTotal = usdc.balanceOf(buyer) - buyerBalanceBefore;

        console2.log("=== RESULT ===");
        console2.log("Seller claimed interest:", sellerClaimedInterest);
        console2.log("Seller redeemed:", sellerRedeemed);
        console2.log("Seller total:", sellerTotal);
        console2.log("Buyer total:", buyerTotal);
        console2.log("Combined:", sellerTotal + buyerTotal);

        // Both should receive something
        assertGt(sellerTotal, 0, "Seller should receive something");
        assertGt(buyerTotal, 0, "Buyer should receive something");

        // Seller: interest + portion of principal
        assertGe(sellerTotal, sellerClaimedInterest + depositAmount / 4, "Seller should get claimed interest + portion");

        // Buyer: portion of principal + remaining interest
        assertGe(buyerTotal, depositAmount / 4, "Buyer should get at least quarter of principal");

        // Fund conservation
        uint256 combined = sellerTotal + buyerTotal;
        assertGe(combined, depositAmount, "Combined should be at least principal");
    }

    /// @notice Secondary market 6: Chained transfer A -> B -> C
    function test_SecondaryMarket_ChainedTransfer_ABC() public {
        address userA = makeAddr("userA");
        address userB = makeAddr("userB");
        address userC = makeAddr("userC");
        uint256 depositAmount = 100_000e6;

        usdc.mint(userA, depositAmount);

        vm.startPrank(userA);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, userA);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (depositAmount * 1500) / (12 * 10_000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 6);
        vault.depositInterest(monthlyInterest * 6);
        vm.stopPrank();

        // Month 1: A claims
        vm.warp(block.timestamp + 34 days);
        vm.prank(userA);
        vault.claimInterest();
        uint256 userAClaimed = usdc.balanceOf(userA);
        console2.log("A claimed (1 month):", userAClaimed);

        // A -> B transfer
        uint256 aShares = vault.balanceOf(userA);
        console2.log("A shares after claim:", aShares);
        vm.prank(userA);
        vault.transfer(userB, aShares);

        // Month 2: B claims
        vm.warp(block.timestamp + 30 days);
        vm.prank(userB);
        vault.claimInterest();
        uint256 userBClaimed = usdc.balanceOf(userB);
        console2.log("B claimed (1 month, since lastClaimMonth=1):", userBClaimed);

        // B -> C transfer
        uint256 bShares = vault.balanceOf(userB);
        console2.log("B shares after claim:", bShares);
        vm.prank(userB);
        vault.transfer(userC, bShares);

        // Maturity
        vm.warp(block.timestamp + 120 days);
        vm.prank(admin);
        vault.matureVault();

        uint256 maturity = vault.maturityTime();
        vm.warp(maturity);

        // C redeems
        uint256 cBalanceBefore = usdc.balanceOf(userC);
        uint256 cShares = vault.balanceOf(userC);
        vm.prank(userC);
        vault.redeem(cShares, userC, userC);
        uint256 userCTotal = usdc.balanceOf(userC) - cBalanceBefore;

        console2.log("=== RESULT ===");
        console2.log("A claimed:", userAClaimed);
        console2.log("B claimed:", userBClaimed);
        console2.log("C total received:", userCTotal);
        console2.log("Combined:", userAClaimed + userBClaimed + userCTotal);

        // A: ~1 month interest
        assertGe(userAClaimed, monthlyInterest - 1e5, "A should get ~1 month interest");

        // B: ~1 month interest
        assertGe(userBClaimed, monthlyInterest - 1e5, "B should get ~1 month interest");

        // C: close to principal + remaining interest
        assertGe(userCTotal, depositAmount * 90 / 100, "C should get close to principal");

        // Fund conservation
        uint256 combined = userAClaimed + userBClaimed + userCTotal;
        assertGe(combined, depositAmount, "Combined should be at least principal");

        // No excess
        uint256 maxTotal = depositAmount + monthlyInterest * 6 + 1e6;
        assertLe(combined, maxTotal, "Combined should not exceed total possible");
    }
}
