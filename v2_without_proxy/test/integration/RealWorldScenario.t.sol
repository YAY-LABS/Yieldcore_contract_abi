// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {BaseTest} from "../unit/BaseTest.sol";

/// @title RealWorldScenario
/// @notice 5 users, 3-month term with share transfers - real world scenario test
contract RealWorldScenarioTest is BaseTest {
    RWAVault public vault;

    address public alice;
    address public bob;
    address public charlie;
    address public dave;
    address public eve;

    uint256 constant ALICE_DEPOSIT = 100_000e6;   // 100k USDC
    uint256 constant BOB_DEPOSIT = 50_000e6;      // 50k USDC
    uint256 constant CHARLIE_DEPOSIT = 200_000e6; // 200k USDC
    uint256 constant DAVE_DEPOSIT = 0;            // Dave buys in secondary market
    uint256 constant EVE_DEPOSIT = 150_000e6;     // 150k USDC

    uint256 constant APY = 1500; // 15%

    function setUp() public override {
        super.setUp();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");
        eve = makeAddr("eve");

        // Create 3-month vault
        vault = RWAVault(_createVaultWithParams(
            7 days,      // collectionDuration
            90 days,     // termDuration (3 months)
            APY          // fixedAPY
        ));

        usdc.mint(alice, ALICE_DEPOSIT);
        usdc.mint(bob, BOB_DEPOSIT);
        usdc.mint(charlie, CHARLIE_DEPOSIT);
        usdc.mint(eve, EVE_DEPOSIT);
    }

    function test_realWorldScenario_5Users_3Months() public {
        console2.log("=====================================");
        console2.log("   5 Users, 3 Month Term Scenario");
        console2.log("=====================================");

        // === PHASE 1: DEPOSITS ===
        console2.log("");
        console2.log("=== PHASE 1: DEPOSITS ===");

        vm.startPrank(alice);
        usdc.approve(address(vault), ALICE_DEPOSIT);
        vault.deposit(ALICE_DEPOSIT, alice);
        vm.stopPrank();
        console2.log("Alice deposited:", ALICE_DEPOSIT / 1e6, "USDC");

        vm.startPrank(bob);
        usdc.approve(address(vault), BOB_DEPOSIT);
        vault.deposit(BOB_DEPOSIT, bob);
        vm.stopPrank();
        console2.log("Bob deposited:", BOB_DEPOSIT / 1e6, "USDC");

        vm.startPrank(charlie);
        usdc.approve(address(vault), CHARLIE_DEPOSIT);
        vault.deposit(CHARLIE_DEPOSIT, charlie);
        vm.stopPrank();
        console2.log("Charlie deposited:", CHARLIE_DEPOSIT / 1e6, "USDC");

        vm.startPrank(eve);
        usdc.approve(address(vault), EVE_DEPOSIT);
        vault.deposit(EVE_DEPOSIT, eve);
        vm.stopPrank();
        console2.log("Eve deposited:", EVE_DEPOSIT / 1e6, "USDC");

        console2.log("Dave: No deposit (will buy in secondary market)");

        uint256 totalDeposited = ALICE_DEPOSIT + BOB_DEPOSIT + CHARLIE_DEPOSIT + EVE_DEPOSIT;
        console2.log("Total deposited:", totalDeposited / 1e6, "USDC");

        // === VAULT ACTIVATION ===
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();
        console2.log("");
        console2.log("=== VAULT ACTIVATED ===");

        uint256 totalMonthlyInterest = (totalDeposited * APY) / (12 * 10000);
        uint256 totalInterestNeeded = totalMonthlyInterest * 3;

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), totalInterestNeeded);
        vault.depositInterest(totalInterestNeeded);
        vm.stopPrank();
        console2.log("Interest liquidity deposited:", totalInterestNeeded / 1e6, "USDC");

        _printAllUsersStatus("INITIAL STATE (After Activation)");

        // === PHASE 2: AFTER 1 MONTH ===
        console2.log("");
        console2.log("=== PHASE 2: AFTER 1 MONTH ===");

        vm.warp(vault.interestPaymentDates(0) + 1);
        console2.log("Time warped to: Payment Date 1 + 1 second");

        // Alice claims 1 month interest
        uint256 aliceClaimed1;
        {
            uint256 balBefore = usdc.balanceOf(alice);
            vm.prank(alice);
            vault.claimInterest();
            aliceClaimed1 = usdc.balanceOf(alice) - balBefore;
            console2.log("");
            console2.log("[Alice] Claimed 1 month interest:", aliceClaimed1 / 1e6, "USDC");
        }

        // Bob transfers 50% shares to Charlie (without claiming)
        {
            uint256 bobShares = vault.balanceOf(bob);
            uint256 transferAmount = bobShares / 2;

            vm.prank(bob);
            vault.transfer(charlie, transferAmount);
            console2.log("[Bob -> Charlie] Transferred", transferAmount / 1e6, "shares (50%)");
        }

        _printAllUsersStatus("After Month 1 Actions");

        // === PHASE 3: AFTER 2 MONTHS ===
        console2.log("");
        console2.log("=== PHASE 3: AFTER 2 MONTHS ===");

        vm.warp(vault.interestPaymentDates(1) + 1);
        console2.log("Time warped to: Payment Date 2 + 1 second");

        // Alice claims month 2 interest then transfers all shares to Dave
        uint256 aliceClaimed2;
        {
            uint256 balBefore = usdc.balanceOf(alice);
            vm.prank(alice);
            vault.claimInterest();
            aliceClaimed2 = usdc.balanceOf(alice) - balBefore;
            console2.log("");
            console2.log("[Alice] Claimed month 2 interest:", aliceClaimed2 / 1e6, "USDC");

            uint256 aliceShares = vault.balanceOf(alice);
            vm.prank(alice);
            vault.transfer(dave, aliceShares);
            console2.log("[Alice -> Dave] Transferred ALL shares:", aliceShares / 1e6);
            console2.log("  (Dave inherits Alice's debt and lastClaimMonth=2)");
        }

        // Eve claims 2 months at once
        uint256 eveClaimed;
        {
            uint256 balBefore = usdc.balanceOf(eve);
            vm.prank(eve);
            vault.claimInterest();
            eveClaimed = usdc.balanceOf(eve) - balBefore;
            console2.log("[Eve] Claimed 2 months interest:", eveClaimed / 1e6, "USDC");
        }

        _printAllUsersStatus("After Month 2 Actions");

        // === PHASE 4: MATURITY ===
        console2.log("");
        console2.log("=== PHASE 4: MATURITY ===");

        vm.warp(vault.interestPaymentDates(2) + 1);
        vm.prank(admin);
        vault.matureVault();
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);
        console2.log("Vault matured and withdrawal enabled");

        _printAllUsersStatus("At Maturity (Before Redemption)");

        // === PHASE 5: REDEMPTIONS ===
        console2.log("");
        console2.log("=== PHASE 5: REDEMPTIONS ===");

        uint256 aliceRedeemed = _redeemAll(alice, "Alice");
        uint256 bobRedeemed = _redeemAll(bob, "Bob");
        uint256 charlieRedeemed = _redeemAll(charlie, "Charlie");
        uint256 daveRedeemed = _redeemAll(dave, "Dave");
        uint256 eveRedeemed = _redeemAll(eve, "Eve");

        // === FINAL SETTLEMENT ===
        console2.log("");
        console2.log("=====================================");
        console2.log("         FINAL SETTLEMENT");
        console2.log("=====================================");

        uint256 aliceTotal = aliceClaimed1 + aliceClaimed2 + aliceRedeemed;
        uint256 bobTotal = bobRedeemed;
        uint256 charlieTotal = charlieRedeemed;
        uint256 daveTotal = daveRedeemed;
        uint256 eveTotal = eveClaimed + eveRedeemed;

        console2.log("");
        console2.log("Alice:");
        console2.log("  Claimed interest:", (aliceClaimed1 + aliceClaimed2) / 1e6, "USDC");
        console2.log("  Redeemed:", aliceRedeemed / 1e6, "USDC");
        console2.log("  TOTAL:", aliceTotal / 1e6, "USDC");

        console2.log("");
        console2.log("Bob:");
        console2.log("  Claimed interest: 0 USDC (never claimed)");
        console2.log("  Redeemed:", bobRedeemed / 1e6, "USDC");
        console2.log("  TOTAL:", bobTotal / 1e6, "USDC");
        console2.log("  (Note: Transferred 50% to Charlie at month 1)");

        console2.log("");
        console2.log("Charlie:");
        console2.log("  Claimed interest: 0 USDC (never claimed)");
        console2.log("  Redeemed:", charlieRedeemed / 1e6, "USDC");
        console2.log("  TOTAL:", charlieTotal / 1e6, "USDC");
        console2.log("  (Note: Original 200k + received 50% of Bob's shares)");

        console2.log("");
        console2.log("Dave:");
        console2.log("  Claimed interest: 0 USDC (bought from Alice)");
        console2.log("  Redeemed:", daveRedeemed / 1e6, "USDC");
        console2.log("  TOTAL:", daveTotal / 1e6, "USDC");
        console2.log("  (Note: Bought Alice's shares after 2mo interest claimed)");

        console2.log("");
        console2.log("Eve:");
        console2.log("  Claimed interest:", eveClaimed / 1e6, "USDC");
        console2.log("  Redeemed:", eveRedeemed / 1e6, "USDC");
        console2.log("  TOTAL:", eveTotal / 1e6, "USDC");

        // === VERIFICATION ===
        console2.log("");
        console2.log("=====================================");
        console2.log("         VERIFICATION");
        console2.log("=====================================");

        uint256 monthlyInterestPer100k = (100_000e6 * APY) / (12 * 10000); // 1,250 USDC

        uint256 aliceExpected = ALICE_DEPOSIT + (monthlyInterestPer100k * 3);
        uint256 bobExpected = (BOB_DEPOSIT / 2) + (monthlyInterestPer100k * 3 / 2 / 2);
        uint256 charlieExpected = CHARLIE_DEPOSIT + (monthlyInterestPer100k * 2 * 3)
            + (BOB_DEPOSIT / 2) + (monthlyInterestPer100k * 3 / 2 / 2);
        uint256 daveExpected = ALICE_DEPOSIT + monthlyInterestPer100k;
        uint256 eveExpected = EVE_DEPOSIT + (monthlyInterestPer100k * 3 * 150 / 100);

        console2.log("");
        console2.log("Alice + Dave combined (original Alice deposit):");
        console2.log("  Expected:", aliceExpected / 1e6, "USDC");
        console2.log("  Actual:", (aliceTotal + daveTotal) / 1e6, "USDC");
        assertApproxEqAbs(aliceTotal + daveTotal, aliceExpected, 100, "Alice+Dave total");

        console2.log("");
        console2.log("Bob + Charlie's Bob portion:");
        uint256 bobPortion = BOB_DEPOSIT + (monthlyInterestPer100k * 3 / 2);
        console2.log("  Expected Bob total value:", bobPortion / 1e6, "USDC");

        console2.log("");
        console2.log("Eve:");
        console2.log("  Expected:", eveExpected / 1e6, "USDC");
        console2.log("  Actual:", eveTotal / 1e6, "USDC");
        assertApproxEqAbs(eveTotal, eveExpected, 100, "Eve total");

        // System check: total payout = total deposited + total interest
        uint256 totalPaidOut = aliceTotal + bobTotal + charlieTotal + daveTotal + eveTotal;
        uint256 expectedTotalPayout = totalDeposited + totalInterestNeeded;

        console2.log("");
        console2.log("SYSTEM CHECK:");
        console2.log("  Total deposited:", totalDeposited / 1e6, "USDC");
        console2.log("  Total interest:", totalInterestNeeded / 1e6, "USDC");
        console2.log("  Expected total payout:", expectedTotalPayout / 1e6, "USDC");
        console2.log("  Actual total payout:", totalPaidOut / 1e6, "USDC");

        assertApproxEqAbs(totalPaidOut, expectedTotalPayout, 1000, "Total system payout");

        console2.log("");
        console2.log("=====================================");
        console2.log("    ALL VERIFICATIONS PASSED!");
        console2.log("=====================================");
    }

    function _printAllUsersStatus(string memory phase) internal view {
        console2.log("");
        console2.log("--- Status:", phase, "---");
        console2.log("Share price (per 1e6):", vault.convertToAssets(1e6));
        console2.log("");

        _printUserStatus(alice, "Alice");
        _printUserStatus(bob, "Bob");
        _printUserStatus(charlie, "Charlie");
        _printUserStatus(dave, "Dave");
        _printUserStatus(eve, "Eve");
    }

    function _printUserStatus(address user, string memory name) internal view {
        (
            uint256 shares,
            uint256 grossValue,
            uint256 claimedInterest,
            uint256 netValue,
            uint256 lastClaimMonth
        ) = vault.getShareInfo(user);

        if (shares == 0 && grossValue == 0) {
            console2.log(name, ": No shares");
            return;
        }

        console2.log(name, ":");
        console2.log("  shares:", shares / 1e6);
        console2.log("  grossValue:", grossValue / 1e6, "USDC");
        console2.log("  claimedInterest (debt):", claimedInterest / 1e6, "USDC");
        console2.log("  netValue:", netValue / 1e6, "USDC");
        console2.log("  lastClaimMonth:", lastClaimMonth);
    }

    function _redeemAll(address user, string memory name) internal returns (uint256 received) {
        uint256 shares = vault.balanceOf(user);
        if (shares == 0) {
            console2.log(name, ": No shares to redeem");
            return 0;
        }

        uint256 balBefore = usdc.balanceOf(user);
        vm.prank(user);
        vault.redeem(shares, user, user);
        received = usdc.balanceOf(user) - balBefore;
        console2.log(name, "redeemed:", received / 1e6, "USDC");
    }
}
