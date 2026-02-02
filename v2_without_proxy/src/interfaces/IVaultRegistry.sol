// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVaultRegistry
/// @notice Interface for the Vault Registry contract (Fixed-term vaults)
interface IVaultRegistry {
    // ============ Structs ============
    struct VaultMetadata {
        address vault;
        string name;
        string symbol;
        uint256 termDuration;
        uint256 fixedAPY;
        uint256 createdAt;
        bool active;
    }

    // ============ Events ============
    event VaultAdded(address indexed vault, string name, uint256 termDuration);
    event VaultRemoved(address indexed vault);
    event VaultStatusChanged(address indexed vault, bool active);

    // ============ Admin Functions ============
    function addVault(
        address vault,
        string calldata name,
        string calldata symbol,
        uint256 termDuration,
        uint256 fixedAPY
    ) external;

    function removeVault(address vault) external;
    function setVaultStatus(address vault, bool active) external;

    // ============ View Functions ============
    function getVault(address vault) external view returns (VaultMetadata memory);
    function getAllVaults() external view returns (address[] memory);
    function getActiveVaults() external view returns (address[] memory);
    function getVaultsByTerm(uint256 termDuration) external view returns (address[] memory);
    function getVaultCount() external view returns (uint256);
    function isRegistered(address vault) external view returns (bool);
    function getTotalTVL() external view returns (uint256);
}
