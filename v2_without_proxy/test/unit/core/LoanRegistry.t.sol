// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {ILoanRegistry} from "../../../src/interfaces/ILoanRegistry.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";

contract LoanRegistryTest is BaseTest {
    address public testVault;

    function setUp() public override {
        super.setUp();
        testVault = _createDefaultVault();
    }

    // ============ Initialization Tests ============

    function test_initialize() public view {
        assertEq(loanRegistry.getLoanCount(), 0);
        assertEq(loanRegistry.getActiveLoanCount(), 0);
        assertEq(loanRegistry.getTotalOutstanding(), 0);
    }

    function test_initialize_grantsAdminRole() public view {
        assertTrue(loanRegistry.hasRole(loanRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ============ registerLoan Tests ============

    function test_registerLoan_success() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        assertEq(loanId, 1);
        assertEq(loanRegistry.getLoanCount(), 1);
        assertEq(loanRegistry.getActiveLoanCount(), 1);
        assertEq(loanRegistry.getTotalOutstanding(), loan.principal);
    }

    function test_registerLoan_multipleLoanss() public {
        ILoanRegistry.Loan memory loan1 = _createTestLoan();
        ILoanRegistry.Loan memory loan2 = _createTestLoan();
        loan2.principal = 200_000e6;

        vm.startPrank(address(poolManager));
        uint256 loanId1 = loanRegistry.registerLoan(loan1);
        uint256 loanId2 = loanRegistry.registerLoan(loan2);
        vm.stopPrank();

        assertEq(loanId1, 1);
        assertEq(loanId2, 2);
        assertEq(loanRegistry.getLoanCount(), 2);
        assertEq(loanRegistry.getActiveLoanCount(), 2);
        assertEq(loanRegistry.getTotalOutstanding(), loan1.principal + loan2.principal);
    }

    function test_registerLoan_revertUnauthorized() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(user1);
        vm.expectRevert();
        loanRegistry.registerLoan(loan);
    }

    function test_registerLoan_setsCorrectFields() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        ILoanRegistry.Loan memory storedLoan = loanRegistry.getLoan(loanId);

        assertEq(storedLoan.id, loanId);
        assertEq(storedLoan.vault, testVault);
        assertEq(storedLoan.borrowerId, loan.borrowerId);
        assertEq(storedLoan.principal, loan.principal);
        assertEq(storedLoan.interestRate, loan.interestRate);
        assertEq(storedLoan.term, loan.term);
        assertEq(storedLoan.collateralValue, loan.collateralValue);
        assertEq(storedLoan.startTime, block.timestamp);
        assertEq(storedLoan.lastRepaymentTime, block.timestamp);
        assertEq(storedLoan.totalRepaid, 0);
        assertEq(storedLoan.totalInterestPaid, 0);
        assertEq(uint8(storedLoan.status), uint8(ILoanRegistry.LoanStatus.Active));
    }

    // ============ addRepayment Tests ============

    function test_addRepayment_partialRepayment() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        uint256 principalPayment = 50_000e6;
        uint256 interestPayment = 5_000e6;

        vm.warp(block.timestamp + 30 days);

        vm.prank(address(poolManager));
        loanRegistry.addRepayment(loanId, principalPayment, interestPayment);

        ILoanRegistry.Loan memory storedLoan = loanRegistry.getLoan(loanId);
        assertEq(storedLoan.totalRepaid, principalPayment);
        assertEq(storedLoan.totalInterestPaid, interestPayment);
        assertEq(uint8(storedLoan.status), uint8(ILoanRegistry.LoanStatus.Active));
        assertEq(loanRegistry.getTotalOutstanding(), loan.principal - principalPayment);
    }

    function test_addRepayment_fullRepayment() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        vm.warp(block.timestamp + 30 days);

        vm.prank(address(poolManager));
        loanRegistry.addRepayment(loanId, loan.principal, 10_000e6);

        ILoanRegistry.Loan memory storedLoan = loanRegistry.getLoan(loanId);
        assertEq(uint8(storedLoan.status), uint8(ILoanRegistry.LoanStatus.Repaid));
        assertEq(loanRegistry.getActiveLoanCount(), 0);
        assertEq(loanRegistry.getTotalOutstanding(), 0);
    }

    function test_addRepayment_revertLoanNotFound() public {
        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.LoanNotFound.selector);
        loanRegistry.addRepayment(999, 1000e6, 100e6);
    }

    function test_addRepayment_revertLoanNotActive() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.startPrank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);
        loanRegistry.addRepayment(loanId, loan.principal, 10_000e6); // Full repay

        vm.expectRevert(RWAErrors.LoanNotActive.selector);
        loanRegistry.addRepayment(loanId, 1000e6, 100e6);
        vm.stopPrank();
    }

    function test_addRepayment_revertExceedsOutstanding() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        vm.prank(address(poolManager));
        vm.expectRevert(RWAErrors.RepaymentExceedsOutstanding.selector);
        loanRegistry.addRepayment(loanId, loan.principal + 1, 0);
    }

    // ============ View Function Tests ============

    function test_getLoan_revertNotFound() public {
        vm.expectRevert(RWAErrors.LoanNotFound.selector);
        loanRegistry.getLoan(999);
    }

    function test_getLoansByVault() public {
        ILoanRegistry.Loan memory loan1 = _createTestLoan();
        ILoanRegistry.Loan memory loan2 = _createTestLoan();

        vm.startPrank(address(poolManager));
        loanRegistry.registerLoan(loan1);
        loanRegistry.registerLoan(loan2);
        vm.stopPrank();

        uint256[] memory loans = loanRegistry.getLoansByVault(testVault);
        assertEq(loans.length, 2);
        assertEq(loans[0], 1);
        assertEq(loans[1], 2);
    }

    function test_getActiveLoansByVault() public {
        ILoanRegistry.Loan memory loan1 = _createTestLoan();
        ILoanRegistry.Loan memory loan2 = _createTestLoan();

        vm.startPrank(address(poolManager));
        uint256 loanId1 = loanRegistry.registerLoan(loan1);
        loanRegistry.registerLoan(loan2);

        // Repay loan 1 fully
        loanRegistry.addRepayment(loanId1, loan1.principal, 10_000e6);
        vm.stopPrank();

        uint256[] memory activeLoans = loanRegistry.getActiveLoansByVault(testVault);
        assertEq(activeLoans.length, 1);
        assertEq(activeLoans[0], 2);
    }

    function test_getOutstandingByVault() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        loanRegistry.registerLoan(loan);

        assertEq(loanRegistry.getOutstandingByVault(testVault), loan.principal);
    }

    function test_getVaultStats() public {
        ILoanRegistry.Loan memory loan1 = _createTestLoan();
        ILoanRegistry.Loan memory loan2 = _createTestLoan();
        loan2.principal = 200_000e6;

        vm.startPrank(address(poolManager));
        uint256 loanId1 = loanRegistry.registerLoan(loan1);
        loanRegistry.registerLoan(loan2);

        // Repay loan 1 fully
        loanRegistry.addRepayment(loanId1, loan1.principal, 10_000e6);
        vm.stopPrank();

        ILoanRegistry.LoanStats memory stats = loanRegistry.getVaultStats(testVault);
        assertEq(stats.activeLoanCount, 1);
        assertEq(stats.totalOutstanding, loan2.principal);
        assertEq(stats.totalRepaid, loan1.principal);
    }

    function test_getGlobalStats() public {
        ILoanRegistry.Loan memory loan1 = _createTestLoan();
        ILoanRegistry.Loan memory loan2 = _createTestLoan();
        loan2.principal = 200_000e6;

        vm.startPrank(address(poolManager));
        uint256 loanId1 = loanRegistry.registerLoan(loan1);
        uint256 loanId2 = loanRegistry.registerLoan(loan2);

        // Partial repay loan 1
        loanRegistry.addRepayment(loanId1, 50_000e6, 5_000e6);
        // Full repay loan 2
        loanRegistry.addRepayment(loanId2, loan2.principal, 20_000e6);
        vm.stopPrank();

        ILoanRegistry.LoanStats memory stats = loanRegistry.getGlobalStats();
        assertEq(stats.activeLoanCount, 1);
        assertEq(stats.totalOutstanding, loan1.principal - 50_000e6);
        assertEq(stats.totalRepaid, 50_000e6 + loan2.principal);
    }

    // ============ Calculation Function Tests ============

    function test_calculateInterestDue() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        // Warp 365 days
        vm.warp(block.timestamp + 365 days);

        // Expected: principal * rate / BASIS_POINTS = 100_000e6 * 2000 / 10000 = 20_000e6
        uint256 expectedInterest = (loan.principal * loan.interestRate) / RWAConstants.BASIS_POINTS;
        uint256 actualInterest = loanRegistry.calculateInterestDue(loanId);

        // Allow small rounding difference
        assertApproxEqAbs(actualInterest, expectedInterest, 1e6);
    }

    function test_calculateInterestDue_zeroForRepaidLoan() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.startPrank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);
        loanRegistry.addRepayment(loanId, loan.principal, 10_000e6);
        vm.stopPrank();

        assertEq(loanRegistry.calculateInterestDue(loanId), 0);
    }

    function test_calculateTotalDue() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        vm.warp(block.timestamp + 365 days);

        uint256 totalDue = loanRegistry.calculateTotalDue(loanId);
        uint256 interestDue = loanRegistry.calculateInterestDue(loanId);

        assertEq(totalDue, loan.principal + interestDue);
    }

    function test_getLTV() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        // LTV = principal / collateralValue * BASIS_POINTS
        // 100_000e6 / 150_000e6 * 10_000 = 6666 (66.66%)
        uint256 ltv = loanRegistry.getLTV(loanId);
        assertApproxEqAbs(ltv, 6666, 1);
    }

    function test_getLTV_afterPartialRepayment() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        // Repay half
        vm.prank(address(poolManager));
        loanRegistry.addRepayment(loanId, 50_000e6, 5_000e6);

        // LTV = 50_000e6 / 150_000e6 * 10_000 = 3333 (33.33%)
        uint256 ltv = loanRegistry.getLTV(loanId);
        assertApproxEqAbs(ltv, 3333, 1);
    }

    function test_isLoanOverdue_false() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        assertFalse(loanRegistry.isLoanOverdue(loanId));
    }

    function test_isLoanOverdue_true() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.prank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);

        // Warp past term
        vm.warp(block.timestamp + loan.term + 1);

        assertTrue(loanRegistry.isLoanOverdue(loanId));
    }

    function test_isLoanOverdue_falseForRepaidLoan() public {
        ILoanRegistry.Loan memory loan = _createTestLoan();

        vm.startPrank(address(poolManager));
        uint256 loanId = loanRegistry.registerLoan(loan);
        loanRegistry.addRepayment(loanId, loan.principal, 10_000e6);
        vm.stopPrank();

        // Warp past term
        vm.warp(block.timestamp + loan.term + 1);

        // Should return false for non-active loans
        assertFalse(loanRegistry.isLoanOverdue(loanId));
    }

    // ============ Pause Tests ============

    function test_pause_unpause() public {
        vm.startPrank(admin);
        loanRegistry.pause();
        assertTrue(loanRegistry.paused());

        loanRegistry.unpause();
        assertFalse(loanRegistry.paused());
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _createTestLoan() internal view returns (ILoanRegistry.Loan memory) {
        return ILoanRegistry.Loan({
            id: 0,
            vault: testVault,
            borrowerId: keccak256("borrower1"),
            principal: 100_000e6,
            interestRate: 2000, // 20%
            term: 180 days,
            collateralValue: 150_000e6,
            startTime: 0,
            lastRepaymentTime: 0,
            totalRepaid: 0,
            totalInterestPaid: 0,
            status: ILoanRegistry.LoanStatus.Active
        });
    }
}
