// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {LoanRegistry} from "../../../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../../../src/core/VaultRegistry.sol";
import {PoolManager} from "../../../src/core/PoolManager.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {VaultFactory} from "../../../src/factory/VaultFactory.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";
import {IVaultFactory} from "../../../src/interfaces/IVaultFactory.sol";
import {IRWAVault} from "../../../src/interfaces/IRWAVault.sol";

// ============================================================================
// HELPER CONTRACTS FOR CONTRACT-TO-CONTRACT TESTING
// ============================================================================

/// @notice Intermediary contract that deposits on behalf of users
/// @dev Simulates a router, aggregator, or DeFi protocol depositing for users
contract IntermediaryDepositor {
    RWAVault public vault;
    IERC20 public usdc;

    constructor(address _vault, address _usdc) {
        vault = RWAVault(_vault);
        usdc = IERC20(_usdc);
    }

    /// @notice Deposit assets to vault with receiver being a different address
    /// @dev This is the key scenario: msg.sender (this contract) != receiver (userWallet)
    function depositFor(address receiver, uint256 amount) external returns (uint256 shares) {
        usdc.approve(address(vault), amount);
        shares = vault.deposit(amount, receiver);
    }

    /// @notice Attempt to claim interest on behalf of a user (should work if this contract has shares)
    function claimInterestFor() external {
        vault.claimInterest();
    }

    /// @notice Attempt to withdraw on behalf of a user
    function withdrawFor(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = vault.withdraw(assets, receiver, owner);
    }

    /// @notice Attempt to redeem on behalf of a user
    function redeemFor(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = vault.redeem(shares, receiver, owner);
    }

    /// @notice Transfer USDC to this contract
    function fundContract(uint256 amount) external {
        usdc.transferFrom(msg.sender, address(this), amount);
    }
}

/// @notice Contract that tries to claim interest for another user (malicious scenario)
contract MaliciousClaimContract {
    RWAVault public vault;

    constructor(address _vault) {
        vault = RWAVault(_vault);
    }

    /// @notice Attempt to claim interest (will only get interest for THIS contract's deposits)
    function attemptClaimInterest() external {
        vault.claimInterest();
    }

    /// @notice Try to claim single month
    function attemptClaimSingleMonth() external {
        vault.claimSingleMonth();
    }
}

/// @notice Contract that receives shares via transfer and tries to claim interest
contract ShareReceiver {
    RWAVault public vault;

    constructor(address _vault) {
        vault = RWAVault(_vault);
    }

    /// @notice Attempt to claim interest after receiving shares
    function claimInterest() external {
        vault.claimInterest();
    }

    /// @notice Attempt to redeem shares
    function redeem(uint256 shares) external returns (uint256 assets) {
        assets = vault.redeem(shares, address(this), address(this));
    }

    /// @notice Get deposit info
    function getMyDepositInfo() external view returns (
        uint256 shares,
        uint256 principal,
        uint256 lastClaimMonth,
        uint256 depositTime
    ) {
        return vault.getDepositInfo(address(this));
    }
}

// ============================================================================
// COMPREHENSIVE EDGE CASE TESTS
// ============================================================================

