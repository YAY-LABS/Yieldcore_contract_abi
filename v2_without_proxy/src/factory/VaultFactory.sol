// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {YieldCoreBase} from "../core/YieldCoreBase.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {IVaultRegistry} from "../interfaces/IVaultRegistry.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IRWAVault} from "../interfaces/IRWAVault.sol";
import {RWAVault} from "../vault/RWAVault.sol";
import {RWAConstants} from "../libraries/RWAConstants.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";
import {RWAEvents} from "../libraries/RWAEvents.sol";

/// @title VaultFactory
/// @notice Factory for deploying RWA Fixed-term Vaults using EIP-1167 clones
contract VaultFactory is YieldCoreBase, IVaultFactory {
    // ============ Storage ============

    /// @notice Pool manager address
    address public poolManager;

    /// @notice Underlying asset address
    address public asset;

    /// @notice Vault registry address
    address public vaultRegistry;

    /// @notice RWAVault implementation address (for clones)
    address public immutable vaultImplementation;

    /// @notice Array of all deployed vaults
    address[] private _allVaults;

    /// @notice Mapping of vault address to info
    mapping(address => VaultInfo) private _vaultInfos;

    /// @notice Mapping of vault address to registration status
    mapping(address => bool) private _isRegistered;

    // ============ Constructor ============

    /// @notice Creates the factory and deploys the vault implementation
    /// @param admin_ The admin address
    /// @param poolManager_ The pool manager address
    /// @param asset_ The underlying asset address
    /// @param vaultRegistry_ The vault registry address
    constructor(
        address admin_,
        address poolManager_,
        address asset_,
        address vaultRegistry_
    ) YieldCoreBase(admin_) {
        if (poolManager_ == address(0)) revert RWAErrors.ZeroAddress();
        if (asset_ == address(0)) revert RWAErrors.ZeroAddress();
        if (vaultRegistry_ == address(0)) revert RWAErrors.ZeroAddress();

        poolManager = poolManager_;
        asset = asset_;
        vaultRegistry = vaultRegistry_;

        // Deploy the RWAVault implementation contract
        vaultImplementation = address(new RWAVault(asset_));
    }

    // ============ Factory Functions ============

    /// @notice Creates a new RWA Fixed-term Vault
    /// @param params The vault parameters
    /// @return vault The deployed vault address
    function createVault(VaultParams calldata params)
        external
        nonReentrant
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address vault)
    {
        // Validate parameters
        if (bytes(params.name).length == 0) revert RWAErrors.InvalidVaultParams();
        if (bytes(params.symbol).length == 0) revert RWAErrors.InvalidVaultParams();
        if (params.collectionStartTime > params.collectionEndTime) revert RWAErrors.InvalidAmount();
        if (params.collectionEndTime <= block.timestamp) revert RWAErrors.InvalidAmount();
        if (params.interestStartTime < params.collectionEndTime) revert RWAErrors.InvalidAmount();
        if (params.fixedAPY > RWAConstants.MAX_TARGET_APY) {
            revert RWAErrors.InvalidAPY();
        }
        if (params.termDuration == 0) revert RWAErrors.InvalidAmount();

        // Validate interestPeriodEndDates
        if (params.interestPeriodEndDates.length > RWAConstants.MAX_PAYMENT_PERIODS) revert RWAErrors.ArrayTooLong();

        // Validate interestPaymentDates
        uint256 paymentDatesLen = params.interestPaymentDates.length;
        if (paymentDatesLen == 0) revert RWAErrors.PaymentDatesNotSet();
        if (paymentDatesLen > RWAConstants.MAX_PAYMENT_PERIODS) revert RWAErrors.ArrayTooLong();
        if (params.interestPaymentDates[0] < params.interestStartTime) {
            revert RWAErrors.InvalidAmount();
        }
        for (uint256 i = 1; i < paymentDatesLen;) {
            if (params.interestPaymentDates[i] <= params.interestPaymentDates[i - 1]) {
                revert RWAErrors.InvalidAmount();
            }
            unchecked { ++i; }
        }

        // Validate withdrawalStartTime (must be >= maturityTime)
        uint256 maturityTime = params.interestStartTime + params.termDuration;
        if (params.withdrawalStartTime < maturityTime) {
            revert RWAErrors.InvalidAmount();
        }

        // Deploy new vault clone
        vault = Clones.clone(vaultImplementation);

        // Initialize the vault (factory as initial admin to configure it)
        IRWAVault(vault).initialize(
            params.name,
            params.symbol,
            params.collectionStartTime,
            params.collectionEndTime,
            params.interestStartTime,
            params.termDuration,
            params.fixedAPY,
            params.minDeposit,
            params.maxCapacity,
            poolManager,
            address(this)  // Factory as initial admin
        );

        // Set interest period end dates (actual period boundaries)
        IRWAVault(vault).setInterestPeriodEndDates(params.interestPeriodEndDates);

        // Set interest payment dates (when interest becomes claimable)
        IRWAVault(vault).setInterestPaymentDates(params.interestPaymentDates);

        // Set withdrawal start time
        IRWAVault(vault).setWithdrawalStartTime(params.withdrawalStartTime);

        // Transfer admin to caller and renounce factory's admin role
        IAccessControl(vault).grantRole(0x00, msg.sender);  // DEFAULT_ADMIN_ROLE = 0x00
        IAccessControl(vault).grantRole(RWAConstants.PAUSER_ROLE, msg.sender);
        IAccessControl(vault).renounceRole(RWAConstants.PAUSER_ROLE, address(this));
        IAccessControl(vault).renounceRole(0x00, address(this));  // Renounce admin last

        // Register in factory
        _allVaults.push(vault);
        _isRegistered[vault] = true;
        _vaultInfos[vault] = VaultInfo({
            vaultAddress: vault,
            name: params.name,
            symbol: params.symbol,
            termDuration: params.termDuration,
            fixedAPY: params.fixedAPY,
            tvl: 0,
            active: true,
            createdAt: block.timestamp
        });

        // Register in pool manager
        IPoolManager(poolManager).registerVault(vault);

        // Register in vault registry
        IVaultRegistry(vaultRegistry).addVault(
            vault,
            params.name,
            params.symbol,
            params.termDuration,
            params.fixedAPY
        );

        emit RWAEvents.VaultCreated(
            vault,
            msg.sender,
            params.name,
            params.symbol,
            params.termDuration,
            params.fixedAPY,
            block.timestamp
        );
    }

    /// @notice Deactivates a vault in Factory and Registry tracking
    /// @dev Vault's setActive() must be called separately by vault admin
    /// @param vault The vault address
    function deactivateVault(address vault)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();

        _vaultInfos[vault].active = false;
        // Note: vault.setActive(false) must be called by vault admin separately
        IVaultRegistry(vaultRegistry).setVaultStatus(vault, false);

        emit RWAEvents.VaultDeactivated(vault, block.timestamp);
    }

    /// @notice Reactivates a vault in Factory and Registry tracking
    /// @dev Vault's setActive() must be called separately by vault admin
    /// @param vault The vault address
    function reactivateVault(address vault)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();

        _vaultInfos[vault].active = true;
        // Note: vault.setActive(true) must be called by vault admin separately
        IVaultRegistry(vaultRegistry).setVaultStatus(vault, true);

        emit RWAEvents.VaultReactivated(vault, block.timestamp);
    }

    // ============ View Functions ============

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
            if (_vaultInfos[_allVaults[i]].active) {
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

    /// @notice Gets vault info
    /// @param vault The vault address
    /// @return The vault info
    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        if (!_isRegistered[vault]) revert RWAErrors.VaultNotRegistered();

        VaultInfo memory info = _vaultInfos[vault];
        // Update TVL
        info.tvl = IERC4626(vault).totalAssets();

        return info;
    }

    /// @notice Gets the total vault count
    /// @return The number of vaults
    function getVaultCount() external view returns (uint256) {
        return _allVaults.length;
    }

    /// @notice Checks if a vault is registered
    /// @param vault The vault address
    /// @return True if registered
    function isRegisteredVault(address vault) external view returns (bool) {
        return _isRegistered[vault];
    }

    /// @notice Gets total TVL across all active vaults
    /// @return The total TVL
    function getTotalTVL() external view returns (uint256) {
        uint256 totalTVL = 0;
        uint256 length = _allVaults.length;

        for (uint256 i = 0; i < length;) {
            if (_vaultInfos[_allVaults[i]].active) {
                totalTVL += IERC4626(_allVaults[i]).totalAssets();
            }
            unchecked { ++i; }
        }

        return totalTVL;
    }
}
