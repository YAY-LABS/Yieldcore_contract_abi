// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../src/vault/RWAVault.sol";
import "../../src/interfaces/IRWAVault.sol";
import "../unit/BaseTest.sol";

/// @title InterestVerificationTest
/// @notice Interest calculation and share value verification tests
contract InterestVerificationTest is BaseTest {
    RWAVault public vault;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 constant DEPOSIT_AMOUNT = 100_000e6; // 100,000 USDC
    uint256 constant APY = 1500; // 15%

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());

        usdc.mint(alice, DEPOSIT_AMOUNT * 10);
        usdc.mint(bob, DEPOSIT_AMOUNT * 10);
        usdc.mint(charlie, DEPOSIT_AMOUNT * 10);
    }

    /// @notice Case 1: Claiming exactly on payment date should yield 1 month interest
    function test_exactMonthlyInterestOnPaymentDate() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // 100,000 * 1500 / 12 / 10000 = 1,250 USDC
        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);
        console2.log("Expected monthly interest:", expectedMonthlyInterest);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        uint256 paymentDate1 = vault.interestPaymentDates(0);
        vm.warp(paymentDate1);

        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vault.claimInterest();

        uint256 received = usdc.balanceOf(alice) - balanceBefore;
        console2.log("Actually received:", received);
        console2.log("Difference:", int256(received) - int256(expectedMonthlyInterest));

        assertEq(received, expectedMonthlyInterest, "Should receive exactly 1 month interest");
    }

    /// @notice Case 2: Cannot claim before payment date
    function test_cannotClaimBeforePaymentDate() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 periodEnd1 = vault.interestPeriodEndDates(0);
        vm.warp(periodEnd1);

        uint256 claimable = vault.getClaimableMonths(alice);
        assertEq(claimable, 0, "Should not be claimable before payment date");

        vm.prank(alice);
        vm.expectRevert();
        vault.claimInterest();
    }

    /// @notice Case 3: Claiming after 2 months should yield 2 months interest
    function test_multipleMonthsInterest() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        uint256 paymentDate3 = vault.interestPaymentDates(2);
        vm.warp(paymentDate3);

        uint256 claimable = vault.getClaimableMonths(alice);
        console2.log("Claimable months:", claimable);
        assertEq(claimable, 3, "Should have 3 months claimable");

        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimInterest();

        uint256 received = usdc.balanceOf(alice) - balanceBefore;
        uint256 expected = expectedMonthlyInterest * 3;

        console2.log("Expected (3 months):", expected);
        console2.log("Actually received:", received);

        assertEq(received, expected, "Should receive exactly 3 months interest");
    }

    /// @notice Case 4: Secondary market - seller claimed then transfer
    function test_secondaryMarket_sellerClaimedThenTransfer() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        vm.warp(vault.interestPaymentDates(0));
        vm.prank(alice);
        vault.claimInterest();
        uint256 aliceClaimed1 = expectedMonthlyInterest;

        vm.warp(vault.interestPaymentDates(1));
        vm.prank(alice);
        vault.claimInterest();
        uint256 aliceClaimed2 = expectedMonthlyInterest;

        console2.log("Alice claimed total:", aliceClaimed1 + aliceClaimed2);

        vm.warp(vault.interestPaymentDates(2));
        uint256 aliceShares = vault.balanceOf(alice);
        console2.log("Alice shares before transfer:", aliceShares);

        vm.prank(alice);
        vault.transfer(bob, aliceShares);

        (uint256 bobShares, uint256 bobPrincipal, uint256 bobLastClaim,) = vault.getDepositInfo(bob);
        console2.log("Bob shares:", bobShares);
        console2.log("Bob principal:", bobPrincipal);
        console2.log("Bob lastClaimMonth:", bobLastClaim);

        assertEq(bobLastClaim, 2, "Bob should inherit lastClaimMonth");

        uint256 lastPaymentDate = vault.interestPaymentDates(5);
        vm.warp(lastPaymentDate + 1);
        vm.prank(admin);
        vault.matureVault();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.redeem(vault.balanceOf(bob), bob, bob);
        uint256 bobReceived = usdc.balanceOf(bob) - bobBalanceBefore;

        console2.log("=== RESULTS ===");
        console2.log("Alice claimed:", aliceClaimed1 + aliceClaimed2);
        console2.log("Bob received:", bobReceived);
        console2.log("Total:", aliceClaimed1 + aliceClaimed2 + bobReceived);
        console2.log("Expected total (principal + 6mo interest):", DEPOSIT_AMOUNT + expectedMonthlyInterest * 6);

        uint256 expectedTotal = DEPOSIT_AMOUNT + expectedMonthlyInterest * 6;
        uint256 actualTotal = aliceClaimed1 + aliceClaimed2 + bobReceived;
        assertApproxEqAbs(actualTotal, expectedTotal, 10, "Total should match expected");
    }

    /// @notice Case 5: Secondary market - seller never claimed
    function test_secondaryMarket_sellerNeverClaimed() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        vm.warp(vault.interestPaymentDates(2));

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.transfer(bob, aliceShares);

        (,, uint256 bobLastClaim,) = vault.getDepositInfo(bob);
        assertEq(bobLastClaim, 0, "Bob should inherit lastClaimMonth=0");

        uint256 bobClaimable = vault.getClaimableMonths(bob);
        assertEq(bobClaimable, 3, "Bob should claim all 3 months");

        uint256 bobBalanceBeforeClaim = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.claimInterest();
        uint256 bobClaimed = usdc.balanceOf(bob) - bobBalanceBeforeClaim;

        console2.log("Bob claimed (3 months):", bobClaimed);
        assertEq(bobClaimed, expectedMonthlyInterest * 3, "Bob should receive 3 months interest");

        uint256 lastPaymentDate = vault.interestPaymentDates(5);
        vm.warp(lastPaymentDate + 1);
        vm.prank(admin);
        vault.matureVault();

        uint256 bobBalanceBeforeRedeem = usdc.balanceOf(bob);
        vm.prank(bob);
        uint256 bobRedeemed = vault.redeem(vault.balanceOf(bob), bob, bob);
        uint256 bobReceivedFromRedeem = usdc.balanceOf(bob) - bobBalanceBeforeRedeem;

        console2.log("Bob redeemed:", bobRedeemed);
        console2.log("Bob claimed + redeemed:", bobClaimed + bobReceivedFromRedeem);
        console2.log("Expected:", DEPOSIT_AMOUNT + expectedMonthlyInterest * 6);

        uint256 bobTotal = bobClaimed + bobReceivedFromRedeem;
        assertApproxEqAbs(bobTotal, DEPOSIT_AMOUNT + expectedMonthlyInterest * 6, 10, "Bob should receive all");
    }

    /// @notice Case 6: Default scenario - 1.5 months after activation
    function test_defaultScenario_partialMonth() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 interestStart = vault.interestStartTime();

        // 45 days: 1 complete month + 15 days partial
        uint256 defaultTimestamp = interestStart + 45 days;
        vm.warp(defaultTimestamp);

        uint256 totalAssetsBefore = vault.totalAssets();
        console2.log("Total assets before default:", totalAssetsBefore);

        vm.prank(admin);
        vault.triggerDefault();

        uint256 totalAssetsAfter = vault.totalAssets();
        console2.log("Total assets after default:", totalAssetsAfter);

        // Month 1: 1,250 USDC, Month 2 partial: 625 USDC
        uint256 monthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);
        uint256 expectedInterest = monthlyInterest + (monthlyInterest * 15 / 30);
        console2.log("Expected interest (1.5 months):", expectedInterest);
        console2.log("Expected totalAssets:", DEPOSIT_AMOUNT + expectedInterest);

        assertApproxEqAbs(totalAssetsAfter, DEPOSIT_AMOUNT + expectedInterest, 1e6, "Total assets should match");

        uint256 claimable = vault.getClaimableMonths(alice);
        console2.log("Claimable months after default:", claimable);
        assertEq(claimable, 1, "Should have 1 claimable month");

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), monthlyInterest * 2 + 1e6);
        vault.depositInterest(monthlyInterest * 2 + 1e6);
        vm.stopPrank();

        uint256 maturity = vault.maturityTime();
        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);
        vm.warp(maturity);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(vault.balanceOf(alice), alice, alice);
        uint256 aliceReceived = usdc.balanceOf(alice) - aliceBalanceBefore;

        console2.log("=== DEFAULT RESULT ===");
        console2.log("Alice received:", aliceReceived);
        console2.log("Principal:", DEPOSIT_AMOUNT);
        console2.log("Interest received:", aliceReceived - DEPOSIT_AMOUNT);
        console2.log("Expected interest (accrued at default):", expectedInterest);

        uint256 expectedReceived = DEPOSIT_AMOUNT + expectedInterest;
        assertApproxEqAbs(aliceReceived, expectedReceived, 1e6, "Should receive principal + accrued interest (hybrid)");
    }

    /// @notice Case 7: Share value accrues per second
    function test_shareValueAccruesPerSecond() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 t0 = block.timestamp;

        uint256[] memory times = new uint256[](5);
        times[0] = 0;
        times[1] = 1;
        times[2] = 60;
        times[3] = 3600;
        times[4] = 86400;

        uint256 prevAssets = vault.totalAssets();

        for (uint256 i = 1; i < times.length; i++) {
            vm.warp(t0 + times[i]);
            uint256 currentAssets = vault.totalAssets();

            console2.log("Time +%d s: totalAssets = %d", times[i], currentAssets);
            console2.log("  Increase from previous: %d", currentAssets - prevAssets);

            assertTrue(currentAssets > prevAssets, "Assets should increase over time");
            prevAssets = currentAssets;
        }

        vm.warp(t0);
        uint256 assets0 = vault.totalAssets();
        vm.warp(t0 + 30 days);
        uint256 assets30day = vault.totalAssets();

        uint256 monthlyIncrease = assets30day - assets0;
        uint256 expectedMonthly = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        console2.log("Monthly increase (30 days):", monthlyIncrease);
        console2.log("Expected monthly:", expectedMonthly);

        assertApproxEqAbs(monthlyIncrease, expectedMonthly, 1e3, "Monthly accrual should match APY/12");
    }

    /// @notice Case 8: Multiple users claim at different times - total should match
    function test_multipleUsersClaimAtDifferentTimes() public {
        address[3] memory users = [alice, bob, charlie];

        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(vault), DEPOSIT_AMOUNT);
            vault.deposit(DEPOSIT_AMOUNT, users[i]);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 monthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);
        uint256 totalMonthlyInterest = monthlyInterest * 3;

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), totalMonthlyInterest * 6);
        vault.depositInterest(totalMonthlyInterest * 6);
        vm.stopPrank();

        uint256[3] memory userClaimed;

        // Alice claims every month
        for (uint256 month = 0; month < 6; month++) {
            vm.warp(vault.interestPaymentDates(month));
            vm.prank(alice);
            vault.claimInterest();
            userClaimed[0] += monthlyInterest;
        }

        // Bob claims at month 3 and 6
        vm.warp(vault.interestPaymentDates(2));
        vm.prank(bob);
        vault.claimInterest();
        userClaimed[1] += monthlyInterest * 3;

        vm.warp(vault.interestPaymentDates(5));
        vm.prank(bob);
        vault.claimInterest();
        userClaimed[1] += monthlyInterest * 3;

        // Charlie never claims

        uint256 lastPaymentDate = vault.interestPaymentDates(5);
        vm.warp(lastPaymentDate + 1);
        vm.prank(admin);
        vault.matureVault();

        uint256[3] memory userReceived;
        for (uint256 i = 0; i < 3; i++) {
            uint256 balBefore = usdc.balanceOf(users[i]);
            vm.prank(users[i]);
            vault.redeem(vault.balanceOf(users[i]), users[i], users[i]);
            userReceived[i] = usdc.balanceOf(users[i]) - balBefore;
        }

        console2.log("=== FINAL RESULTS ===");
        console2.log("Alice - claimed:", userClaimed[0]);
        console2.log("Alice - redeemed:", userReceived[0]);
        console2.log("Alice - total:", userClaimed[0] + userReceived[0]);
        console2.log("Bob - claimed:", userClaimed[1]);
        console2.log("Bob - redeemed:", userReceived[1]);
        console2.log("Bob - total:", userClaimed[1] + userReceived[1]);
        console2.log("Charlie - claimed:", userClaimed[2]);
        console2.log("Charlie - redeemed:", userReceived[2]);
        console2.log("Charlie - total:", userClaimed[2] + userReceived[2]);

        uint256 expectedPerUser = DEPOSIT_AMOUNT + monthlyInterest * 6;

        assertApproxEqAbs(userClaimed[0] + userReceived[0], expectedPerUser, 10, "Alice total");
        assertApproxEqAbs(userClaimed[1] + userReceived[1], expectedPerUser, 10, "Bob total");
        assertApproxEqAbs(userClaimed[2] + userReceived[2], expectedPerUser, 10, "Charlie total");
    }

    /// @notice Case 9: Anti-abuse - share value remains stable after claim
    function test_antiAbuse_claimThenSell_shareValueReflected() public {
        vm.startPrank(alice);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        uint256 lastPaymentDate = vault.interestPaymentDates(5);
        vm.warp(lastPaymentDate + 1);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 shareValueBefore = vault.convertToAssets(1e6);

        console2.log("=== BEFORE ALICE CLAIMS ===");
        console2.log("totalAssets:", totalAssetsBefore);
        console2.log("totalSupply:", totalSupplyBefore);
        console2.log("Share value (per 1e6):", shareValueBefore);
        console2.log("Alice shares:", vault.balanceOf(alice));

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimInterest();
        uint256 aliceClaimed = usdc.balanceOf(alice) - aliceBalanceBefore;

        console2.log("");
        console2.log("=== AFTER ALICE CLAIMS 6 MONTHS ===");
        console2.log("Alice claimed:", aliceClaimed);
        console2.log("Alice remaining shares:", vault.balanceOf(alice));

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 shareValueAfter = vault.convertToAssets(1e6);

        console2.log("totalAssets:", totalAssetsAfter);
        console2.log("totalSupply:", totalSupplyAfter);
        console2.log("Share value (per 1e6):", shareValueAfter);

        console2.log("");
        console2.log("Share value change:", int256(shareValueAfter) - int256(shareValueBefore));

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.transfer(bob, aliceShares);

        (uint256 bobShares, uint256 bobPrincipal, uint256 bobLastClaim,) = vault.getDepositInfo(bob);
        console2.log("");
        console2.log("=== BOB'S STATE AFTER PURCHASE ===");
        console2.log("Bob shares:", bobShares);
        console2.log("Bob principal:", bobPrincipal);
        console2.log("Bob lastClaimMonth:", bobLastClaim);
        console2.log("Bob claimable months:", vault.getClaimableMonths(bob));

        assertEq(bobLastClaim, 6, "Bob should inherit lastClaimMonth=6");
        assertEq(vault.getClaimableMonths(bob), 0, "Bob should have 0 claimable months");

        vm.prank(admin);
        vault.matureVault();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.redeem(vault.balanceOf(bob), bob, bob);
        uint256 bobReceived = usdc.balanceOf(bob) - bobBalanceBefore;

        console2.log("");
        console2.log("=== FINAL RESULT ===");
        console2.log("Alice received (interest):", aliceClaimed);
        console2.log("Bob received (principal only):", bobReceived);
        console2.log("Total:", aliceClaimed + bobReceived);
        console2.log("Expected total:", DEPOSIT_AMOUNT + expectedMonthlyInterest * 6);

        assertApproxEqAbs(bobReceived, DEPOSIT_AMOUNT, 10, "Bob should only receive principal");
        assertApproxEqAbs(aliceClaimed + bobReceived, DEPOSIT_AMOUNT + expectedMonthlyInterest * 6, 10, "Total should match");
        assertApproxEqAbs(shareValueBefore, shareValueAfter, 1e3, "Share value should remain stable after claim");
    }

    /// @notice Case 10: Atomic claim + transfer attack prevention
    function test_atomicClaimAndTransfer_noExploit() public {
        AtomicAttacker attacker = new AtomicAttacker(address(vault), address(usdc));

        usdc.mint(address(attacker), DEPOSIT_AMOUNT);

        attacker.deposit(DEPOSIT_AMOUNT);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        uint256 expectedMonthlyInterest = (DEPOSIT_AMOUNT * APY) / (12 * 10000);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedMonthlyInterest * 6);
        vault.depositInterest(expectedMonthlyInterest * 6);
        vm.stopPrank();

        uint256 lastPaymentDate = vault.interestPaymentDates(5);
        vm.warp(lastPaymentDate + 1);

        console2.log("=== BEFORE ATOMIC ATTACK ===");
        console2.log("Attacker shares:", vault.balanceOf(address(attacker)));
        console2.log("Bob shares:", vault.balanceOf(bob));
        console2.log("totalAssets:", vault.totalAssets());

        uint256 attackerSharesBefore = vault.balanceOf(address(attacker));
        uint256 bobSharesBefore = vault.balanceOf(bob);

        attacker.atomicClaimAndTransfer(bob);

        console2.log("");
        console2.log("=== AFTER ATOMIC ATTACK ===");
        console2.log("Attacker shares:", vault.balanceOf(address(attacker)));
        console2.log("Attacker received USDC:", usdc.balanceOf(address(attacker)));
        console2.log("Bob shares:", vault.balanceOf(bob));

        (uint256 bobShares, uint256 bobPrincipal, uint256 bobLastClaim,) = vault.getDepositInfo(bob);
        console2.log("Bob lastClaimMonth:", bobLastClaim);
        console2.log("Bob claimable months:", vault.getClaimableMonths(bob));

        assertEq(bobLastClaim, 6, "Bob MUST inherit lastClaimMonth=6");
        assertEq(vault.getClaimableMonths(bob), 0, "Bob should have 0 claimable months");

        vm.prank(admin);
        vault.matureVault();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        vault.redeem(vault.balanceOf(bob), bob, bob);
        uint256 bobReceived = usdc.balanceOf(bob) - bobBalanceBefore;

        console2.log("");
        console2.log("=== VICTIM (BOB) RESULT ===");
        console2.log("Bob received:", bobReceived);
        console2.log("This should be ONLY principal:", DEPOSIT_AMOUNT);

        assertApproxEqAbs(bobReceived, DEPOSIT_AMOUNT, 10, "Bob should only receive principal");

        uint256 attackerGot = usdc.balanceOf(address(attacker));
        assertApproxEqAbs(attackerGot, expectedMonthlyInterest * 6, 10, "Attacker got all interest");

        console2.log("");
        console2.log("=== DEFENSE VERIFIED ===");
        console2.log("Attacker extracted:", attackerGot);
        console2.log("Bob got principal:", bobReceived);
        console2.log("Total:", attackerGot + bobReceived);
        console2.log("No double-claim possible!");
    }
}

/// @notice Malicious contract for atomic claim + transfer attack
contract AtomicAttacker {
    RWAVault public vault;
    IERC20 public usdc;

    constructor(address _vault, address _usdc) {
        vault = RWAVault(_vault);
        usdc = IERC20(_usdc);
    }

    function deposit(uint256 amount) external {
        usdc.approve(address(vault), amount);
        vault.deposit(amount, address(this));
    }

    function atomicClaimAndTransfer(address victim) external {
        vault.claimInterest();
        uint256 myShares = vault.balanceOf(address(this));
        vault.transfer(victim, myShares);
    }
}
