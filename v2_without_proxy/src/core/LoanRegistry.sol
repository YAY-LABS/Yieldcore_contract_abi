// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {YieldCoreBase} from "./YieldCoreBase.sol";
import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {RWAConstants} from "../libraries/RWAConstants.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";
import {RWAEvents} from "../libraries/RWAEvents.sol";

/// @title LoanRegistry
/// @notice Registry for tracking all RWA loans
contract LoanRegistry is YieldCoreBase, ILoanRegistry {
    // ============ Storage ============

    /// @notice Next loan ID to assign
    uint256 private _nextLoanId;

    /// @notice Mapping of loan ID to loan data
    mapping(uint256 => Loan) private _loans;

    /// @notice Mapping of vault to loan IDs
    mapping(address => uint256[]) private _vaultLoans;

    /// @notice Current number of active loans
    uint256 private _activeLoanCount;

    /// @notice Total outstanding principal across all loans
    uint256 private _totalOutstanding;

    /// @notice Total principal repaid across all loans
    uint256 private _totalRepaid;

    /// @notice Outstanding principal by vault
    mapping(address => uint256) private _outstandingByVault;

    // ============ Constructor ============

    /// @notice Creates the registry
    /// @param admin_ The admin address
    constructor(address admin_) YieldCoreBase(admin_) {
        _nextLoanId = 1;
    }

    // ============ Loan Management ============

    /// @notice Registers a new loan
    /// @param loan The loan data
    /// @return loanId The assigned loan ID
    function registerLoan(Loan calldata loan) external onlyRole(RWAConstants.POOL_MANAGER_ROLE) returns (uint256 loanId) {
        loanId = _nextLoanId++;

        Loan storage newLoan = _loans[loanId];
        newLoan.id = loanId;
        newLoan.vault = loan.vault;
        newLoan.borrowerId = loan.borrowerId;
        newLoan.principal = loan.principal;
        newLoan.interestRate = loan.interestRate;
        newLoan.term = loan.term;
        newLoan.collateralValue = loan.collateralValue;
        newLoan.startTime = block.timestamp;
        newLoan.lastRepaymentTime = block.timestamp;
        newLoan.totalRepaid = 0;
        newLoan.totalInterestPaid = 0;
        newLoan.status = LoanStatus.Active;

        _vaultLoans[loan.vault].push(loanId);
        _activeLoanCount++;
        _totalOutstanding += loan.principal;
        _outstandingByVault[loan.vault] += loan.principal;

        emit RWAEvents.LoanRegistered(loanId, loan.vault, loan.borrowerId);
    }

    /// @notice Records a repayment on a loan
    /// @param loanId The loan ID
    /// @param principalAmount The principal amount repaid
    /// @param interestAmount The interest amount paid
    function addRepayment(
        uint256 loanId,
        uint256 principalAmount,
        uint256 interestAmount
    ) external onlyRole(RWAConstants.POOL_MANAGER_ROLE) {
        Loan storage loan = _loans[loanId];
        if (loan.id == 0) revert RWAErrors.LoanNotFound();
        if (loan.status != LoanStatus.Active) revert RWAErrors.LoanNotActive();

        uint256 remainingPrincipal = loan.principal - loan.totalRepaid;
        if (principalAmount > remainingPrincipal) revert RWAErrors.RepaymentExceedsOutstanding();

        loan.totalRepaid += principalAmount;
        loan.totalInterestPaid += interestAmount;
        loan.lastRepaymentTime = block.timestamp;

        _totalOutstanding -= principalAmount;
        _totalRepaid += principalAmount;
        _outstandingByVault[loan.vault] -= principalAmount;

        // Check if loan is fully repaid
        if (loan.totalRepaid >= loan.principal) {
            loan.status = LoanStatus.Repaid;
            _activeLoanCount--;
            emit RWAEvents.LoanStatusUpdated(loanId, uint8(LoanStatus.Repaid));
        }

        emit RWAEvents.LoanUpdated(loanId, principalAmount, interestAmount);
    }

    // ============ View Functions ============

    /// @notice Gets loan data by ID
    /// @param loanId The loan ID
    /// @return The loan data
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        if (_loans[loanId].id == 0) revert RWAErrors.LoanNotFound();
        return _loans[loanId];
    }

    /// @notice Gets all loan IDs for a vault
    /// @param vault The vault address
    /// @return Array of loan IDs
    function getLoansByVault(address vault) external view returns (uint256[] memory) {
        return _vaultLoans[vault];
    }

    /// @notice Gets active loan IDs for a vault
    /// @param vault The vault address
    /// @return Array of active loan IDs
    function getActiveLoansByVault(address vault) external view returns (uint256[] memory) {
        uint256[] memory allLoans = _vaultLoans[vault];
        uint256 length = allLoans.length;

        // Allocate max possible size, then resize (single pass - gas optimized)
        uint256[] memory activeLoans = new uint256[](length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < length;) {
            if (_loans[allLoans[i]].status == LoanStatus.Active) {
                activeLoans[activeCount] = allLoans[i];
                unchecked { ++activeCount; }
            }
            unchecked { ++i; }
        }

        // Resize array using assembly (avoids second loop)
        assembly {
            mstore(activeLoans, activeCount)
        }

        return activeLoans;
    }

    /// @notice Gets the total loan count
    /// @return The total number of loans
    function getLoanCount() external view returns (uint256) {
        return _nextLoanId - 1;
    }

    /// @notice Gets the active loan count
    /// @return The number of active loans
    function getActiveLoanCount() external view returns (uint256) {
        return _activeLoanCount;
    }

    /// @notice Gets the total outstanding principal
    /// @return The total outstanding amount
    function getTotalOutstanding() external view returns (uint256) {
        return _totalOutstanding;
    }

    /// @notice Gets outstanding principal for a vault
    /// @param vault The vault address
    /// @return The outstanding amount for the vault
    function getOutstandingByVault(address vault) external view returns (uint256) {
        return _outstandingByVault[vault];
    }

    /// @notice Gets loan statistics for a vault
    /// @param vault The vault address
    /// @return stats The loan statistics
    function getVaultStats(address vault) external view returns (LoanStats memory stats) {
        uint256[] memory loanIds = _vaultLoans[vault];
        uint256 len = loanIds.length;

        for (uint256 i = 0; i < len;) {
            Loan storage loan = _loans[loanIds[i]];
            if (loan.status == LoanStatus.Active) {
                stats.activeLoanCount++;
                stats.totalOutstanding += loan.principal - loan.totalRepaid;
            } else if (loan.status == LoanStatus.Repaid) {
                stats.totalRepaid += loan.totalRepaid;
            }
            unchecked { ++i; }
        }
    }

    /// @notice Gets global loan statistics
    /// @return stats The global loan statistics
    function getGlobalStats() external view returns (LoanStats memory stats) {
        stats.activeLoanCount = _activeLoanCount;
        stats.totalOutstanding = _totalOutstanding;
        stats.totalRepaid = _totalRepaid;
    }

    // ============ Calculation Functions ============

    /// @notice Calculates interest due on a loan
    /// @param loanId The loan ID
    /// @return The interest amount due
    function calculateInterestDue(uint256 loanId) external view returns (uint256) {
        return _calculateInterestDue(loanId);
    }

    /// @notice Calculates total amount due on a loan
    /// @param loanId The loan ID
    /// @return The total amount due (principal + interest)
    function calculateTotalDue(uint256 loanId) external view returns (uint256) {
        Loan storage loan = _loans[loanId];
        if (loan.id == 0) revert RWAErrors.LoanNotFound();
        if (loan.status != LoanStatus.Active) return 0;

        uint256 remainingPrincipal = loan.principal - loan.totalRepaid;
        uint256 interestDue = _calculateInterestDue(loanId);

        return remainingPrincipal + interestDue;
    }

    /// @dev Internal function to calculate interest due
    function _calculateInterestDue(uint256 loanId) internal view returns (uint256) {
        Loan storage loan = _loans[loanId];
        if (loan.id == 0) revert RWAErrors.LoanNotFound();
        if (loan.status != LoanStatus.Active) return 0;

        uint256 remainingPrincipal = loan.principal - loan.totalRepaid;
        uint256 timeElapsed = block.timestamp - loan.lastRepaymentTime;

        // Interest = Principal * Rate * Time / (BASIS_POINTS * SECONDS_PER_YEAR)
        return (remainingPrincipal * loan.interestRate * timeElapsed) /
               (RWAConstants.BASIS_POINTS * RWAConstants.SECONDS_PER_YEAR);
    }

    /// @notice Gets the LTV ratio of a loan
    /// @param loanId The loan ID
    /// @return The LTV ratio in basis points
    function getLTV(uint256 loanId) external view returns (uint256) {
        Loan storage loan = _loans[loanId];
        if (loan.id == 0) revert RWAErrors.LoanNotFound();
        if (loan.collateralValue == 0) return 0;

        uint256 remainingPrincipal = loan.principal - loan.totalRepaid;
        return (remainingPrincipal * RWAConstants.BASIS_POINTS) / loan.collateralValue;
    }

    /// @notice Checks if a loan is overdue
    /// @param loanId The loan ID
    /// @return True if the loan is past its term
    function isLoanOverdue(uint256 loanId) external view returns (bool) {
        Loan storage loan = _loans[loanId];
        if (loan.id == 0) revert RWAErrors.LoanNotFound();
        if (loan.status != LoanStatus.Active) return false;

        return block.timestamp > loan.startTime + loan.term;
    }
}
