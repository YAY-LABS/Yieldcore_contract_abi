// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../../src/interfaces/IRWAVault.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {console2} from "forge-std/Test.sol";

// Import enums for updateSettings test
import {RWAVault as RWAVaultTypes} from "../../../src/vault/RWAVault.sol";

/// @title RWAVault Coverage Tests
/// @notice Tests for previously uncovered functions
contract RWAVaultCoverageTest is BaseTest {
    RWAVault public vault;

    uint256 constant DEPOSIT_AMOUNT = 10_000e6; // 10,000 USDC

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());
    }

    // ============ View/Getter Function Tests ============

    function test_getNetRedemptionValue() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Get net redemption value (calculates value based on shares)
        uint256 netValue = vault.getNetRedemptionValue(user1);
        // Before maturity, this returns the calculated value but withdraw is blocked
        assertGt(netValue, 0, "Should have calculated value");

        // Activate and mature
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // After maturity - should have value
        netValue = vault.getNetRedemptionValue(user1);
        assertGt(netValue, 0, "Should have value after maturity");
    }

    function test_isWhitelisted() public {
        // Enable whitelist
        vm.prank(admin);
        vault.setWhitelistEnabled(true);

        // Add user to whitelist
        address[] memory users = new address[](1);
        users[0] = user1;
        vm.prank(admin);
        vault.addToWhitelist(users);

        assertTrue(vault.isWhitelisted(user1), "User1 should be whitelisted");
        assertFalse(vault.isWhitelisted(user2), "User2 should not be whitelisted");
    }

    function test_getAllocatedCap() public {
        // Allocate cap
        vm.prank(admin);
        vault.allocateCap(user1, 50_000e6);

        assertEq(vault.getAllocatedCap(user1), 50_000e6, "Should return allocated cap");
        assertEq(vault.getAllocatedCap(user2), 0, "Should return 0 for unallocated user");
    }

    function test_getPublicCapacity() public {
        uint256 maxCapacity = vault.maxCapacity();
        uint256 publicCapacity = vault.getPublicCapacity();

        // Initially all capacity is public
        assertEq(publicCapacity, maxCapacity, "All capacity should be public initially");

        // Allocate some cap
        vm.prank(admin);
        vault.allocateCap(user1, 1_000_000e6);

        // Public capacity should decrease
        uint256 newPublicCapacity = vault.getPublicCapacity();
        assertEq(newPublicCapacity, maxCapacity - 1_000_000e6, "Public capacity should decrease");
    }

    function test_getRemainingAllocation() public {
        // Allocate cap
        vm.prank(admin);
        vault.allocateCap(user1, 50_000e6);

        // Check remaining
        assertEq(vault.getRemainingAllocation(user1), 50_000e6, "Should have full allocation");

        // Deposit some
        vm.startPrank(user1);
        usdc.approve(address(vault), 20_000e6);
        vault.deposit(20_000e6, user1);
        vm.stopPrank();

        // Check remaining decreased
        assertEq(vault.getRemainingAllocation(user1), 30_000e6, "Remaining should decrease");
    }

    function test_getUserDepositAllowance() public {
        // Set user deposit caps
        vm.prank(admin);
        vault.setUserDepositCaps(100e6, 100_000e6);

        // Get allowance
        uint256 allowance = vault.getUserDepositAllowance(user1);
        assertEq(allowance, 100_000e6, "Should return max per user");

        // After deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), 30_000e6);
        vault.deposit(30_000e6, user1);
        vm.stopPrank();

        allowance = vault.getUserDepositAllowance(user1);
        assertEq(allowance, 70_000e6, "Should return remaining allowance");
    }

    function test_isActive() public {
        assertTrue(vault.isActive(), "Vault should be active by default");

        vm.prank(admin);
        vault.setActive(false);

        assertFalse(vault.isActive(), "Vault should be inactive");
    }

    function test_getExtendedInfo() public {
        (
            uint256 totalPrincipal_,
            uint256 bufferBalance_,
            int256 totalFxGainLoss_,
            uint256 deploymentCount,
            ,
        ) = vault.getExtendedInfo();

        assertEq(totalPrincipal_, 0, "Should be 0 initially");
        assertEq(bufferBalance_, 0, "Should be 0 initially");
        assertEq(totalFxGainLoss_, 0, "Should be 0 initially");
        assertEq(deploymentCount, 0, "Should be 0 initially");
    }

    function test_getDeploymentRecord() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Deploy with rate
        vm.prank(address(poolManager));
        vault.deployCapitalWithRate(5000e6, borrower, 130000000000); // 1300 KRW/USD

        // Get deployment record
        RWAVault.DeploymentRecord memory record = vault.getDeploymentRecord(0);

        assertEq(record.deployedUSD, 5000e6, "Deployed USD should match");
        assertEq(record.deploymentRate, 130000000000, "Rate should match");
        assertGt(record.deployedKRW, 0, "KRW should be calculated");
        assertGt(record.deploymentTime, 0, "Time should be set");
        assertFalse(record.settled, "Should not be settled yet");
    }

    function test_getInterestPaymentDates() public {
        uint256[] memory dates = vault.getInterestPaymentDates();
        assertEq(dates.length, 6, "Should have 6 payment dates");
    }

    function test_getTotalInterestMonths() public {
        uint256 months = vault.getTotalInterestMonths();
        assertEq(months, 6, "Should have 6 interest months");
    }

    // ============ Alternative Entry Point Tests ============

    function test_mint_success() public {
        uint256 sharesToMint = 5000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        uint256 assetsUsed = vault.mint(sharesToMint, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), sharesToMint, "Should have minted shares");
        assertEq(assetsUsed, sharesToMint, "1:1 ratio during collection");
    }

    function test_maxMint() public {
        uint256 maxMintAmount = vault.maxMint(user1);
        assertGt(maxMintAmount, 0, "Should have max mint capacity");

        // After vault inactive
        vm.prank(admin);
        vault.setActive(false);

        assertEq(vault.maxMint(user1), 0, "Should be 0 when inactive");
    }

    function test_maxRedeem() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Before maturity
        assertEq(vault.maxRedeem(user1), 0, "Should be 0 before maturity");

        // Activate and mature
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // After maturity
        uint256 maxRedeemAmount = vault.maxRedeem(user1);
        assertGt(maxRedeemAmount, 0, "Should have redeemable shares");
    }

    function test_claimSingleMonth() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        // Warp to after first payment date
        uint256[] memory paymentDates = vault.getInterestPaymentDates();
        vm.warp(paymentDates[0] + 1);

        // Claim single month
        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vault.claimSingleMonth();
        uint256 balanceAfter = usdc.balanceOf(user1);

        assertGt(balanceAfter - balanceBefore, 0, "Should claim interest for one month");
    }

    // ============ FX Rate Function Tests ============

    function test_deployCapitalWithRate() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 deployAmount = 5000e6;
        uint256 exchangeRate = 130000000000; // 1300 KRW/USD (8 decimals)

        vm.prank(address(poolManager));
        vault.deployCapitalWithRate(deployAmount, borrower, exchangeRate);

        assertEq(vault.totalDeployed(), deployAmount, "Should track deployed amount");

        // Verify deployment record
        RWAVault.DeploymentRecord memory record = vault.getDeploymentRecord(0);

        assertEq(record.deployedUSD, deployAmount, "Record should match");
        assertEq(record.deploymentRate, exchangeRate, "Rate should match");
        assertGt(record.deployedKRW, 0, "KRW should be calculated");
    }

    function test_returnCapitalWithRate() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 deployAmount = 5000e6;
        uint256 deployRate = 130000000000; // 1300 KRW/USD

        // Deploy with rate
        vm.prank(address(poolManager));
        vault.deployCapitalWithRate(deployAmount, borrower, deployRate);

        // Return with different rate (simulating FX change)
        uint256 returnRate = 135000000000; // 1350 KRW/USD (USD appreciated)

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), deployAmount);
        vault.returnCapitalWithRate(deployAmount, returnRate, 0);
        vm.stopPrank();

        assertEq(vault.totalDeployed(), 0, "Should be fully returned");

        // Verify return record
        RWAVault.DeploymentRecord memory record = vault.getDeploymentRecord(0);

        assertEq(record.returnedUSD, deployAmount, "Returned amount should match");
        assertEq(record.returnRate, returnRate, "Return rate should match");
        assertGt(record.returnedKRW, 0, "Returned KRW should be calculated");
        assertTrue(record.settled, "Should be settled");
    }

    function test_returnCapitalWithRate_fxGainLoss() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        uint256 deployAmount = 5000e6;

        // Deploy at 1300 KRW/USD
        vm.prank(address(poolManager));
        vault.deployCapitalWithRate(deployAmount, borrower, 130000000000);

        // Return at 1350 KRW/USD (USD appreciated = FX gain)
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), deployAmount);
        vault.returnCapitalWithRate(deployAmount, 135000000000, 0);
        vm.stopPrank();

        // Check FX gain/loss
        (,, int256 totalFxGainLoss,,,) = vault.getExtendedInfo();
        // When USD appreciates (1300 -> 1350), returning same USD means FX gain
        assertGt(totalFxGainLoss, 0, "Should have FX gain when USD appreciates");
    }

    // ============ Buffer Management Tests ============

    function test_depositToBuffer() public {
        uint256 bufferAmount = 1000e6;

        vm.startPrank(admin);
        usdc.approve(address(vault), bufferAmount);
        vault.depositToBuffer(bufferAmount);
        vm.stopPrank();

        (, uint256 bufferBalance_,,,, ) = vault.getExtendedInfo();
        assertEq(bufferBalance_, bufferAmount, "Buffer should have funds");
    }

    function test_withdrawFromBuffer() public {
        uint256 bufferAmount = 1000e6;

        // First deposit to buffer
        vm.startPrank(admin);
        usdc.approve(address(vault), bufferAmount);
        vault.depositToBuffer(bufferAmount);

        // Then withdraw
        uint256 withdrawAmount = 500e6;
        vault.withdrawFromBuffer(withdrawAmount);
        vm.stopPrank();

        (, uint256 bufferBalance_,,,, ) = vault.getExtendedInfo();
        assertEq(bufferBalance_, bufferAmount - withdrawAmount, "Buffer should decrease");
    }

    function test_withdrawFromBuffer_revertInsufficientLiquidity() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InsufficientLiquidity.selector);
        vault.withdrawFromBuffer(1000e6);
    }

    // ============ Whitelist/Cap Management Tests ============

    function test_removeFromWhitelist() public {
        // Enable whitelist and add user
        vm.startPrank(admin);
        vault.setWhitelistEnabled(true);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        vault.addToWhitelist(users);

        assertTrue(vault.isWhitelisted(user1), "User1 should be whitelisted");
        assertTrue(vault.isWhitelisted(user2), "User2 should be whitelisted");

        // Remove user1
        address[] memory toRemove = new address[](1);
        toRemove[0] = user1;
        vault.removeFromWhitelist(toRemove);
        vm.stopPrank();

        assertFalse(vault.isWhitelisted(user1), "User1 should be removed");
        assertTrue(vault.isWhitelisted(user2), "User2 should still be whitelisted");
    }

    function test_batchAllocateCap() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = borrower;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000e6;
        amounts[1] = 20_000e6;
        amounts[2] = 30_000e6;

        vm.prank(admin);
        vault.batchAllocateCap(users, amounts);

        assertEq(vault.getAllocatedCap(user1), 10_000e6, "User1 cap should match");
        assertEq(vault.getAllocatedCap(user2), 20_000e6, "User2 cap should match");
        assertEq(vault.getAllocatedCap(borrower), 30_000e6, "Borrower cap should match");
    }

    function test_batchAllocateCap_revertArrayMismatch() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000e6;

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        vault.batchAllocateCap(users, amounts);
    }

    // ============ Admin Settings Tests ============

    function test_setPriceOracle() public {
        address newOracle = makeAddr("oracle");

        vm.prank(admin);
        vault.setPriceOracle(newOracle);

        assertEq(vault.priceOracle(), newOracle, "Oracle should be set");
    }

    function test_setPriceOracle_revertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        vault.setPriceOracle(address(0));
    }

    function test_updateSettings() public {
        vm.prank(admin);
        vault.updateSettings(
            RWAVault.InterestMode.BufferAdjusted,
            RWAVault.PrincipalProtection.Full,
            500,    // 5% buffer target
            1000    // 10% max FX loss
        );

        // Verify settings were updated via getExtendedInfo
        (,,,, RWAVault.InterestMode mode, RWAVault.PrincipalProtection protection) = vault.getExtendedInfo();
        assertEq(uint8(mode), uint8(RWAVault.InterestMode.BufferAdjusted), "Mode should be updated");
        assertEq(uint8(protection), uint8(RWAVault.PrincipalProtection.Full), "Protection should be updated");
    }

    // ============ Edge Case Tests ============

    function test_mint_revertWhenInactive() public {
        vm.prank(admin);
        vault.setActive(false);

        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(RWAErrors.VaultNotActive.selector);
        vault.mint(1000e6, user1);
        vm.stopPrank();
    }

    function test_claimSingleMonth_revertNoClaimableMonths() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to claim before any payment date (no claimable months)
        vm.prank(user1);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimSingleMonth();
    }

    function test_deployCapitalWithRate_revertZeroAmount() public {
        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.deployCapitalWithRate(0, borrower, 130000000000);
    }

    function test_returnCapitalWithRate_revertAlreadySettled() public {
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.stopPrank();

        // Deploy
        vm.prank(address(poolManager));
        vault.deployCapitalWithRate(5000e6, borrower, 130000000000);

        // Return
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 5000e6);
        vault.returnCapitalWithRate(5000e6, 135000000000, 0);

        // Try to return again (already settled)
        usdc.approve(address(vault), 5000e6);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        vault.returnCapitalWithRate(5000e6, 135000000000, 0);
        vm.stopPrank();
    }
}
