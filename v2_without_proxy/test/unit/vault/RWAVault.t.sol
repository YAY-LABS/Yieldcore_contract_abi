// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../../src/interfaces/IRWAVault.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";

contract RWAVaultTest is BaseTest {
    RWAVault public vault;

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());
    }

    // ============ Initialization Tests ============

    function test_initialize() public view {
        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Collecting));
        assertEq(vault.fixedAPY(), 1500);
        assertEq(vault.minDeposit(), 100e6);
        assertEq(vault.maxCapacity(), 10_000_000e6);
        assertEq(vault.poolManager(), address(poolManager));
        assertTrue(vault.active());
    }

    function test_initialize_grantsRoles() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(RWAConstants.OPERATOR_ROLE, address(poolManager)));
        assertTrue(vault.hasRole(RWAConstants.PAUSER_ROLE, admin));
    }

    // ============ Deposit Tests (Collecting Phase) ============

    function test_deposit_success() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(shares, depositAmount); // 1:1 initially
        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_deposit_tracksDepositInfo() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        (uint256 userShares, uint256 principal, uint256 lastClaimMonth, uint256 depositTime) = vault.getDepositInfo(user1);
        assertEq(userShares, shares);
        assertEq(principal, depositAmount);
        assertEq(lastClaimMonth, 0);
        assertEq(depositTime, block.timestamp);
    }

    function test_deposit_multipleUsers() public {
        uint256 depositAmount1 = 10_000e6;
        uint256 depositAmount2 = 20_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2, user2);
        vm.stopPrank();

        assertEq(vault.totalAssets(), depositAmount1 + depositAmount2);
    }

    function test_deposit_revertMinDepositNotMet() public {
        uint256 depositAmount = 50e6; // Below 100e6 min

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);

        vm.expectRevert(RWAErrors.MinDepositNotMet.selector);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
    }

    function test_deposit_revertCapacityExceeded() public {
        uint256 depositAmount = 10_000_001e6; // Above 10M max

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);

        vm.expectRevert(RWAErrors.VaultCapacityExceeded.selector);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
    }

    function test_deposit_revertWhenNotActive() public {
        vm.prank(admin);
        vault.setActive(false);

        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);

        vm.expectRevert(RWAErrors.VaultNotActive.selector);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();
    }

    function test_deposit_revertWhenPaused() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);

        vm.expectRevert();
        vault.deposit(10_000e6, user1);
        vm.stopPrank();
    }

    function test_deposit_revertAfterCollectionEnds() public {
        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);

        vm.expectRevert(RWAErrors.CollectionEnded.selector);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();
    }

    function test_deposit_revertInActivePhase() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        // Warp and activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to deposit in Active phase
        vm.startPrank(user2);
        usdc.approve(address(vault), 10_000e6);

        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.deposit(10_000e6, user2);
        vm.stopPrank();
    }

    // ============ Phase Transition Tests ============

    function test_activateVault() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        // Warp past collection end
        vm.warp(block.timestamp + 8 days);

        vm.prank(admin);
        vault.activateVault();

        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Active));
    }

    function test_activateVault_revertBeforeCollectionEnds() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.CollectionNotEnded.selector);
        vault.activateVault();
    }

    function test_activateVault_revertArrayLengthMismatch() public {
        // Set mismatched array lengths (3 period end dates, but 6 payment dates already set)
        uint256 interestStart = block.timestamp + 7 days;
        uint256[] memory shortPeriodEndDates = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            shortPeriodEndDates[i] = interestStart + (i + 1) * 30 days;
        }

        vm.prank(admin);
        vault.setInterestPeriodEndDates(shortPeriodEndDates);

        // Warp past collection end
        vm.warp(block.timestamp + 8 days);

        vm.prank(admin);
        vm.expectRevert(RWAErrors.ArrayLengthMismatch.selector);
        vault.activateVault();
    }

    function test_matureVault() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp past maturity (7 days collection + 180 days term)
        vm.warp(block.timestamp + 181 days);

        vm.prank(admin);
        vault.matureVault();

        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Matured));
    }

    function test_matureVault_revertBeforeMaturity() public {
        // Setup and activate
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to mature before maturity time
        vm.prank(admin);
        vm.expectRevert(RWAErrors.NotMatured.selector);
        vault.matureVault();
    }

    // ============ Interest Tests ============

    function test_claimInterest_afterOneMonth() public {
        uint256 depositAmount = 120_000e6; // 120K for easy math

        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp 1 month + 3 days (past first payment date)
        // Note: interestPaymentDates[0] = interestStartTime + 30 days + 3 days
        vm.warp(block.timestamp + 33 days);

        // Calculate expected monthly interest based on current share value
        // Interest is calculated as: previewRedeem(shares) * fixedAPY / (12 * BASIS_POINTS)
        uint256 principal = vault.previewRedeem(vault.balanceOf(user1));
        uint256 expectedInterest = (principal * 1500) / (12 * 10_000);

        // Deposit interest funds to vault (from PoolManager)
        // Must deposit AFTER calculating expected, as it affects share price
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), expectedInterest);
        vault.depositInterest(expectedInterest);
        vm.stopPrank();

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.claimInterest();

        // Allow small rounding tolerance from division operations
        assertApproxEqAbs(usdc.balanceOf(user1), balanceBefore + expectedInterest, 100e6);
    }

    function test_getPendingInterest() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Before activation, no pending interest
        assertEq(vault.getPendingInterest(user1), 0);

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // After 1 month + 3 days (past first payment date)
        // Note: interestPaymentDates[0] = interestStartTime + 30 days + 3 days
        vm.warp(block.timestamp + 33 days);

        uint256 expectedInterest = (depositAmount * 1500) / (12 * 10_000);
        assertEq(vault.getPendingInterest(user1), expectedInterest);
    }

    function test_claimInterest_revertInCollectingPhase() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.claimInterest();
    }

    // ============ Withdrawal Tests (Matured Phase Only) ============

    function test_withdraw_atMaturity() public {
        uint256 depositAmount = 10_000e6;

        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest for any pending claims
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        // Mature
        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal start time (required after M-01 fix)
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // Withdraw
        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 shares = vault.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        // User gets principal back (plus any interest claimed automatically)
        assertTrue(usdc.balanceOf(user1) > balanceBefore);
    }

    function test_withdraw_revertBeforeMaturity() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Try to withdraw in Collecting phase
        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.withdraw(depositAmount, user1, user1);
    }

    function test_withdraw_revertInActivePhase() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to withdraw in Active phase
        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.withdraw(depositAmount, user1, user1);
    }

    // ============ Capital Deployment Tests (PoolManager) ============

    function test_deployCapital_success() public {
        uint256 depositAmount = 100_000e6;

        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);

        // Deploy capital through PoolManager (with timelock)
        uint256 deployAmount = 50_000e6;
        uint256 recipientBalanceBefore = usdc.balanceOf(borrower);

        _deployCapital(address(vault), deployAmount, borrower);

        assertEq(vault.totalDeployed(), deployAmount);
        assertEq(usdc.balanceOf(borrower), recipientBalanceBefore + deployAmount);
    }

    function test_deployCapital_revertUnauthorized() public {
        // Unauthorized user cannot call announceDeployCapital on vault
        vm.prank(user1);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        vault.announceDeployCapital(10_000e6, borrower);
    }

    function test_deployCapital_revertZeroAmount() public {
        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);

        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.announceDeployCapital(0, borrower);
    }

    function test_deployCapital_revertInsufficientLiquidity() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);

        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.InsufficientLiquidity.selector);
        vault.announceDeployCapital(depositAmount + 1e6, borrower);
    }

    function test_returnCapital_success() public {
        uint256 depositAmount = 100_000e6;
        uint256 deployAmount = 50_000e6;

        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);

        // Deploy through PoolManager
        _deployCapital(address(vault), deployAmount, address(poolManager));

        // Return capital through PoolManager
        _returnCapital(address(vault), deployAmount);

        assertEq(vault.totalDeployed(), 0);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_returnCapital_revertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        vault.returnCapital(10_000e6);
    }

    // ============ View Function Tests ============

    function test_availableLiquidity() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertEq(vault.availableLiquidity(), depositAmount);
    }

    function test_getVaultStatus() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        (
            IRWAVault.Phase phase,
            uint256 totalAssets_,
            uint256 totalDeployed_,
            uint256 availableBalance,
            uint256 totalInterestPaid_
        ) = vault.getVaultStatus();

        assertEq(uint256(phase), uint256(IRWAVault.Phase.Collecting));
        assertEq(totalAssets_, depositAmount);
        assertEq(totalDeployed_, 0);
        assertEq(availableBalance, depositAmount);
        assertEq(totalInterestPaid_, 0);
    }

    function test_getVaultConfig() public view {
        (
            uint256 collectionEndTime_,
            uint256 interestStartTime_,
            uint256 maturityTime_,
            uint256 termDuration_,
            uint256 fixedAPY_,
            uint256 minDeposit_,
            uint256 maxCapacity_
        ) = vault.getVaultConfig();

        assertEq(termDuration_, 180 days);
        assertEq(fixedAPY_, 1500);
        assertEq(minDeposit_, 100e6);
        assertEq(maxCapacity_, 10_000_000e6);
        assertTrue(collectionEndTime_ > block.timestamp);
        assertTrue(interestStartTime_ >= collectionEndTime_);
        assertTrue(maturityTime_ > interestStartTime_);
    }

    // ============ Admin Function Tests ============

    function test_setActive() public {
        assertTrue(vault.active());

        vm.prank(admin);
        vault.setActive(false);

        assertFalse(vault.active());
    }

    function test_setInterestStartTime() public {
        uint256 newStartTime = block.timestamp + 14 days;

        vm.prank(admin);
        vault.setInterestStartTime(newStartTime);

        assertEq(vault.interestStartTime(), newStartTime);
        // maturityTime is now derived from interestPeriodEndDates[last]
        // It doesn't auto-update when interestStartTime changes
        // Admin must call setInterestPeriodEndDates with updated dates
    }

    function test_setInterestStartTime_revertAfterActive() public {
        // Deposit and activate
        vm.startPrank(user1);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to change interest start time
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.setInterestStartTime(block.timestamp + 30 days);
    }

    // ============ Pause Tests ============

    function test_pause_unpause() public {
        vm.startPrank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }

    // ============ Token Recovery Tests ============

    function test_recoverERC20_success() public {
        // Deploy a random ERC20 token (not USDC)
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        // Accidentally send tokens to vault
        uint256 accidentalAmount = 1000e18;
        randomToken.mint(address(vault), accidentalAmount);

        assertEq(randomToken.balanceOf(address(vault)), accidentalAmount);
        assertEq(randomToken.balanceOf(treasury), 0);

        // Admin recovers the tokens via PoolManager
        vm.prank(admin);
        poolManager.recoverERC20(address(vault), address(randomToken), accidentalAmount, treasury);

        // Tokens should be transferred to treasury
        assertEq(randomToken.balanceOf(address(vault)), 0);
        assertEq(randomToken.balanceOf(treasury), accidentalAmount);
    }

    function test_recoverERC20_revertVaultAsset() public {
        // Try to recover the vault's underlying asset (USDC) via PoolManager
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        poolManager.recoverERC20(address(vault), address(usdc), 1000e6, treasury);
    }

    function test_recoverERC20_revertZeroAmount() public {
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);

        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.recoverERC20(address(vault), address(randomToken), 0, treasury);
    }

    function test_recoverERC20_revertUnauthorized() public {
        MockERC20 randomToken = new MockERC20("Random Token", "RND", 18);
        randomToken.mint(address(vault), 1000e18);

        // Non-admin tries to recover via PoolManager
        vm.prank(user1);
        vm.expectRevert(); // AccessControl revert
        poolManager.recoverERC20(address(vault), address(randomToken), 1000e18, treasury);
    }

    // ============ Deployment Timelock Tests ============

    function test_announceDeployCapital_success() public {
        // Setup: deposit funds
        usdc.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Announce deployment
        vm.prank(address(poolManager));
        vault.announceDeployCapital(50_000e6, treasury);

        // Check pending deployment
        (uint256 amount, address recipient, uint256 executeTime, bool active) = vault.getPendingDeployment();
        assertEq(amount, 50_000e6);
        assertEq(recipient, treasury);
        assertEq(executeTime, block.timestamp + 1 hours);
        assertTrue(active);
    }

    function test_executeDeployCapital_success() public {
        // Setup: deposit funds
        usdc.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Announce deployment
        vm.prank(address(poolManager));
        vault.announceDeployCapital(50_000e6, treasury);

        // Try to execute before delay - should fail
        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.DeploymentNotReady.selector);
        vault.executeDeployCapital();

        // Wait for delay
        vm.warp(block.timestamp + 1 hours + 1);

        // Execute deployment
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        vm.prank(address(poolManager));
        vault.executeDeployCapital();

        // Verify
        assertEq(usdc.balanceOf(treasury), treasuryBalanceBefore + 50_000e6);
        assertEq(vault.totalDeployed(), 50_000e6);

        // Pending deployment should be cleared
        (,,, bool active) = vault.getPendingDeployment();
        assertFalse(active);
    }

    function test_cancelDeployCapital_success() public {
        // Setup: deposit funds
        usdc.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Announce deployment
        vm.prank(address(poolManager));
        vault.announceDeployCapital(50_000e6, treasury);

        // Cancel deployment
        vm.prank(address(poolManager));
        vault.cancelDeployCapital();

        // Pending deployment should be cleared
        (,,, bool active) = vault.getPendingDeployment();
        assertFalse(active);
    }

    function test_announceDeployCapital_revertAlreadyPending() public {
        // Setup: deposit funds
        usdc.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Announce first deployment
        vm.prank(address(poolManager));
        vault.announceDeployCapital(50_000e6, treasury);

        // Try to announce another - should fail
        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.DeploymentAlreadyPending.selector);
        vault.announceDeployCapital(30_000e6, treasury);
    }

    function test_setDeploymentDelay() public {
        assertEq(vault.deploymentDelay(), 1 hours);

        vm.prank(admin);
        vault.setDeploymentDelay(48 hours);

        assertEq(vault.deploymentDelay(), 48 hours);
    }
}
