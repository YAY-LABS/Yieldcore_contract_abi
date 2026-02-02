// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILoanRegistry
/// @notice Interface for the Loan Registry contract
interface ILoanRegistry {
    // ============ Enums ============
    enum LoanStatus {
        Active,
        Repaid
    }

    // ============ Structs ============
    struct Loan {
        uint256 id;
        address vault;
        bytes32 borrowerId;
        uint256 principal;
        uint256 interestRate;
        uint256 term;
        uint256 collateralValue;
        uint256 startTime;
        uint256 lastRepaymentTime;
        uint256 totalRepaid;
        uint256 totalInterestPaid;
        LoanStatus status;
    }

    struct LoanStats {
        uint256 activeLoanCount;
        uint256 totalOutstanding;
        uint256 totalRepaid;
    }

    // ============ Events ============
    event LoanRegistered(uint256 indexed loanId, address indexed vault, bytes32 indexed borrowerId);
    event LoanUpdated(uint256 indexed loanId, uint256 repaidAmount, uint256 interestAmount);
    event LoanStatusUpdated(uint256 indexed loanId, LoanStatus status);

    // ============ Loan Management ============
    function registerLoan(Loan calldata loan) external returns (uint256 loanId);
    function addRepayment(uint256 loanId, uint256 principalAmount, uint256 interestAmount) external;

    // ============ View Functions ============
    function getLoan(uint256 loanId) external view returns (Loan memory);
    function getLoansByVault(address vault) external view returns (uint256[] memory);
    function getActiveLoansByVault(address vault) external view returns (uint256[] memory);
    function getLoanCount() external view returns (uint256);
    function getActiveLoanCount() external view returns (uint256);
    function getTotalOutstanding() external view returns (uint256);
    function getOutstandingByVault(address vault) external view returns (uint256);
    function getVaultStats(address vault) external view returns (LoanStats memory);
    function getGlobalStats() external view returns (LoanStats memory);

    // ============ Calculation Functions ============
    function calculateInterestDue(uint256 loanId) external view returns (uint256);
    function calculateTotalDue(uint256 loanId) external view returns (uint256);
    function getLTV(uint256 loanId) external view returns (uint256);
    function isLoanOverdue(uint256 loanId) external view returns (bool);
}
