// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {YieldCoreBase} from "./YieldCoreBase.sol";
import {IVaultRegistry} from "../interfaces/IVaultRegistry.sol";
import {RWAConstants} from "../libraries/RWAConstants.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";
import {RWAEvents} from "../libraries/RWAEvents.sol";

/// @title VaultRegistry
/// @notice Registry for tracking all deployed RWA Vaults (Fixed-term)
contract VaultRegistry is YieldCoreBase, IVaultRegistry {
    // ============ Storage ============

    /// @notice Array of all vault addresses
    address[] private _allVaults;

    /// @notice Mapping of vault address to metadata
    mapping(address => VaultMetadata) private _vaultMetadata;

    /// @notice Mapping of vault address to registration status
    mapping(address => bool) private _isRegistered;

    /// @notice Mapping of term duration to vault addresses
    mapping(uint256 => address[]) private _vaultsByTerm;

    // ============ Constructor ============

    /// @notice Creates the registry
    /// @param admin_ The admin address
    constructor(address admin_) YieldCoreBase(admin_) {}

    // ============ Admin Functions ============

    /// @notice Adds a new vault to the registry
    /// @param vault The vault address
    /// @param name The vault name
    /// @param symbol The vault symbol
    /// @param termDuration The term duration in seconds
    /// @param fixedAPY The fixed APY in basis points
    function addVault(
        address vault,
        string calldata name,
        string calldata symbol,
        uint256 termDuration,
        uint256 fixedAPY
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault == address(0)) revert RWAErrors.ZeroAddress();
        if (_isRegistered[vault]) revert RWAErrors.VaultAlreadyRegistered();

        _allVaults.push(vault);
        _isRegistered[vault] = true;
        _vaultsByTerm[termDuration].push(vault);

        _vaultMetadata[vault] = VaultMetadata({
            vault: vault,
            name: name,
            symbol: symbol,
            termDuration: termDuration,
            fixedAPY: fixedAPY,
            createdAt: block.timestamp,
            active: true
        });

        emit RWAEvents.VaultAdded(vault, name, termDuration);
    }

    /// @notice Removes a vault from the registry
    /// @param vault The vault address to remove
    function removeVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();

        // Get term duration before deleting metadata
        uint256 termDuration = _vaultMetadata[vault].termDuration;

        // Remove from _allVaults array (swap and pop)
        uint256 len = _allVaults.length;
        for (uint256 i = 0; i < len;) {
            if (_allVaults[i] == vault) {
                _allVaults[i] = _allVaults[len - 1];
                _allVaults.pop();
                break;
            }
            unchecked { ++i; }
        }

        // Remove from _vaultsByTerm array (swap and pop)
        address[] storage termVaults = _vaultsByTerm[termDuration];
        uint256 termLen = termVaults.length;
        for (uint256 i = 0; i < termLen;) {
            if (termVaults[i] == vault) {
                termVaults[i] = termVaults[termLen - 1];
                termVaults.pop();
                break;
            }
            unchecked { ++i; }
        }

        _isRegistered[vault] = false;
        delete _vaultMetadata[vault];

        emit RWAEvents.VaultRemoved(vault);
    }

    /// @notice Sets the active status of a vault
    /// @param vault The vault address
    /// @param active The new active status
    function setVaultStatus(address vault, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();

        _vaultMetadata[vault].active = active;

        emit RWAEvents.VaultStatusChanged(vault, active);
    }

    // ============ View Functions ============

    /// @notice Gets the metadata for a vault
    /// @param vault The vault address
    /// @return The vault metadata
    function getVault(address vault) external view returns (VaultMetadata memory) {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();
        return _vaultMetadata[vault];
    }

    /// @notice Gets all vault addresses
    /// @return Array of vault addresses
    function getAllVaults() external view returns (address[] memory) {
        return _allVaults;
    }

    /// @notice Gets all active vault addresses
    /// @return Array of active vault addresses
    function getActiveVaults() external view returns (address[] memory) {
        uint256 length = _allVaults.length;

        // Allocate max possible size, then resize (single pass - gas optimized)
        address[] memory activeVaults = new address[](length);
        uint256 activeCount = 0;

        for (uint256 i = 0; i < length;) {
            if (_isRegistered[_allVaults[i]] && _vaultMetadata[_allVaults[i]].active) {
                activeVaults[activeCount] = _allVaults[i];
                unchecked { ++activeCount; }
            }
            unchecked { ++i; }
        }

        // Resize array using assembly (avoids second loop)
        assembly {
            mstore(activeVaults, activeCount)
        }

        return activeVaults;
    }

    /// @notice Gets vaults by term duration
    /// @param termDuration The term duration in seconds
    /// @return Array of vault addresses with the specified term duration
    function getVaultsByTerm(uint256 termDuration) external view returns (address[] memory) {
        return _vaultsByTerm[termDuration];
    }

    /// @notice Gets the total number of vaults
    /// @return The total vault count
    function getVaultCount() external view returns (uint256) {
        return _allVaults.length;
    }

    /// @notice Checks if a vault is registered
    /// @param vault The vault address
    /// @return True if registered
    function isRegistered(address vault) external view returns (bool) {
        return _isRegistered[vault];
    }

    /// @notice Gets the total TVL across all active vaults
    /// @return The total TVL
    function getTotalTVL() external view returns (uint256) {
        uint256 totalTVL = 0;
        uint256 length = _allVaults.length;

        for (uint256 i = 0; i < length;) {
            address vault = _allVaults[i];
            if (_isRegistered[vault] && _vaultMetadata[vault].active) {
                totalTVL += IERC4626(vault).totalAssets();
            }
            unchecked { ++i; }
        }

        return totalTVL;
    }
}