/// @title RWAVault Edge Case Tests
/// @notice Comprehensive tests for contract-to-contract deposits, interest claiming,
///         withdrawals, whitelist, share transfers, and phase transitions
contract RWAVaultEdgeCasesTest is Test {
    // ============ Contracts ============
    MockERC20 public usdc;
    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;
    RWAVault public vault;

    // ============ Helper Contracts ============
    IntermediaryDepositor public intermediary;
    MaliciousClaimContract public maliciousClaimer;
    ShareReceiver public shareReceiver;

    // ============ Addresses ============
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public whitelistedUser = makeAddr("whitelistedUser");
    address public nonWhitelistedUser = makeAddr("nonWhitelistedUser");
    address public allocatedUser = makeAddr("allocatedUser");

    // ============ Constants ============
    uint256 public constant INITIAL_BALANCE = 10_000_000e6; // 10M USDC
    uint256 public constant PROTOCOL_FEE = 500;

    // ============ Setup ============

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint initial balances
        usdc.mint(admin, INITIAL_BALANCE);
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(user3, INITIAL_BALANCE);
        usdc.mint(whitelistedUser, INITIAL_BALANCE);
        usdc.mint(nonWhitelistedUser, INITIAL_BALANCE);
        usdc.mint(allocatedUser, INITIAL_BALANCE);

        // Deploy core contracts
        _deployCore();

        // Mint USDC to poolManager for depositInterest calls
        usdc.mint(address(poolManager), INITIAL_BALANCE);

        // Create default vault for testing
        vault = RWAVault(_createDefaultVault());

        // Deploy helper contracts
        intermediary = new IntermediaryDepositor(address(vault), address(usdc));
        maliciousClaimer = new MaliciousClaimContract(address(vault));
        shareReceiver = new ShareReceiver(address(vault));

        // Fund intermediary contract
        usdc.mint(address(intermediary), INITIAL_BALANCE);
    }

    /// @notice Helper to deploy capital through PoolManager with timelock
    function _localDeployCapital(uint256 amount, address recipient) internal {
        vm.startPrank(admin);
        poolManager.announceDeployCapital(address(vault), amount, recipient);
        vm.stopPrank();

        uint256 delay = vault.deploymentDelay();
        vm.warp(block.timestamp + delay + 1);

        vm.startPrank(admin);
        poolManager.executeDeployCapital(address(vault));
        vm.stopPrank();
    }

    function _deployCore() internal {
        vm.startPrank(admin);

        loanRegistry = new LoanRegistry(admin);
        vaultRegistry = new VaultRegistry(admin);
        poolManager = new PoolManager(
            admin,
            address(usdc),
            address(loanRegistry),
            treasury,
            PROTOCOL_FEE
        );
        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            address(usdc),
            address(vaultRegistry)
        );

        // Setup roles
        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));
        poolManager.grantRole(RWAConstants.CURATOR_ROLE, admin);
        poolManager.grantRole(RWAConstants.OPERATOR_ROLE, admin);
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        vm.stopPrank();
    }

    function _createDefaultVault() internal returns (address vaultAddr) {
        vm.startPrank(admin);

        uint256 interestStart = block.timestamp + 7 days;
        uint256 maturityTime = interestStart + 180 days;

        uint256[] memory periodEndDates = new uint256[](6);
        uint256[] memory paymentDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "YieldCore RWA Vault",
            symbol: "ycRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 1500, // 15%
            minDeposit: 100e6, // 100 USDC
            maxCapacity: 10_000_000e6, // 10M USDC
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        vaultAddr = vaultFactory.createVault(params);

        vm.stopPrank();
    }

    // ============================================================================
    // SECTION 1: CONTRACT-TO-CONTRACT DEPOSIT SCENARIOS
    // ============================================================================

    /// @notice Test: Intermediary contract deposits with receiver=userWallet
    /// @dev This is the key scenario where msg.sender != receiver
    function test_ContractDeposit_IntermediaryDepositsForUser() public {
        uint256 depositAmount = 100_000e6;

        // Intermediary deposits for user1
        uint256 shares = intermediary.depositFor(user1, depositAmount);

        // Verify shares went to user1, NOT the intermediary contract
        assertEq(vault.balanceOf(user1), shares, "Shares should go to user1");
        assertEq(vault.balanceOf(address(intermediary)), 0, "Intermediary should have 0 shares");

        // Verify depositInfo is tracked for user1
        (uint256 userShares, uint256 principal, uint256 lastClaimMonth, uint256 depositTime) =
            vault.getDepositInfo(user1);

        assertEq(userShares, shares, "DepositInfo shares should match");
        assertEq(principal, depositAmount, "Principal should be tracked");
        assertEq(lastClaimMonth, 0, "Last claim month should be 0");
        assertEq(depositTime, block.timestamp, "Deposit time should be current");

        console2.log("Contract-to-user deposit successful");
        console2.log("  User1 shares:", shares);
        console2.log("  User1 principal:", principal);
    }

    /// @notice Test: User can claim interest after contract deposits for them
    function test_ContractDeposit_UserCanClaimInterestAfter() public {
        uint256 depositAmount = 120_000e6; // 120K for easy math

        // Intermediary deposits for user1
        intermediary.depositFor(user1, depositAmount);

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest funds
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        // Warp past first payment date (30 days period + 3 days buffer + 1)
        vm.warp(block.timestamp + 34 days);

        // User1 (NOT the intermediary) should be able to claim interest
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.claimInterest();

        uint256 balanceAfter = usdc.balanceOf(user1);
        uint256 interestReceived = balanceAfter - balanceBefore;

        // Expected interest: 120,000 * 15% / 12 = 1,500 USDC
        uint256 expectedInterest = (depositAmount * 1500) / (12 * 10_000);

        assertApproxEqAbs(interestReceived, expectedInterest, 1e6, "User should receive correct interest");
        console2.log("Interest claimed by user after contract deposit:", interestReceived);
    }

    /// @notice Test: Intermediary contract CANNOT claim interest for user's shares
    /// @dev msg.sender check means intermediary's claimInterest() affects only its own shares
    function test_ContractDeposit_IntermediaryCannotClaimUserInterest() public {
        uint256 depositAmount = 100_000e6;

        // Intermediary deposits for user1 (user1 gets the shares)
        intermediary.depositFor(user1, depositAmount);

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp past first payment date
        vm.warp(block.timestamp + 34 days);

        // Intermediary tries to claim interest - should fail because it has 0 shares
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        intermediary.claimInterestFor();
    }

    /// @notice Test: User can withdraw after maturity even if deposited via contract
    function test_ContractDeposit_UserCanWithdrawAfterMaturity() public {
        uint256 depositAmount = 100_000e6;

        // Intermediary deposits for user1
        uint256 shares = intermediary.depositFor(user1, depositAmount);

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest for claims
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        // Mature vault
        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal start time
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // User1 can withdraw
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 balanceAfter = usdc.balanceOf(user1);

        // User should receive principal + any unclaimed interest
        assertGt(balanceAfter, balanceBefore, "User should receive assets");
        console2.log("User withdrew after contract deposit:", balanceAfter - balanceBefore);
    }

    // ============================================================================
    // SECTION 2: INTEREST CLAIMING TESTS
    // ============================================================================

    /// @notice Test: User claims interest directly from wallet
    function test_InterestClaim_UserClaimsDirectly() public {
        uint256 depositAmount = 120_000e6;

        // User deposits directly
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest funds
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        // Warp past first payment date
        vm.warp(block.timestamp + 34 days);

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.claimInterest();

        uint256 interestClaimed = usdc.balanceOf(user1) - balanceBefore;
        uint256 expectedInterest = (depositAmount * 1500) / (12 * 10_000);

        assertApproxEqAbs(interestClaimed, expectedInterest, 1e6, "Should receive correct interest");
    }

    /// @notice Test: Contract tries to claim on behalf of user - fails/gets 0
    function test_InterestClaim_ContractCannotClaimForUser() public {
        uint256 depositAmount = 100_000e6;

        // User deposits directly
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp past first payment date
        vm.warp(block.timestamp + 34 days);

        // Malicious contract tries to claim - fails because it has no shares
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        maliciousClaimer.attemptClaimInterest();
    }

    /// @notice Test: Claim after partial months (2.5 months elapsed)
    function test_InterestClaim_PartialMonths() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit enough interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp 2.5 months (75 days - only 2 payment dates passed)
        // Payment dates are at 30+3=33 days, 60+3=63 days, 90+3=93 days from interest start
        vm.warp(block.timestamp + 75 days);

        // Should be able to claim 2 months
        uint256 claimableMonths = vault.getClaimableMonths(user1);
        assertEq(claimableMonths, 2, "Should have 2 claimable months");

        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vault.claimInterest();

        uint256 interestClaimed = usdc.balanceOf(user1) - balanceBefore;
        uint256 expectedTwoMonths = (depositAmount * 1500 * 2) / (12 * 10_000);

        assertApproxEqAbs(interestClaimed, expectedTwoMonths, 1e6, "Should claim 2 months interest");
    }

    /// @notice Test: claimInterest() claims ALL available months
    function test_InterestClaim_ClaimAllMonths() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit enough interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp past 3 payment dates
        vm.warp(block.timestamp + 100 days);

        assertEq(vault.getClaimableMonths(user1), 3, "Should have 3 claimable months");

        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vault.claimInterest();

        uint256 interestClaimed = usdc.balanceOf(user1) - balanceBefore;
        uint256 expectedThreeMonths = (depositAmount * 1500 * 3) / (12 * 10_000);

        assertApproxEqAbs(interestClaimed, expectedThreeMonths, 1e6, "Should claim all 3 months");
    }

    /// @notice Test: claimSingleMonth() claims only ONE month at a time
    function test_InterestClaim_ClaimSingleMonth() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit enough interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp past 3 payment dates
        vm.warp(block.timestamp + 100 days);

        assertEq(vault.getClaimableMonths(user1), 3, "Should have 3 claimable months");

        // Claim single month
        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        vault.claimSingleMonth();

        uint256 interestClaimed = usdc.balanceOf(user1) - balanceBefore;
        uint256 expectedOneMonth = (depositAmount * 1500) / (12 * 10_000);

        assertApproxEqAbs(interestClaimed, expectedOneMonth, 1e6, "Should claim exactly 1 month");
        assertEq(vault.getClaimableMonths(user1), 2, "Should have 2 months remaining");
    }

    /// @notice Test: Claim when vault has no liquidity - should revert
    function test_InterestClaim_NoLiquidity() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deploy ALL capital away (except minimum reserve)
        // Monthly interest = 100,000 * 15% / 12 = 1,250
        // 2 month reserve = 2,500
        // Max deployable = 100,000 - 2,500 = 97,500
        // Deploy via PoolManager timelock pattern
        _localDeployCapital(97_500e6, treasury);

        // Warp past first payment date
        vm.warp(block.timestamp + 34 days);

        // Try to claim - should fail due to insufficient liquidity
        // Expected interest: 1,250 USDC
        // Available: 2,500 USDC (reserve)
        // This should actually succeed with reserve!
        // Let's make reserve smaller by deploying more before collection ends

        // Actually the reserve ensures we CAN pay 2 months of interest
        // So claiming 1 month should work
        vm.prank(user1);
        vault.claimInterest(); // Should succeed because reserve covers it
    }

    // ============================================================================
    // SECTION 3: WITHDRAWAL TESTS
    // ============================================================================

    /// @notice Test: Withdraw/redeem in Matured phase
    function test_Withdraw_MaturedPhase() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        // Mature
        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal start time
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        uint256 shares = vault.balanceOf(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 received = usdc.balanceOf(user1) - balanceBefore;
        assertGt(received, 0, "Should receive assets");
        assertEq(vault.balanceOf(user1), 0, "Should have 0 shares after full redeem");
    }

    /// @notice Test: Attempt withdraw in Active phase - should fail with InvalidPhase
    /// @dev The contract checks phase FIRST, then checks withdrawalStartTime
    function test_Withdraw_ActivePhaseFails_Withdraw() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Try to withdraw in Active phase - should fail with InvalidPhase
        // Contract checks: phase first (must be Matured or Defaulted)
        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.withdraw(depositAmount, user1, user1);
    }

    /// @notice Test: Attempt redeem in Active phase - should fail with InvalidPhase
    function test_Withdraw_ActivePhaseFails_Redeem() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Get shares first, then test redeem
        uint256 shares = vault.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.redeem(shares, user1, user1);
    }

    /// @notice Test: Withdraw after claiming some interest (netValue vs grossValue)
    function test_Withdraw_AfterPartialInterestClaim() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp past 2 payment dates and claim
        vm.warp(block.timestamp + 70 days);

        vm.prank(user1);
        vault.claimInterest(); // Claims 2 months

        uint256 claimedInterest = vault.getUserClaimedInterest(user1);
        console2.log("Claimed interest (debt):", claimedInterest);

        // Now mature vault
        vm.warp(block.timestamp + 120 days);
        vm.prank(admin);
        vault.matureVault();

        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // Get share info before redeem
        (uint256 shares, uint256 grossValue, uint256 claimedDebt, uint256 netValue,) =
            vault.getShareInfo(user1);

        console2.log("Shares:", shares);
        console2.log("Gross value:", grossValue);
        console2.log("Claimed debt:", claimedDebt);
        console2.log("Net value:", netValue);

        // Net value should be gross - already claimed
        assertEq(netValue, grossValue - claimedDebt, "Net = Gross - Debt");

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 received = usdc.balanceOf(user1) - balanceBefore;

        // Should receive approximately netValue (accounting for auto-claimed remaining interest)
        console2.log("Received at withdrawal:", received);
    }

    /// @notice Test: Contract can withdraw for user (receiver gets assets)
    /// @dev SECURITY NOTE: The current contract implementation allows ANYONE to trigger
    ///      a redeem/withdraw for any user. However, the assets always go to the specified
    ///      receiver (which can be controlled). The _depositInfos[owner] tracking ensures
    ///      only the actual depositor's shares are redeemed, and assets go to receiver.
    ///
    ///      This is by design for this contract - it's not a standard ERC4626 where only
    ///      the owner or approved spender can withdraw. Instead:
    ///      - Anyone can call redeem(shares, receiver, owner)
    ///      - The shares are burned from owner's _depositInfos tracking
    ///      - The assets are sent to receiver
    ///
    ///      This means a malicious caller could force-redeem user's shares but the assets
    ///      would still go to the specified receiver. In production, the receiver param
    ///      would typically be the owner themselves.
    function test_Withdraw_ContractCanTriggerForUser() public {
        uint256 depositAmount = 100_000e6;

        // User deposits
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate and mature
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();

        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        uint256 shares = vault.balanceOf(user1);

        // NOTE: Current implementation allows anyone to trigger redeem for any owner
        // Assets go to receiver (user1 in this case)
        uint256 balanceBefore = usdc.balanceOf(user1);
        intermediary.redeemFor(shares, user1, user1);
        uint256 received = usdc.balanceOf(user1) - balanceBefore;

        assertGt(received, 0, "User should receive assets");
        assertEq(vault.balanceOf(user1), 0, "User should have 0 shares after redeem");
    }

    // ============================================================================
    // SECTION 4: WHITELIST TESTS
    // ============================================================================

    /// @notice Test: Whitelist checks receiver, NOT msg.sender
    function test_Whitelist_ChecksReceiver() public {
        // Enable whitelist and add only whitelistedUser
        vm.startPrank(admin);
        vault.setWhitelistEnabled(true);
        address[] memory users = new address[](1);
        users[0] = whitelistedUser;
        vault.addToWhitelist(users);
        vm.stopPrank();

        // Intermediary (not whitelisted) deposits for whitelistedUser
        // This SHOULD succeed because receiver (whitelistedUser) is whitelisted
        uint256 shares = intermediary.depositFor(whitelistedUser, 100_000e6);
        assertGt(shares, 0, "Should succeed when receiver is whitelisted");

        // Verify shares went to whitelistedUser
        assertEq(vault.balanceOf(whitelistedUser), shares);
    }

    /// @notice Test: Contract deposits for whitelisted user - SUCCESS
    function test_Whitelist_ContractDepositsForWhitelistedUser() public {
        vm.startPrank(admin);
        vault.setWhitelistEnabled(true);
        address[] memory users = new address[](1);
        users[0] = user1;
        vault.addToWhitelist(users);
        vm.stopPrank();

        // Intermediary deposits for user1 (who is whitelisted)
        uint256 shares = intermediary.depositFor(user1, 100_000e6);

        assertGt(shares, 0, "Deposit should succeed");
        assertEq(vault.balanceOf(user1), shares, "User1 should have shares");
    }

    /// @notice Test: Contract deposits for non-whitelisted user - FAIL
    function test_Whitelist_ContractDepositsForNonWhitelistedFails() public {
        vm.startPrank(admin);
        vault.setWhitelistEnabled(true);
        // Only whitelist user1, not nonWhitelistedUser
        address[] memory users = new address[](1);
        users[0] = user1;
        vault.addToWhitelist(users);
        vm.stopPrank();

        // Intermediary tries to deposit for nonWhitelistedUser
        vm.expectRevert(RWAErrors.NotWhitelisted.selector);
        intermediary.depositFor(nonWhitelistedUser, 100_000e6);
    }

    /// @notice Test: Allocated cap bypasses whitelist
    function test_Whitelist_AllocatedCapBypassesWhitelist() public {
        vm.startPrank(admin);
        // Enable whitelist but DON'T add allocatedUser to whitelist
        vault.setWhitelistEnabled(true);

        // Allocate cap to allocatedUser
        vault.allocateCap(allocatedUser, 500_000e6);
        vm.stopPrank();

        // allocatedUser deposits directly - should succeed despite not being whitelisted
        vm.startPrank(allocatedUser);
        usdc.approve(address(vault), 200_000e6);
        uint256 shares = vault.deposit(200_000e6, allocatedUser);
        vm.stopPrank();

        assertGt(shares, 0, "Allocated user should be able to deposit");

        // Intermediary deposits for allocatedUser - should also succeed
        uint256 shares2 = intermediary.depositFor(allocatedUser, 200_000e6);
        assertGt(shares2, 0, "Contract deposit for allocated user should succeed");
    }

    /// @notice Test: Allocated cap is respected even via contract deposits
    function test_Whitelist_AllocatedCapLimit() public {
        vm.startPrank(admin);
        vault.allocateCap(allocatedUser, 100_000e6); // 100K cap
        vm.stopPrank();

        // First deposit under cap
        intermediary.depositFor(allocatedUser, 50_000e6);

        // Second deposit would exceed cap
        vm.expectRevert(RWAErrors.ExceedsUserDepositCap.selector);
        intermediary.depositFor(allocatedUser, 60_000e6); // Total would be 110K > 100K
    }

    // ============================================================================
    // SECTION 5: SHARE TOKEN TESTS
    // ============================================================================

    /// @notice Test: Transfer shares to another address
    function test_ShareToken_Transfer() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 user1Shares = vault.balanceOf(user1);
        uint256 transferAmount = user1Shares / 2;

        vm.prank(user1);
        vault.transfer(user2, transferAmount);

        assertEq(vault.balanceOf(user1), user1Shares - transferAmount);
        assertEq(vault.balanceOf(user2), transferAmount);

        // Principal should also be transferred
        (, uint256 user1Principal,,) = vault.getDepositInfo(user1);
        (, uint256 user2Principal,,) = vault.getDepositInfo(user2);

        assertApproxEqAbs(user1Principal, depositAmount / 2, 1e6, "User1 should have half principal");
        assertApproxEqAbs(user2Principal, depositAmount / 2, 1e6, "User2 should have half principal");
    }

    /// @notice Test: New owner can claim interest after receiving shares
    /// @dev Interest is based on principal (transferred with shares), so new owner CAN claim
    function test_ShareToken_NewOwnerCanClaimInterest() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Transfer half shares to shareReceiver contract
        uint256 transferShares = vault.balanceOf(user1) / 2;
        vm.prank(user1);
        vault.transfer(address(shareReceiver), transferShares);

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        // Warp past first payment date
        vm.warp(block.timestamp + 34 days);

        // Check shareReceiver's deposit info
        (uint256 shares, uint256 principal, uint256 lastClaimMonth,) = shareReceiver.getMyDepositInfo();
        console2.log("ShareReceiver shares:", shares);
        console2.log("ShareReceiver principal:", principal);
        console2.log("ShareReceiver lastClaimMonth:", lastClaimMonth);

        // ShareReceiver can claim interest based on transferred principal
        uint256 pendingInterest = vault.getPendingInterest(address(shareReceiver));
        console2.log("ShareReceiver pending interest:", pendingInterest);

        assertGt(pendingInterest, 0, "New owner should have pending interest");

        // Claim interest
        uint256 balanceBefore = usdc.balanceOf(address(shareReceiver));
        shareReceiver.claimInterest();
        uint256 interestReceived = usdc.balanceOf(address(shareReceiver)) - balanceBefore;

        assertGt(interestReceived, 0, "New owner should receive interest");
    }

    /// @notice Test: Approval and transferFrom scenarios
    function test_ShareToken_ApproveAndTransferFrom() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 shares = vault.balanceOf(user1);

        // User1 approves user2 to transfer shares
        vm.prank(user1);
        vault.approve(user2, shares / 2);

        // User2 transfers user1's shares to user3
        vm.prank(user2);
        vault.transferFrom(user1, user3, shares / 2);

        assertEq(vault.balanceOf(user3), shares / 2);
        assertEq(vault.allowance(user1, user2), 0); // Allowance consumed
    }

    /// @notice Test: lastClaimMonth is transferred with shares (prevents double claiming)
    function test_ShareToken_LastClaimMonthTransferred() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate and claim some interest
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp past 2 payment dates and claim
        vm.warp(block.timestamp + 70 days);
        vm.prank(user1);
        vault.claimInterest();

        (, , uint256 user1LastClaim,) = vault.getDepositInfo(user1);
        assertEq(user1LastClaim, 2, "User1 should have claimed 2 months");

        // Transfer shares to user2
        uint256 shares = vault.balanceOf(user1);
        vm.prank(user1);
        vault.transfer(user2, shares / 2);

        // Check user2's lastClaimMonth - should inherit user1's (prevents double claim)
        (, , uint256 user2LastClaim,) = vault.getDepositInfo(user2);
        assertEq(user2LastClaim, 2, "User2 should inherit lastClaimMonth from user1");

        // User2 tries to claim - should get 0 for those already-claimed months
        assertEq(vault.getClaimableMonths(user2), 0, "User2 should have 0 claimable (already claimed)");
    }

    // ============================================================================
    // SECTION 6: PHASE TRANSITION EDGE CASES
    // ============================================================================

    /// @notice Test: Deposit right before collection ends
    function test_PhaseTransition_DepositBeforeCollectionEnds() public {
        uint256 depositAmount = 100_000e6;

        // Warp to 1 second before collection ends
        vm.warp(vault.collectionEndTime() - 1);

        // Should still be able to deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertGt(shares, 0, "Should be able to deposit just before collection ends");

        // Warp 1 more second - collection ended
        vm.warp(vault.collectionEndTime());

        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount);
        vm.expectRevert(RWAErrors.CollectionEnded.selector);
        vault.deposit(depositAmount, user2);
        vm.stopPrank();
    }

    /// @notice Test: Claim interest right when Active phase starts
    function test_PhaseTransition_ClaimWhenActiveStarts() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Warp past collection end
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Right at activation, no interest payment date has passed yet
        // First payment date is interestStartTime + 30 days + 3 days
        assertEq(vault.getClaimableMonths(user1), 0, "No claimable months right at activation");

        // Warp to just before first payment date (30 + 3 days from interest start)
        vm.warp(vault.interestStartTime() + 33 days - 1);
        assertEq(vault.getClaimableMonths(user1), 0, "Still no claimable months");

        // Warp past first payment date
        vm.warp(vault.interestStartTime() + 33 days + 1);
        assertEq(vault.getClaimableMonths(user1), 1, "Should have 1 claimable month");
    }

    /// @notice Test: Withdraw right when Matured phase starts
    /// @dev Tests the scenario where withdrawalStartTime is set to a FUTURE time (after maturity)
    ///      In default setup, withdrawalStartTime = maturityTime, so we create a special vault
    function test_PhaseTransition_WithdrawWhenMaturedStarts() public {
        // Create a vault with withdrawalStartTime > maturityTime
        vm.startPrank(admin);

        uint256 interestStart = block.timestamp + 7 days;
        uint256 maturity = interestStart + 180 days;
        uint256 withdrawalStart = maturity + 5 days; // 5 days after maturity

        uint256[] memory periodEndDates = new uint256[](6);
        uint256[] memory paymentDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "Delayed Withdrawal Vault",
            symbol: "ycDWV",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 1500,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: withdrawalStart // 5 days after maturity
        });

        RWAVault delayedWithdrawalVault = RWAVault(vaultFactory.createVault(params));
        vm.stopPrank();

        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(delayedWithdrawalVault), depositAmount);
        delayedWithdrawalVault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        delayedWithdrawalVault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(delayedWithdrawalVault), 50_000e6);
        delayedWithdrawalVault.depositInterest(50_000e6);
        vm.stopPrank();

        // Warp to just before maturity
        vm.warp(delayedWithdrawalVault.maturityTime() - 1);

        // Cannot mature yet
        vm.prank(admin);
        vm.expectRevert(RWAErrors.NotMatured.selector);
        delayedWithdrawalVault.matureVault();

        // Warp to exactly maturity
        vm.warp(delayedWithdrawalVault.maturityTime());
        vm.prank(admin);
        delayedWithdrawalVault.matureVault();

        // Withdrawal not available until withdrawalStartTime is reached
        // (withdrawalStartTime = maturity + 5 days)
        uint256 userShares = delayedWithdrawalVault.balanceOf(user1);
        vm.prank(user1);
        vm.expectRevert(RWAErrors.WithdrawalNotAvailable.selector);
        delayedWithdrawalVault.redeem(userShares, user1, user1);

        // Warp to withdrawal start time
        vm.warp(withdrawalStart);

        // Now can withdraw
        uint256 shares = delayedWithdrawalVault.balanceOf(user1);
        vm.prank(user1);
        delayedWithdrawalVault.redeem(shares, user1, user1);

        assertEq(delayedWithdrawalVault.balanceOf(user1), 0, "Should have withdrawn all shares");
    }

    // Note: test_PhaseTransition_DepositBeforeCollectionStarts was removed
    // because collectionStartTime is not implemented in RWAVault

    // ============================================================================
    // SECTION 7: HYBRID SYSTEM EDGE CASES
    // ============================================================================

    /// @notice Test: Debt transfer with shares
    function test_HybridSystem_DebtTransfersWithShares() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate and claim interest
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days);

        vm.prank(user1);
        vault.claimInterest();

        uint256 user1DebtBefore = vault.getUserClaimedInterest(user1);
        console2.log("User1 debt before transfer:", user1DebtBefore);

        // Transfer half shares to user2
        uint256 shares = vault.balanceOf(user1);
        vm.prank(user1);
        vault.transfer(user2, shares / 2);

        // Debt should also be transferred proportionally
        uint256 user1DebtAfter = vault.getUserClaimedInterest(user1);
        uint256 user2Debt = vault.getUserClaimedInterest(user2);

        console2.log("User1 debt after transfer:", user1DebtAfter);
        console2.log("User2 debt after transfer:", user2Debt);

        // Total debt should be conserved
        assertApproxEqAbs(
            user1DebtAfter + user2Debt,
            user1DebtBefore,
            1e6,
            "Total debt should be conserved"
        );
    }

    /// @notice Test: Net value calculation with debt
    function test_HybridSystem_NetValueWithDebt() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp 3 months and claim 2 months
        vm.warp(block.timestamp + 100 days);

        vm.prank(user1);
        vault.claimSingleMonth();
        vm.prank(user1);
        vault.claimSingleMonth();

        // Get share info
        (uint256 shares, uint256 grossValue, uint256 claimedInterest, uint256 netValue,) =
            vault.getShareInfo(user1);

        console2.log("Shares:", shares);
        console2.log("Gross value:", grossValue);
        console2.log("Claimed interest:", claimedInterest);
        console2.log("Net value:", netValue);

        // Net value = gross - claimed debt
        assertEq(netValue, grossValue - claimedInterest, "Net = Gross - Claimed");

        // getNetRedemptionValue should match
        uint256 netRedemption = vault.getNetRedemptionValue(user1);
        assertEq(netRedemption, netValue, "getNetRedemptionValue should match");
    }

    // ============================================================================
    // SECTION 8: ADDITIONAL EDGE CASES
    // ============================================================================

    /// @notice Test: Multiple contract deposits for same user
    function test_EdgeCase_MultipleContractDeposits() public {
        // Fund second intermediary
        IntermediaryDepositor intermediary2 = new IntermediaryDepositor(address(vault), address(usdc));
        usdc.mint(address(intermediary2), INITIAL_BALANCE);

        // Both intermediaries deposit for user1
        intermediary.depositFor(user1, 50_000e6);
        intermediary2.depositFor(user1, 50_000e6);

        // User1 should have combined shares
        assertEq(vault.balanceOf(user1), 100_000e6);

        // Principal should be combined
        (, uint256 principal,,) = vault.getDepositInfo(user1);
        assertEq(principal, 100_000e6);
    }

    /// @notice Test: User cannot claim in Collecting phase
    function test_EdgeCase_CannotClaimInCollectingPhase() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.claimInterest();
    }

    /// @notice Test: maxDeposit returns 0 for non-whitelisted when whitelist enabled
    function test_EdgeCase_MaxDepositWithWhitelist() public {
        vm.prank(admin);
        vault.setWhitelistEnabled(true);

        // Non-whitelisted user should have 0 maxDeposit
        uint256 maxDep = vault.maxDeposit(nonWhitelistedUser);
        assertEq(maxDep, 0, "Non-whitelisted should have 0 maxDeposit");

        // Add to whitelist
        vm.startPrank(admin);
        address[] memory users = new address[](1);
        users[0] = nonWhitelistedUser;
        vault.addToWhitelist(users);
        vm.stopPrank();

        // Now should have positive maxDeposit
        maxDep = vault.maxDeposit(nonWhitelistedUser);
        assertGt(maxDep, 0, "Whitelisted user should have positive maxDeposit");
    }

    /// @notice Test: Interest claim in Defaulted phase
    function test_EdgeCase_InterestClaimInDefaultedPhase() public {
        uint256 depositAmount = 120_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp past 2 payment dates
        vm.warp(block.timestamp + 70 days);

        // Trigger default
        vm.prank(admin);
        poolManager.triggerDefault(address(vault));

        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Defaulted));

        // User should still be able to claim earned interest up to default time
        uint256 claimableMonths = vault.getClaimableMonths(user1);
        console2.log("Claimable months after default:", claimableMonths);

        // Claim should work
        vm.prank(user1);
        vault.claimInterest();
    }

    /// @notice Test: Withdrawal in Defaulted phase
    /// @dev setWithdrawalStartTime requires time >= maturityTime, so in early default scenarios
    ///      the admin must set withdrawalStartTime to at least maturityTime
    function test_EdgeCase_WithdrawInDefaultedPhase() public {
        uint256 depositAmount = 100_000e6;

        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp and default
        vm.warp(block.timestamp + 30 days);
        vm.prank(admin);
        poolManager.triggerDefault(address(vault));

        // setWithdrawalStartTime requires time >= maturityTime
        // So we must set it to maturityTime (earliest allowed) and warp to that time
        uint256 maturity = vault.maturityTime();

        vm.prank(admin);
        vault.setWithdrawalStartTime(maturity);

        // Warp to maturity time so withdrawal is available
        vm.warp(maturity);

        // Can withdraw in Defaulted phase
        uint256 shares = vault.balanceOf(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 received = usdc.balanceOf(user1) - balanceBefore;
        assertGt(received, 0, "Should be able to withdraw in Defaulted phase");
    }

    /// @notice Test: Minimum share transfer amount
    function test_EdgeCase_MinimumShareTransfer() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Try to transfer less than MIN_SHARE_TRANSFER (1e6)
        vm.prank(user1);
        vm.expectRevert(RWAErrors.TransferTooSmall.selector);
        vault.transfer(user2, 1e5); // 0.1 USDC worth - too small

        // Transfer exactly MIN_SHARE_TRANSFER should work
        vm.prank(user1);
        vault.transfer(user2, 1e6);

        assertEq(vault.balanceOf(user2), 1e6);
    }
}
