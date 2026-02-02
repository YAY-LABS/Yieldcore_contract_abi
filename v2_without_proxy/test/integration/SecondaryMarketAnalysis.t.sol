// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/vault/RWAVault.sol";
import "../unit/BaseTest.sol";

contract SecondaryMarketAnalysisTest is BaseTest {
    
    function test_claimedVsUnclaimedTransfer() public {
        RWAVault vault = RWAVault(_createDefaultVault());
        
        // Setup: Two users deposit same amount
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address buyerA = makeAddr("buyerA");
        address buyerB = makeAddr("buyerB");
        
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        
        vm.prank(alice);
        usdc.approve(address(vault), 100_000e6);
        vm.prank(alice);
        vault.deposit(100_000e6, alice);
        
        vm.prank(bob);
        usdc.approve(address(vault), 100_000e6);
        vm.prank(bob);
        vault.deposit(100_000e6, bob);
        
        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();
        
        // Deposit interest to vault (simulating interest earnings)
        usdc.mint(address(vault), 25_000e6);
        
        uint256 t0 = block.timestamp;
        
        console2.log("=== Initial State ===");
        console2.log("Alice shares:", vault.balanceOf(alice));
        console2.log("Bob shares:", vault.balanceOf(bob));
        console2.log("Share value (per 1e6):", vault.convertToAssets(1e6));
        
        // Warp to month 3 payment date
        vm.warp(t0 + 90 days + 3 days + 1);
        
        console2.log("");
        console2.log("=== After 3 Months ===");
        console2.log("Share value (per 1e6):", vault.convertToAssets(1e6));
        console2.log("Alice pending interest:", vault.getPendingInterest(alice));
        console2.log("Bob pending interest:", vault.getPendingInterest(bob));
        
        // Alice claims 3 months interest
        uint256 aliceClaimedAmount = vault.getPendingInterest(alice);
        vm.prank(alice);
        vault.claimInterest();
        
        console2.log("");
        console2.log("=== After Alice Claims ===");
        console2.log("Alice claimed:", aliceClaimedAmount);
        console2.log("Alice shares:", vault.balanceOf(alice));
        console2.log("Bob shares:", vault.balanceOf(bob));
        console2.log("Share value (per 1e6):", vault.convertToAssets(1e6));
        
        (uint256 aliceShares,,uint256 aliceLastClaim,) = vault.getDepositInfo(alice);
        (uint256 bobShares,,uint256 bobLastClaim,) = vault.getDepositInfo(bob);
        
        console2.log("");
        console2.log("=== Before Transfer ===");
        console2.log("Alice shares:", aliceShares);
        console2.log("Alice lastClaim:", aliceLastClaim);
        console2.log("Bob shares:", bobShares);
        console2.log("Bob lastClaim:", bobLastClaim);
        
        // Both transfer ALL shares to buyers
        uint256 aliceTransferAmount = vault.balanceOf(alice);
        uint256 bobTransferAmount = vault.balanceOf(bob);
        
        vm.prank(alice);
        vault.transfer(buyerA, aliceTransferAmount);
        
        vm.prank(bob);
        vault.transfer(buyerB, bobTransferAmount);
        
        console2.log("");
        console2.log("=== After Transfers ===");
        (uint256 buyerAShares, uint256 buyerAPrincipal, uint256 buyerALastClaim,) = vault.getDepositInfo(buyerA);
        (uint256 buyerBShares, uint256 buyerBPrincipal, uint256 buyerBLastClaim,) = vault.getDepositInfo(buyerB);
        
        console2.log("BuyerA (from claimed seller):");
        console2.log("  shares:", buyerAShares);
        console2.log("  principal:", buyerAPrincipal);
        console2.log("  lastClaim:", buyerALastClaim);
        console2.log("  pending interest:", vault.getPendingInterest(buyerA));
        console2.log("");
        console2.log("BuyerB (from unclaimed seller):");
        console2.log("  shares:", buyerBShares);
        console2.log("  principal:", buyerBPrincipal);
        console2.log("  lastClaim:", buyerBLastClaim);
        console2.log("  pending interest:", vault.getPendingInterest(buyerB));
        
        // Fast forward to maturity
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);
        
        console2.log("");
        console2.log("=== At Maturity ===");
        console2.log("BuyerA pending interest:", vault.getPendingInterest(buyerA));
        console2.log("BuyerB pending interest:", vault.getPendingInterest(buyerB));
        console2.log("BuyerA maxWithdraw:", vault.maxWithdraw(buyerA));
        console2.log("BuyerB maxWithdraw:", vault.maxWithdraw(buyerB));
        
        // Both buyers withdraw everything
        uint256 buyerARedeemShares = vault.balanceOf(buyerA);
        uint256 buyerBRedeemShares = vault.balanceOf(buyerB);
        
        vm.prank(buyerA);
        vault.redeem(buyerARedeemShares, buyerA, buyerA);
        
        vm.prank(buyerB);
        vault.redeem(buyerBRedeemShares, buyerB, buyerB);
        
        uint256 buyerATotal = usdc.balanceOf(buyerA);
        uint256 buyerBTotal = usdc.balanceOf(buyerB);
        
        console2.log("");
        console2.log("========== FINAL SUMMARY ==========");
        console2.log("Alice (claimed then sold):");
        console2.log("  Claimed interest:", aliceClaimedAmount);
        console2.log("  Buyer received:", buyerATotal);
        console2.log("  TOTAL VALUE:", aliceClaimedAmount + buyerATotal);
        console2.log("");
        console2.log("Bob (sold without claiming):");
        console2.log("  Buyer received:", buyerBTotal);
        console2.log("  TOTAL VALUE:", buyerBTotal);
        console2.log("");
        console2.log("DIFFERENCE:", int256(aliceClaimedAmount + buyerATotal) - int256(buyerBTotal));
        console2.log("===================================");
        
        // Verify total values are equal
        assertApproxEqAbs(
            aliceClaimedAmount + buyerATotal,
            buyerBTotal,
            10, // Allow 10 wei rounding error
            "Total values should be equal regardless of claim timing"
        );
    }
}
