// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPoolManager
/// @notice Interface for the Pool Manager contract
interface IPoolManager {
    // ============ Structs ============
    struct LoanParams {
        address vault;
        bytes32 borrowerId;
        uint256 principal;
        uint256 interestRate;
        uint256 term;
        uint256 collateralValue;
    }

    // ============ Events ============
    event LoanCreated(
        uint256 indexed loanId,
        address indexed vault,
        bytes32 indexed borrowerId,
        uint256 principal,
        uint256 interestRate,
        uint256 term,
        uint256 collateralValue
    );

    event RepaymentRecorded(
        uint256 indexed loanId,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 protocolFee,
        uint256 remainingPrincipal
    );

    event VaultRegistered(address indexed vault);
    event VaultUnregistered(address indexed vault);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeesWithdrawn(address indexed treasury, uint256 amount);

    // ============ Loan Management ============
    function createLoan(LoanParams calldata params) external returns (uint256 loanId);

    function recordRepayment(
        uint256 loanId,
        uint256 principalAmount,
        uint256 interestAmount
    ) external;

    // ============ Vault Management ============
    function registerVault(address vault) external;
    function unregisterVault(address vault) external;
    function isRegisteredVault(address vault) external view returns (bool);

    // ============ Fee Management ============
    function withdrawFees() external;
    function setProtocolFee(uint256 newFee) external;
    function setTreasury(address newTreasury) external;

    // ============ View Functions ============
    function treasury() external view returns (address);
    function protocolFee() external view returns (uint256);
    function accumulatedFees() external view returns (uint256);
}
