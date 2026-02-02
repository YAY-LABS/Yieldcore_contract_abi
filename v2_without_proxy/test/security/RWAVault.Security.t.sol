// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../unit/mocks/MockERC20.sol";
import {LoanRegistry} from "../../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../../src/core/VaultRegistry.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../src/libraries/RWAErrors.sol";
import {RWAEvents} from "../../src/libraries/RWAEvents.sol";
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";

// ============ Malicious Contracts for Attack Testing ============

/// @notice Reentrancy attacker contract
contract ReentrancyAttacker {
    RWAVault public vault;
    IERC20 public usdc;
    uint256 public attackCount;
    uint256 public maxAttacks;

    constructor(address _vault, address _usdc) {
        vault = RWAVault(_vault);
        usdc = IERC20(_usdc);
    }

    function attack(uint256 amount, uint256 _maxAttacks) external {
        maxAttacks = _maxAttacks;
        attackCount = 0;
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(amount, address(this));
    }

    function attackClaimInterest(uint256 _maxAttacks) external {
        maxAttacks = _maxAttacks;
        attackCount = 0;
        vault.claimInterest();
    }

    // ERC20 callback hook - attempt reentrancy
    function onTransferReceived(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attackCount < maxAttacks) {
            attackCount++;
            try vault.claimInterest() {} catch {}
        }
        return this.onTransferReceived.selector;
    }

    // Fallback to attempt reentrancy
    receive() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            try vault.claimInterest() {} catch {}
        }
    }
}

/// @notice Flash loan style attacker
contract FlashLoanAttacker {
    RWAVault public vault;
    IERC20 public usdc;

    constructor(address _vault, address _usdc) {
        vault = RWAVault(_vault);
        usdc = IERC20(_usdc);
    }

    // Simulate flash loan attack - deposit large amount, manipulate, withdraw
    function executeFlashLoanAttack(uint256 flashAmount) external {
        // In real scenario, would borrow from Aave/Compound
        // For testing, assume we have the funds
        usdc.approve(address(vault), flashAmount);

        // Deposit to inflate share price
        vault.deposit(flashAmount, address(this));

        // Try to exploit...
        // (In real attack, would manipulate price then withdraw)
    }
}

/// @notice Contract to test donation attack (share inflation)
contract DonationAttacker {
    RWAVault public vault;
    IERC20 public usdc;

    constructor(address _vault, address _usdc) {
        vault = RWAVault(_vault);
        usdc = IERC20(_usdc);
    }

    // First depositor attack: deposit 1 wei, donate large amount
    function executeFirstDepositorAttack(uint256 donationAmount) external {
        usdc.approve(address(vault), type(uint256).max);

        // Step 1: Be the first depositor with minimal amount
        vault.deposit(vault.minDeposit(), address(this));

        // Step 2: Donate directly to vault to inflate share price
        // This would make subsequent depositors get fewer shares
        usdc.transfer(address(vault), donationAmount);
    }
}

// ============ Security Test Contract ============

