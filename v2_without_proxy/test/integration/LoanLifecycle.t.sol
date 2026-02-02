// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20} from "../unit/mocks/MockERC20.sol";
import {LoanRegistry} from "../../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../../src/core/VaultRegistry.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ILoanRegistry} from "../../src/interfaces/ILoanRegistry.sol";
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";

/// @title LoanLifecycleTest
/// @notice Integration tests for the complete loan lifecycle
contract LoanLifecycleTest is Test {
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
    address public depositor1 = makeAddr("depositor1");
    address public depositor2 = makeAddr("depositor2");
    address public borrower = makeAddr("borrower");

    // ============ Constants ============
    uint256 public constant PROTOCOL_FEE = 500; // 5%

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint initial balances
        usdc.mint(admin, 10_000_000e6);
        usdc.mint(curator, 10_000_000e6);
        usdc.mint(operator, 10_000_000e6);
        usdc.mint(depositor1, 10_000_000e6);
        usdc.mint(depositor2, 10_000_000e6);
        usdc.mint(borrower, 10_000_000e6);

        // Deploy all contracts
        _deployProtocol();
    }

    function _deployProtocol() internal {
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

        // 8. Create a vault
        uint256 interestStart = block.timestamp + 7 days;
        uint256 maturityTime = interestStart + 180 days;

        uint256[] memory periodEndDates = new uint256[](6);
        uint256[] memory paymentDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory vaultParams = IVaultFactory.VaultParams({
            name: "YieldCore RWA Vault",
            symbol: "ycRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 1500,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });
        vault = RWAVault(vaultFactory.createVault(vaultParams));

        vm.stopPrank();
    }

    // ============ Full Loan Lifecycle: Success Path ============

    function test_fullLoanLifecycle_successfulRepayment() public {
        // Step 1: Depositors provide liquidity (during Collecting phase)
        _depositToVault(depositor1, 200_000e6);
        _depositToVault(depositor2, 300_000e6);

        assertEq(vault.totalAssets(), 500_000e6);
        assertEq(vaultRegistry.getTotalTVL(), 500_000e6);

        // Step 2: Warp past collection end and activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Step 4: Curator registers a loan and deploys capital
        uint256 loanPrincipal = 100_000e6;
        uint256 loanInterestRate = 2000; // 20% APR
        uint256 loanTerm = 180 days;
        uint256 collateralValue = 150_000e6;

        IPoolManager.LoanParams memory loanParams = IPoolManager.LoanParams({
            vault: address(vault),
            borrowerId: keccak256("gasStation001"),
            principal: loanPrincipal,
            interestRate: loanInterestRate,
            term: loanTerm,
            collateralValue: collateralValue
        });

        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(loanParams);

        // Deploy capital separately (with timelock)
        _deployCapital(address(vault), loanPrincipal, address(poolManager));

        // Verify loan created
        assertEq(loanId, 1);
        assertEq(loanRegistry.getActiveLoanCount(), 1);
        assertEq(loanRegistry.getTotalOutstanding(), loanPrincipal);
        assertEq(vault.totalDeployed(), loanPrincipal);

        // Verify capital moved to pool manager
        assertEq(usdc.balanceOf(address(poolManager)), loanPrincipal);

        // Step 5: Time passes (6 months - vault term)
        vm.warp(block.timestamp + 180 days);

        // Step 6: Calculate interest due
        uint256 interestDue = loanRegistry.calculateInterestDue(loanId);
        assertGt(interestDue, 0);

        // For 20% APR over 6 months: ~10% of principal = 10,000 USDC
        // Actual calculation may vary slightly due to seconds
        uint256 expectedInterest = (loanPrincipal * loanInterestRate * loanTerm) /
                                   (RWAConstants.BASIS_POINTS * 365 days);
        assertApproxEqRel(interestDue, expectedInterest, 0.01e18); // 1% tolerance

        // Step 7: Operator records full repayment
        uint256 totalRepayment = loanPrincipal + interestDue;

        vm.startPrank(operator);
        usdc.approve(address(poolManager), totalRepayment);
        poolManager.recordRepayment(loanId, loanPrincipal, interestDue);
        vm.stopPrank();

        // Verify loan repaid
        ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Repaid));
        assertEq(loanRegistry.getActiveLoanCount(), 0);
        assertEq(loanRegistry.getTotalOutstanding(), 0);

        // Protocol fee is disabled - no fees collected
        assertEq(poolManager.accumulatedFees(), 0);

        // Step 9: Mature the vault (past maturity time)
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        vault.matureVault();

        // Set withdrawal start time (required after M-01 fix)
        vm.prank(admin);
        vault.setWithdrawalStartTime(block.timestamp);

        // Step 10: Deposit interest to vault for user interest claims
        vm.startPrank(operator);
        usdc.approve(address(poolManager), 100_000e6);
        poolManager.depositInterest(address(vault), 100_000e6);
        vm.stopPrank();

        // Step 11: Depositors withdraw after maturity
        uint256 depositor1Shares = vault.balanceOf(depositor1);
        uint256 depositor2Shares = vault.balanceOf(depositor2);
        uint256 depositor1BalanceBefore = usdc.balanceOf(depositor1);
        uint256 depositor2BalanceBefore = usdc.balanceOf(depositor2);

        vm.prank(depositor1);
        vault.redeem(depositor1Shares, depositor1, depositor1);

        vm.prank(depositor2);
        vault.redeem(depositor2Shares, depositor2, depositor2);

        // Verify depositors received at least their principal back
        // With new share value design, they get principal + accrued interest
        assertGe(usdc.balanceOf(depositor1), depositor1BalanceBefore + 200_000e6, "Depositor1 should receive at least principal");
        assertGe(usdc.balanceOf(depositor2), depositor2BalanceBefore + 300_000e6, "Depositor2 should receive at least principal");

        // Verify no shares remaining
        assertEq(vault.totalSupply(), 0, "All shares should be redeemed");
    }

    // ============ Multiple Loans Scenario ============

    function test_multipleLoans_mixedOutcomes() public {
        // Setup - deposits (Collecting phase)
        _depositToVault(depositor1, 500_000e6);

        // Warp past collection end and activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Create 3 loans (register + deploy separately)
        IPoolManager.LoanParams memory params1 = IPoolManager.LoanParams({
            vault: address(vault),
            borrowerId: keccak256("station001"),
            principal: 100_000e6,
            interestRate: 2000,
            term: 90 days,
            collateralValue: 150_000e6
        });

        IPoolManager.LoanParams memory params2 = IPoolManager.LoanParams({
            vault: address(vault),
            borrowerId: keccak256("station002"),
            principal: 80_000e6,
            interestRate: 1800,
            term: 120 days,
            collateralValue: 120_000e6
        });

        IPoolManager.LoanParams memory params3 = IPoolManager.LoanParams({
            vault: address(vault),
            borrowerId: keccak256("station003"),
            principal: 60_000e6,
            interestRate: 2200,
            term: 60 days,
            collateralValue: 100_000e6
        });

        vm.startPrank(curator);
        uint256 loanId1 = poolManager.registerLoan(params1);
        uint256 loanId2 = poolManager.registerLoan(params2);
        uint256 loanId3 = poolManager.registerLoan(params3);
        vm.stopPrank();

        // Deploy capital for all loans
        _deployCapital(address(vault), params1.principal + params2.principal + params3.principal, address(poolManager));

        assertEq(loanRegistry.getActiveLoanCount(), 3);
        assertEq(loanRegistry.getTotalOutstanding(), 240_000e6);

        // Time passes
        vm.warp(block.timestamp + 60 days);

        // Loan 3 repaid early
        uint256 interest3 = loanRegistry.calculateInterestDue(loanId3);

        vm.startPrank(operator);
        usdc.approve(address(poolManager), params3.principal + interest3);
        poolManager.recordRepayment(loanId3, params3.principal, interest3);
        vm.stopPrank();

        assertEq(loanRegistry.getActiveLoanCount(), 2);

        // More time passes
        vm.warp(block.timestamp + 60 days);

        // Loan 1 repaid on time
        uint256 interest1 = loanRegistry.calculateInterestDue(loanId1);

        vm.startPrank(operator);
        usdc.approve(address(poolManager), params1.principal + interest1);
        poolManager.recordRepayment(loanId1, params1.principal, interest1);
        vm.stopPrank();

        // More time passes, repay loan 2
        vm.warp(block.timestamp + 30 days);

        uint256 interest2 = loanRegistry.calculateInterestDue(loanId2);

        vm.startPrank(operator);
        usdc.approve(address(poolManager), params2.principal + interest2);
        poolManager.recordRepayment(loanId2, params2.principal, interest2);
        vm.stopPrank();

        // Final state
        ILoanRegistry.LoanStats memory stats = loanRegistry.getGlobalStats();
        assertEq(stats.activeLoanCount, 0);
        assertEq(stats.totalRepaid, params1.principal + params2.principal + params3.principal);
    }

    // ============ Stress Test: Large Number of Loans ============

    function test_stressTest_manyLoans() public {
        // Setup with large deposits (Collecting phase)
        _depositToVault(depositor1, 5_000_000e6);

        // Warp past collection end and activate vault
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Create 10 loans and deploy capital once
        uint256 totalPrincipal = 0;
        for (uint256 i = 0; i < 10; i++) {
            IPoolManager.LoanParams memory params = IPoolManager.LoanParams({
                vault: address(vault),
                borrowerId: keccak256(abi.encodePacked("station", i)),
                principal: 100_000e6,
                interestRate: 2000 + uint256(i * 100),
                term: 90 days + uint256(i * 30 days),
                collateralValue: 150_000e6
            });

            vm.prank(curator);
            poolManager.registerLoan(params);
            totalPrincipal += params.principal;
        }

        // Deploy capital for all loans in one batch
        _deployCapital(address(vault), totalPrincipal, address(poolManager));

        assertEq(loanRegistry.getActiveLoanCount(), 10);
        assertEq(loanRegistry.getTotalOutstanding(), 1_000_000e6);

        // Repay half
        vm.warp(block.timestamp + 120 days);

        for (uint256 i = 0; i < 5; i++) {
            uint256 loanId = i + 1;
            ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
            uint256 interest = loanRegistry.calculateInterestDue(loanId);

            vm.startPrank(operator);
            usdc.approve(address(poolManager), loan.principal + interest);
            poolManager.recordRepayment(loanId, loan.principal, interest);
            vm.stopPrank();
        }

        assertEq(loanRegistry.getActiveLoanCount(), 5);

        // Repay the rest
        vm.warp(block.timestamp + 200 days);

        for (uint256 i = 5; i < 10; i++) {
            uint256 loanId = i + 1;
            ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
            uint256 interest = loanRegistry.calculateInterestDue(loanId);

            vm.startPrank(operator);
            usdc.approve(address(poolManager), loan.principal + interest);
            poolManager.recordRepayment(loanId, loan.principal, interest);
            vm.stopPrank();
        }

        assertEq(loanRegistry.getActiveLoanCount(), 0);
    }

    // ============ Helper Functions ============

    function _depositToVault(address depositor, uint256 amount) internal {
        vm.startPrank(depositor);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, depositor);
        vm.stopPrank();
    }

    function _deployCapital(address vaultAddr, uint256 amount, address recipient) internal {
        vm.prank(curator);
        poolManager.announceDeployCapital(vaultAddr, amount, recipient);

        // Warp past timelock
        uint256 delay = RWAVault(vaultAddr).deploymentDelay();
        vm.warp(block.timestamp + delay + 1);

        vm.prank(curator);
        poolManager.executeDeployCapital(vaultAddr);
    }
}
