// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVaultFactory
/// @notice Interface for the Vault Factory contract (Fixed-term vaults)
interface IVaultFactory {
    // ============ Structs ============
    struct VaultParams {
        string name;
        string symbol;
        uint256 collectionStartTime;   // When collection phase starts (deposits allowed)
        uint256 collectionEndTime;     // When collection phase ends
        uint256 interestStartTime;     // When interest starts accruing
        uint256 termDuration;          // Duration of the term
        uint256 fixedAPY;              // Fixed APY in basis points
        uint256 minDeposit;
        uint256 maxCapacity;
        uint256[] interestPeriodEndDates; // End date of each interest period
        uint256[] interestPaymentDates; // Monthly interest payment timestamps (claimable dates)
        uint256 withdrawalStartTime;   // When withdrawals become available
    }

    struct VaultInfo {
        address vaultAddress;
        string name;
        string symbol;
        uint256 termDuration;
        uint256 fixedAPY;
        uint256 tvl;
        bool active;
        uint256 createdAt;
    }

    // ============ Events ============
    event VaultCreated(
        address indexed vault,
        address indexed creator,
        string name,
        string symbol,
        uint256 termDuration,
        uint256 fixedAPY,
        uint256 timestamp
    );

    event VaultDeactivated(address indexed vault, uint256 timestamp);
    event VaultReactivated(address indexed vault, uint256 timestamp);

    // ============ Admin Functions ============
    function createVault(VaultParams calldata params) external returns (address vault);
    function deactivateVault(address vault) external;
    function reactivateVault(address vault) external;

    // ============ View Functions ============
    function getAllVaults() external view returns (address[] memory);
    function getActiveVaults() external view returns (address[] memory);
    function getVaultInfo(address vault) external view returns (VaultInfo memory);
    function getVaultCount() external view returns (uint256);
    function isRegisteredVault(address vault) external view returns (bool);
    function getTotalTVL() external view returns (uint256);

    function poolManager() external view returns (address);
    function asset() external view returns (address);
    function vaultRegistry() external view returns (address);
}