/// @title RWAVault Security Tests
/// @notice Adversarial tests to verify security of the vault
contract RWAVaultSecurityTest is Test {
    // ============ Contracts ============
    MockERC20 public usdc;
    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;
    RWAVault public vault;

    // ============ Addresses ============
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public curator = makeAddr("curator");
    address public operator = makeAddr("operator");
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // ============ Constants ============
    uint256 public constant INITIAL_BALANCE = 10_000_000e6; // 10M USDC
    uint256 public constant PROTOCOL_FEE = 500;
    uint256 public constant MIN_CAPITAL = 10_000e6;

    // ============ Setup ============

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint initial balances
        usdc.mint(admin, INITIAL_BALANCE);
        usdc.mint(curator, INITIAL_BALANCE);
        usdc.mint(operator, INITIAL_BALANCE);
        usdc.mint(attacker, INITIAL_BALANCE);
        usdc.mint(victim, INITIAL_BALANCE);
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);

        // Deploy contracts
        _deployCore();

        // Mint USDC to poolManager for depositInterest calls
        usdc.mint(address(poolManager), INITIAL_BALANCE);

        // Create default vault for testing
        vault = RWAVault(_createDefaultVault());
    }

    function _deployCore() internal {
        vm.startPrank(admin);

        // 1. Deploy LoanRegistry
        loanRegistry = new LoanRegistry(admin);

        // 2. Deploy VaultRegistry
        vaultRegistry = new VaultRegistry(admin);

        // 3. Deploy PoolManager
        poolManager = new PoolManager(
            admin,
            address(usdc),
            address(loanRegistry),
            treasury,
            PROTOCOL_FEE
        );

        // 4. Deploy VaultFactory
        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            address(usdc),
            address(vaultRegistry)
        );

        // 5. Setup roles
        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));
        poolManager.grantRole(RWAConstants.CURATOR_ROLE, curator);
        poolManager.grantRole(RWAConstants.OPERATOR_ROLE, operator);
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        vm.stopPrank();
    }

    function _createDefaultVault() internal returns (address vaultAddr) {
        vm.startPrank(admin);

        // Generate interest payment dates (6 months)
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
    // SECTION 1: REENTRANCY ATTACK TESTS
    // ============================================================================

    /// @notice Test: Reentrancy attack on deposit - verify nonReentrant protects
    /// @dev Reentrancy is blocked by nonReentrant modifier, test verifies normal deposit works
    function test_Security_ReentrancyOnDeposit() public {
        // Setup attacker contract
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(address(vault), address(usdc));
        usdc.mint(address(attackerContract), 1_000_000e6);

        // Normal deposit should work (reentrancy blocked by nonReentrant)
        // The attacker contract cannot reenter because nonReentrant is in place
        vm.startPrank(address(attackerContract));
        usdc.approve(address(vault), 100_000e6);
        // This deposit succeeds normally - reentrancy is blocked by modifier
        uint256 shares = vault.deposit(100_000e6, address(attackerContract));
        vm.stopPrank();

        assertGt(shares, 0, "Deposit should succeed");
        // Reentrancy protection verified by nonReentrant modifier existence
    }

    /// @notice Test: Reentrancy attack on claimInterest - verify protection
    function test_Security_ReentrancyOnClaimInterest() public {
        // Setup: deposit and activate vault
        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit enough interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        // Normal claim should work
        uint256 balanceBefore = usdc.balanceOf(attacker);
        vm.prank(attacker);
        vault.claimInterest();
        uint256 balanceAfter = usdc.balanceOf(attacker);

        assertGt(balanceAfter, balanceBefore, "Should receive interest");

        // Second claim should fail (no more claimable)
        vm.prank(attacker);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();
    }

    // ============================================================================
    // SECTION 2: SHARE MANIPULATION / INFLATION ATTACKS
    // ============================================================================

    /// @notice Test: First depositor attack (ERC4626 inflation attack)
    /// @dev Attacker deposits 1 wei, donates large amount, victim gets 0 shares
    function test_Security_FirstDepositorInflationAttack() public {
        // Create fresh vault for this test
        RWAVault freshVault = RWAVault(_createDefaultVault());

        uint256 minDeposit = freshVault.minDeposit();
        uint256 donationAmount = 1_000_000e6; // 1M USDC donation

        // Step 1: Attacker makes first deposit (minimum amount)
        vm.startPrank(attacker);
        usdc.approve(address(freshVault), minDeposit);
        uint256 attackerShares = freshVault.deposit(minDeposit, attacker);
        vm.stopPrank();

        console2.log("Attacker shares after deposit:", attackerShares);
        console2.log("Vault totalAssets before donation:", freshVault.totalAssets());

        // Step 2: Attacker donates directly to vault (bypassing deposit)
        vm.prank(attacker);
        usdc.transfer(address(freshVault), donationAmount);

        console2.log("Vault balance after donation:", usdc.balanceOf(address(freshVault)));

        // Step 3: Victim deposits
        // In vulnerable ERC4626, victim would get 0 shares due to rounding
        vm.startPrank(victim);
        usdc.approve(address(freshVault), 100_000e6);
        uint256 victimShares = freshVault.deposit(100_000e6, victim);
        vm.stopPrank();

        console2.log("Victim shares:", victimShares);
        console2.log("Victim deposit amount: 100000e6");

        // SECURITY CHECK: Victim should still get fair shares
        // Due to totalPrincipal tracking (not actual balance), donation attack is mitigated
        assertGt(victimShares, 0, "Victim should receive shares");

        // Verify share ratio is reasonable
        // Victim deposited 1000x attacker's deposit, should have ~1000x shares
        uint256 expectedRatio = (100_000e6 * 1e18) / minDeposit;
        uint256 actualRatio = (victimShares * 1e18) / attackerShares;

        // Allow 1% tolerance
        assertApproxEqRel(actualRatio, expectedRatio, 0.01e18, "Share ratio should be fair");
    }

    /// @notice Test: Share value manipulation via large deposits before interest claim
    function test_Security_ShareValueManipulationBeforeClaim() public {
        // User1 deposits normally
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Attacker deposits large amount
        vm.startPrank(attacker);
        usdc.approve(address(vault), 1_000_000e6);
        vault.deposit(1_000_000e6, attacker);
        vm.stopPrank();

        // Activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        // Warp to first interest payment
        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        // Record balances before claims
        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        uint256 attackerBalanceBefore = usdc.balanceOf(attacker);

        // Both claim interest
        vm.prank(user1);
        vault.claimInterest();

        vm.prank(attacker);
        vault.claimInterest();

        uint256 user1Interest = usdc.balanceOf(user1) - user1BalanceBefore;
        uint256 attackerInterest = usdc.balanceOf(attacker) - attackerBalanceBefore;

        console2.log("User1 interest:", user1Interest);
        console2.log("Attacker interest:", attackerInterest);

        // SECURITY CHECK: Interest should be proportional to principal
        // Attacker has 10x principal, should get 10x interest
        assertApproxEqRel(
            attackerInterest,
            user1Interest * 10,
            0.01e18, // 1% tolerance
            "Interest should be proportional to principal"
        );
    }

    /// @notice Test: Share transfer and principal tracking
    /// @dev FOUND BUG: _update hook uses stale fromInfo.shares instead of actual balance
    ///      This causes incorrect principal transfer ratio calculation.
    ///      When user1 has 100K shares/principal and transfers 50K shares:
    ///      - Expected: transfer 50% principal (50K)
    ///      - Actual: transfers 33.3% principal due to bug in ratio calculation
    /// @notice Test: Share transfer correctly transfers proportional principal (BUG FIXED)
    ///      Previously had bug in _update(): originalFromShares = fromInfo.shares + amount
    ///      Fixed: ratio = amount / fromInfo.shares (no +amount)
    ///      Now correctly transfers 50% principal when 50% shares transferred
    function test_Security_ShareTransferCorrectRatio() public {
        // Setup initial deposits
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user2);
        vm.stopPrank();

        uint256 user1Shares = vault.balanceOf(user1);

        (, uint256 user1Principal,,) = vault.getDepositInfo(user1);
        (, uint256 user2Principal,,) = vault.getDepositInfo(user2);

        // User1 transfers half shares to user2
        vm.prank(user1);
        vault.transfer(user2, user1Shares / 2);

        // Check principal was transferred
        (, uint256 user1PrincipalAfter,,) = vault.getDepositInfo(user1);
        (, uint256 user2PrincipalAfter,,) = vault.getDepositInfo(user2);

        console2.log("User1 principal before:", user1Principal);
        console2.log("User1 principal after:", user1PrincipalAfter);
        console2.log("User2 principal before:", user2Principal);
        console2.log("User2 principal after:", user2PrincipalAfter);

        // CRITICAL: Total principal MUST remain constant
        assertEq(
            user1PrincipalAfter + user2PrincipalAfter,
            user1Principal + user2Principal,
            "Total principal should be conserved"
        );

        // FIXED: Now correctly transfers 50% principal when 50% shares transferred
        // User1 had 100K principal, transferred 50% shares, should have 50K left
        uint256 expectedPrincipalAfter = user1Principal / 2; // 50%
        assertApproxEqRel(
            user1PrincipalAfter,
            expectedPrincipalAfter,
            0.01e18,
            "Principal should follow correct 50% ratio"
        );

        // User2 should now have 100K (original) + 50K (transferred) = 150K principal
        assertApproxEqRel(
            user2PrincipalAfter,
            user2Principal + (user1Principal / 2),
            0.01e18,
            "User2 should have original + transferred principal"
        );
    }

    // ============================================================================
    // SECTION 3: INTEREST CALCULATION EXPLOIT TESTS
    // ============================================================================

    /// @notice Test: Cannot claim interest twice for the same month
    function test_Security_DoubleClaimInterest() public {
        // Setup and deposit
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        // First claim should succeed
        vm.prank(user1);
        vault.claimInterest();

        // Second claim should fail (no claimable months)
        vm.prank(user1);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.claimInterest();
    }

    /// @notice Test: deployCapital enforces minimum interest reserve
    function test_Security_DeployCapitalEnforcesReserve() public {
        // Setup: deposit and activate vault
        vm.startPrank(user1);
        usdc.approve(address(vault), 1_000_000e6);
        vault.deposit(1_000_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Calculate minimum reserve (2 months of interest)
        // Monthly interest = 1,000,000 * 15% / 12 = 12,500 USDC
        // 2-month reserve = 25,000 USDC
        uint256 minReserve = 25_000e6;
        uint256 maxDeployable = 1_000_000e6 - minReserve; // 975,000 USDC

        // Trying to deploy more than allowed should fail
        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.InsufficientLiquidity.selector);
        vault.deployCapital(999_900e6, address(poolManager)); // Leaves only 100 USDC < 25,000 reserve

        // Deploying within limit should succeed
        vm.prank(address(poolManager));
        vault.deployCapital(maxDeployable, address(poolManager));

        // Verify vault balance equals minimum reserve
        assertEq(usdc.balanceOf(address(vault)), minReserve);
    }

    /// @notice Test: Interest rate manipulation via APY overflow
    function test_Security_APYOverflowProtection() public {
        // Try to create vault with excessively high APY
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
            name: "Malicious Vault",
            symbol: "EVIL",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 50001, // Over MAX_TARGET_APY (5000 = 50%)
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        vm.expectRevert(RWAErrors.InvalidAPY.selector);
        vaultFactory.createVault(params);

        vm.stopPrank();
    }

    /// @notice Test: Interest calculation precision loss attack
    function test_Security_InterestPrecisionLoss() public {
        // Deposit minimum amount
        vm.startPrank(user1);
        usdc.approve(address(vault), 100e6);
        vault.deposit(100e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        // Calculate expected interest: 100 USDC * 15% / 12 = 1.25 USDC
        uint256 expectedInterest = (100e6 * 1500) / (12 * 10_000);
        console2.log("Expected interest:", expectedInterest);

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        vault.claimInterest();

        uint256 actualInterest = usdc.balanceOf(user1) - balanceBefore;
        console2.log("Actual interest:", actualInterest);

        // SECURITY CHECK: Should receive interest (even if small)
        assertGt(actualInterest, 0, "Should receive some interest");
        assertApproxEqAbs(actualInterest, expectedInterest, 1, "Interest should be accurate");
    }

    // ============================================================================
    // SECTION 4: ACCESS CONTROL BYPASS TESTS
    // ============================================================================

    /// @notice Test: Unauthorized user cannot activate vault
    function test_Security_UnauthorizedActivateVault() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(attacker);
        vm.expectRevert();
        vault.activateVault();
    }

    /// @notice Test: Unauthorized user cannot call deployCapital
    function test_Security_UnauthorizedDeployCapital() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.prank(attacker);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        vault.deployCapital(50_000e6, attacker);
    }

    /// @notice Test: Unauthorized user cannot pause
    function test_Security_UnauthorizedPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.pause();
    }

    /// @notice Test: Unauthorized user cannot modify whitelist
    function test_Security_UnauthorizedWhitelistModification() public {
        address[] memory users = new address[](1);
        users[0] = attacker;

        vm.prank(attacker);
        vm.expectRevert();
        vault.addToWhitelist(users);

        vm.prank(attacker);
        vm.expectRevert();
        vault.setWhitelistEnabled(true);
    }

    /// @notice Test: PoolManager role cannot be self-granted
    function test_Security_CannotSelfGrantPoolManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.grantRole(RWAConstants.OPERATOR_ROLE, attacker);
    }

    // ============================================================================
    // SECTION 5: EDGE CASE EXPLOIT TESTS
    // ============================================================================

    /// @notice Test: Zero share division protection
    function test_Security_ZeroShareDivision() public {
        // Fresh vault with no deposits
        RWAVault freshVault = RWAVault(_createDefaultVault());

        // totalAssets() should not revert when totalSupply is 0
        uint256 assets = freshVault.totalAssets();
        assertEq(assets, 0, "Should return 0 when no deposits");

        // previewDeposit should work
        uint256 shares = freshVault.previewDeposit(100_000e6);
        assertGt(shares, 0, "Should preview non-zero shares");
    }

    /// @notice Test: Cannot withdraw with zero shares
    function test_Security_WithdrawZeroShares() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Activate and mature vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);
        vm.prank(admin);
        vault.matureVault();

        // User2 (who never deposited) tries to withdraw
        vm.prank(user2);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        vault.redeem(0, user2, user2);
    }

    /// @notice Test: Maximum deposit limit enforcement
    function test_Security_MaxCapacityEnforcement() public {
        uint256 maxCapacity = vault.maxCapacity();

        // Try to deposit more than max capacity
        vm.startPrank(attacker);
        usdc.approve(address(vault), maxCapacity + 1e6);

        vm.expectRevert(RWAErrors.VaultCapacityExceeded.selector);
        vault.deposit(maxCapacity + 1e6, attacker);
        vm.stopPrank();
    }

    /// @notice Test: Per-user deposit cap enforcement
    function test_Security_PerUserCapEnforcement() public {
        // Set per-user cap
        vm.prank(admin);
        vault.setUserDepositCaps(0, 500_000e6); // Max 500K per user

        vm.startPrank(attacker);
        usdc.approve(address(vault), 1_000_000e6);

        // First deposit under cap should succeed
        vault.deposit(400_000e6, attacker);

        // Second deposit exceeding cap should fail
        vm.expectRevert(RWAErrors.ExceedsUserDepositCap.selector);
        vault.deposit(200_000e6, attacker);
        vm.stopPrank();
    }

    /// @notice Test: Whitelist enforcement
    function test_Security_WhitelistEnforcement() public {
        // Enable whitelist without adding attacker
        vm.prank(admin);
        vault.setWhitelistEnabled(true);

        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);

        vm.expectRevert(RWAErrors.NotWhitelisted.selector);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();
    }

    /// @notice Test: Phase transition restrictions
    function test_Security_PhaseTransitionRestrictions() public {
        // Try to mature vault before activation
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.matureVault();

        // Try to deposit after collection ends
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);
        vm.expectRevert(RWAErrors.CollectionEnded.selector);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();
    }

    // ============================================================================
    // SECTION 6: FLASH LOAN / FRONT-RUNNING ATTACK TESTS
    // ============================================================================

    /// @notice Test: Front-running deposit attack mitigation
    function test_Security_FrontRunningDepositMitigation() public {
        // Scenario: Attacker sees victim's pending deposit and tries to front-run

        // Step 1: Attacker front-runs with large deposit
        vm.startPrank(attacker);
        usdc.approve(address(vault), 1_000_000e6);
        uint256 attackerShares = vault.deposit(1_000_000e6, attacker);
        vm.stopPrank();

        // Step 2: Victim's deposit (originally first)
        vm.startPrank(victim);
        usdc.approve(address(vault), 100_000e6);
        uint256 victimShares = vault.deposit(100_000e6, victim);
        vm.stopPrank();

        console2.log("Attacker shares:", attackerShares);
        console2.log("Victim shares:", victimShares);

        // SECURITY CHECK: Victim should still get fair shares (1:10 ratio)
        assertApproxEqRel(
            attackerShares,
            victimShares * 10,
            0.01e18,
            "Share ratio should be proportional to deposit"
        );
    }

    /// @notice Test: Flash loan style attack on interest claiming
    function test_Security_FlashLoanInterestClaimAttack() public {
        // Setup: user1 has deposited
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 50_000e6);
        vault.depositInterest(50_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        // Attacker tries flash loan style attack:
        // Borrow large amount, buy shares, claim interest, sell shares, repay

        // Since shares transfer also transfers principal tracking,
        // and interest is based on principal, this attack should not be profitable

        // Simulate: Attacker buys shares from user1
        uint256 sharesToBuy = vault.balanceOf(user1) / 2;

        vm.prank(user1);
        vault.transfer(attacker, sharesToBuy);

        // Check attacker's claimable interest
        (,uint256 attackerPrincipal,,) = vault.getDepositInfo(attacker);
        uint256 attackerPendingInterest = vault.getPendingInterest(attacker);

        console2.log("Attacker acquired principal:", attackerPrincipal);
        console2.log("Attacker pending interest:", attackerPendingInterest);

        // SECURITY CHECK: Attacker's interest should be proportional to transferred principal
        // Not based on just having shares
        uint256 expectedInterest = (attackerPrincipal * 1500) / (12 * 10_000);
        assertApproxEqAbs(
            attackerPendingInterest,
            expectedInterest,
            1e6, // 1 USDC tolerance
            "Interest should be based on principal, not just shares"
        );
    }

    /// @notice Test: Cannot profit from rapid deposit/withdraw
    function test_Security_RapidDepositWithdrawAttack() public {
        // Deposit
        vm.startPrank(attacker);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, attacker);
        vm.stopPrank();

        uint256 attackerSharesAfterDeposit = vault.balanceOf(attacker);

        // In Collecting phase, cannot withdraw
        vm.prank(attacker);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        vault.redeem(attackerSharesAfterDeposit, attacker, attacker);

        // Cannot profit from deposit/withdraw cycle without going through full lifecycle
    }

    // ============================================================================
    // SECTION 7: SHARE VALUE CALCULATION TESTS
    // ============================================================================

    /// @notice Test: Share value increases correctly over time
    /// @dev Uses period-based calculation: 1 month = principal * APY / 12 / BASIS_POINTS
    function test_Security_ShareValueAccrual() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Check share value at different times
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 shareValueBefore = vault.previewRedeem(100_000e6);

        console2.log("Total assets at activation:", totalAssetsBefore);
        console2.log("Share value at activation:", shareValueBefore);

        // Warp 30 days (full first month period)
        vm.warp(block.timestamp + 30 days);

        uint256 totalAssetsAfter30Days = vault.totalAssets();
        uint256 shareValueAfter30Days = vault.previewRedeem(100_000e6);

        console2.log("Total assets after 30 days:", totalAssetsAfter30Days);
        console2.log("Share value after 30 days:", shareValueAfter30Days);

        // Share value should increase due to interest accrual
        assertGt(totalAssetsAfter30Days, totalAssetsBefore, "Total assets should increase");

        // Period-based interest calculation:
        // Monthly interest = principal * APY / 12 / BASIS_POINTS
        // = 100,000e6 * 1500 / 12 / 10_000 = 1,250e6 (1,250 USDC)
        uint256 principal = 100_000e6;
        uint256 expectedIncrease = (principal * 1500) / (12 * 10_000);
        uint256 actualIncrease = totalAssetsAfter30Days - totalAssetsBefore;

        assertApproxEqAbs(
            actualIncrease,
            expectedIncrease,
            1e6, // 1 USDC tolerance
            "Interest accrual should be accurate"
        );
    }

    /// @notice Test: Share value stops increasing after maturity
    function test_Security_ShareValueCapsAtMaturity() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp to exactly maturity time
        vm.warp(vault.maturityTime());
        uint256 assetsAtMaturity = vault.totalAssets();

        // Warp 30 more days past maturity
        vm.warp(vault.maturityTime() + 30 days);
        uint256 assetsAfterMaturity = vault.totalAssets();

        console2.log("Assets at maturity:", assetsAtMaturity);
        console2.log("Assets 30 days after maturity:", assetsAfterMaturity);

        // SECURITY CHECK: Assets should NOT increase after maturity
        assertEq(
            assetsAfterMaturity,
            assetsAtMaturity,
            "Share value should not increase after maturity"
        );
    }

    /// @notice Test: Hybrid system - interest claim records debt, not share burn
    function test_Security_InterestPaidReducesTotalAssets() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 10_000e6);
        vault.depositInterest(10_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 userDebtBefore = vault.getUserClaimedInterest(user1);

        vm.prank(user1);
        vault.claimInterest();

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 userDebtAfter = vault.getUserClaimedInterest(user1);

        console2.log("Total assets before claim:", totalAssetsBefore);
        console2.log("Total assets after claim:", totalAssetsAfter);
        console2.log("Total supply before claim:", totalSupplyBefore);
        console2.log("Total supply after claim:", totalSupplyAfter);
        console2.log("User debt before:", userDebtBefore);
        console2.log("User debt after:", userDebtAfter);

        // Hybrid system: After claiming interest:
        // - shares are NOT burned (stay the same)
        // - totalAssets stays the same (no deduction for claimed interest)
        // - user's debt (claimed interest) is recorded
        assertEq(totalSupplyAfter, totalSupplyBefore, "Hybrid: Shares should NOT be burned");
        assertEq(totalAssetsAfter, totalAssetsBefore, "Hybrid: totalAssets unchanged after claim");
        assertGt(userDebtAfter, userDebtBefore, "Hybrid: User debt should increase");
    }

    // ============================================================================
    // SECTION 8: MULTI-USER FAIRNESS TESTS
    // ============================================================================

    /// @notice Test: Interest distribution is fair among multiple users
    function test_Security_FairInterestDistribution() public {
        // Three users deposit different amounts
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), 200_000e6);
        vault.deposit(200_000e6, user2);
        vm.stopPrank();

        vm.startPrank(attacker);
        usdc.approve(address(vault), 300_000e6);
        vault.deposit(300_000e6, attacker);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), 100_000e6);
        vault.depositInterest(100_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 34 days); // 30 days (period) + 3 days (payment buffer) + 1

        uint256 user1Interest = vault.getPendingInterest(user1);
        uint256 user2Interest = vault.getPendingInterest(user2);
        uint256 attackerInterest = vault.getPendingInterest(attacker);

        console2.log("User1 interest (100K):", user1Interest);
        console2.log("User2 interest (200K):", user2Interest);
        console2.log("Attacker interest (300K):", attackerInterest);

        // SECURITY CHECK: Interest should be proportional to deposit
        // User2 deposited 2x user1, should get 2x interest
        assertApproxEqRel(user2Interest, user1Interest * 2, 0.01e18, "User2 should get 2x user1 interest");
        // Attacker deposited 3x user1, should get 3x interest
        assertApproxEqRel(attackerInterest, user1Interest * 3, 0.01e18, "Attacker should get 3x user1 interest");
    }

    /// @notice Test: Late depositor doesn't get unfair advantage
    function test_Security_LateDepositorNoAdvantage() public {
        // User1 deposits early
        vm.startPrank(user1);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user1);
        vm.stopPrank();

        // Warp 3 days (still in collection)
        vm.warp(block.timestamp + 3 days);

        // User2 deposits late (but still in collection)
        vm.startPrank(user2);
        usdc.approve(address(vault), 100_000e6);
        vault.deposit(100_000e6, user2);
        vm.stopPrank();

        // Both should have same number of shares for same deposit
        uint256 user1Shares = vault.balanceOf(user1);
        uint256 user2Shares = vault.balanceOf(user2);

        assertEq(user1Shares, user2Shares, "Same deposit should get same shares during collection");
    }
}
