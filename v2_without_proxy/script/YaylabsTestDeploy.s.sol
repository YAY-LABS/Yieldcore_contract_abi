// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {LoanRegistry} from "../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../src/core/VaultRegistry.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {RWAVault} from "../src/vault/RWAVault.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {RWAConstants} from "../src/libraries/RWAConstants.sol";

/// @title YaylabsTestDeploy
/// @notice Deploys YieldCore RWA Protocol with Safe multisig as admin
/// @dev All permissions are transferred to Safe, deployer retains NO permissions
contract YaylabsTestDeploy is Script {
    // ============ Configuration ============

    /// @notice Safe multisig address (receives ALL admin permissions)
    address public constant SAFE_MULTISIG = 0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE;

    /// @notice MockUSDC on Sepolia (existing)
    address public constant MOCK_USDC = 0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7;

    /// @notice Protocol fee in basis points (0%)
    uint256 public constant PROTOCOL_FEE = 0;

    // ============ Deployed Contracts ============

    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("==============================================");
        console2.log("   YieldCore RWA Protocol - Yaylabs Deploy    ");
        console2.log("==============================================");
        console2.log("");
        console2.log("Deployer:", deployer);
        console2.log("Safe Multisig:", SAFE_MULTISIG);
        console2.log("MockUSDC:", MOCK_USDC);
        console2.log("Protocol Fee:", PROTOCOL_FEE, "bps (0%)");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy all contracts with deployer as initial admin
        _deployContracts(deployer);

        // Step 2: Setup inter-contract roles
        _setupContractRoles();

        // Step 3: Grant all roles to Safe multisig
        _grantRolesToSafe();

        // Step 4: Revoke all roles from deployer
        _revokeDeployerRoles(deployer);

        vm.stopBroadcast();

        // Log final state
        _logDeployment();
        _verifyPermissions(deployer);
    }

    function _deployContracts(address deployer) internal {
        console2.log("=== Step 1: Deploying Contracts ===");
        console2.log("");

        // 1. LoanRegistry
        console2.log("1. Deploying LoanRegistry...");
        loanRegistry = new LoanRegistry(deployer);
        console2.log("   Address:", address(loanRegistry));

        // 2. VaultRegistry
        console2.log("2. Deploying VaultRegistry...");
        vaultRegistry = new VaultRegistry(deployer);
        console2.log("   Address:", address(vaultRegistry));

        // 3. PoolManager
        console2.log("3. Deploying PoolManager...");
        poolManager = new PoolManager(
            deployer,           // admin (temporary)
            MOCK_USDC,          // asset
            address(loanRegistry),
            SAFE_MULTISIG,      // treasury (fees go to Safe)
            PROTOCOL_FEE
        );
        console2.log("   Address:", address(poolManager));

        // 4. VaultFactory
        console2.log("4. Deploying VaultFactory...");
        vaultFactory = new VaultFactory(
            deployer,           // admin (temporary)
            address(poolManager),
            MOCK_USDC,
            address(vaultRegistry)
        );
        console2.log("   Address:", address(vaultFactory));
        console2.log("");
    }

    function _setupContractRoles() internal {
        console2.log("=== Step 2: Setting Up Contract Roles ===");
        console2.log("");

        // PoolManager needs POOL_MANAGER_ROLE on LoanRegistry
        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));
        console2.log("- LoanRegistry: granted POOL_MANAGER_ROLE to PoolManager");

        // VaultFactory needs DEFAULT_ADMIN_ROLE on VaultRegistry
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        console2.log("- VaultRegistry: granted DEFAULT_ADMIN_ROLE to VaultFactory");

        // VaultFactory needs DEFAULT_ADMIN_ROLE on PoolManager (to register vaults)
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        console2.log("- PoolManager: granted DEFAULT_ADMIN_ROLE to VaultFactory");
        console2.log("");
    }

    function _grantRolesToSafe() internal {
        console2.log("=== Step 3: Granting Roles to Safe Multisig ===");
        console2.log("");

        bytes32 DEFAULT_ADMIN = 0x00;

        // LoanRegistry
        loanRegistry.grantRole(DEFAULT_ADMIN, SAFE_MULTISIG);
        loanRegistry.grantRole(RWAConstants.PAUSER_ROLE, SAFE_MULTISIG);
        console2.log("- LoanRegistry: granted DEFAULT_ADMIN_ROLE, PAUSER_ROLE");

        // VaultRegistry
        vaultRegistry.grantRole(DEFAULT_ADMIN, SAFE_MULTISIG);
        vaultRegistry.grantRole(RWAConstants.PAUSER_ROLE, SAFE_MULTISIG);
        console2.log("- VaultRegistry: granted DEFAULT_ADMIN_ROLE, PAUSER_ROLE");

        // PoolManager
        poolManager.grantRole(DEFAULT_ADMIN, SAFE_MULTISIG);
        poolManager.grantRole(RWAConstants.PAUSER_ROLE, SAFE_MULTISIG);
        poolManager.grantRole(RWAConstants.CURATOR_ROLE, SAFE_MULTISIG);
        poolManager.grantRole(RWAConstants.OPERATOR_ROLE, SAFE_MULTISIG);
        console2.log("- PoolManager: granted DEFAULT_ADMIN_ROLE, PAUSER_ROLE, CURATOR_ROLE, OPERATOR_ROLE");

        // VaultFactory
        vaultFactory.grantRole(DEFAULT_ADMIN, SAFE_MULTISIG);
        vaultFactory.grantRole(RWAConstants.PAUSER_ROLE, SAFE_MULTISIG);
        console2.log("- VaultFactory: granted DEFAULT_ADMIN_ROLE, PAUSER_ROLE");
        console2.log("");
    }

    function _revokeDeployerRoles(address deployer) internal {
        console2.log("=== Step 4: Revoking Deployer Roles ===");
        console2.log("");

        bytes32 DEFAULT_ADMIN = 0x00;

        // LoanRegistry
        loanRegistry.revokeRole(RWAConstants.PAUSER_ROLE, deployer);
        loanRegistry.revokeRole(DEFAULT_ADMIN, deployer);
        console2.log("- LoanRegistry: revoked all deployer roles");

        // VaultRegistry
        vaultRegistry.revokeRole(RWAConstants.PAUSER_ROLE, deployer);
        vaultRegistry.revokeRole(DEFAULT_ADMIN, deployer);
        console2.log("- VaultRegistry: revoked all deployer roles");

        // PoolManager
        poolManager.revokeRole(RWAConstants.OPERATOR_ROLE, deployer);
        poolManager.revokeRole(RWAConstants.CURATOR_ROLE, deployer);
        poolManager.revokeRole(RWAConstants.PAUSER_ROLE, deployer);
        poolManager.revokeRole(DEFAULT_ADMIN, deployer);
        console2.log("- PoolManager: revoked all deployer roles");

        // VaultFactory
        vaultFactory.revokeRole(RWAConstants.PAUSER_ROLE, deployer);
        vaultFactory.revokeRole(DEFAULT_ADMIN, deployer);
        console2.log("- VaultFactory: revoked all deployer roles");
        console2.log("");
    }

    function _logDeployment() internal view {
        console2.log("==============================================");
        console2.log("         DEPLOYMENT COMPLETE                  ");
        console2.log("==============================================");
        console2.log("");
        console2.log("Contract Addresses:");
        console2.log("-------------------");
        console2.log("LoanRegistry:   ", address(loanRegistry));
        console2.log("VaultRegistry:  ", address(vaultRegistry));
        console2.log("PoolManager:    ", address(poolManager));
        console2.log("VaultFactory:   ", address(vaultFactory));
        console2.log("");
        console2.log("Configuration:");
        console2.log("--------------");
        console2.log("Safe Multisig:  ", SAFE_MULTISIG);
        console2.log("MockUSDC:       ", MOCK_USDC);
        console2.log("Treasury:       ", SAFE_MULTISIG);
        console2.log("Protocol Fee:   ", PROTOCOL_FEE, "bps");
        console2.log("");
    }

    function _verifyPermissions(address deployer) internal view {
        console2.log("=== Permission Verification ===");
        console2.log("");

        bytes32 DEFAULT_ADMIN = 0x00;

        // Check Safe has admin
        bool safeHasAdmin = loanRegistry.hasRole(DEFAULT_ADMIN, SAFE_MULTISIG) &&
                           vaultRegistry.hasRole(DEFAULT_ADMIN, SAFE_MULTISIG) &&
                           poolManager.hasRole(DEFAULT_ADMIN, SAFE_MULTISIG) &&
                           vaultFactory.hasRole(DEFAULT_ADMIN, SAFE_MULTISIG);

        console2.log("Safe has DEFAULT_ADMIN on all contracts:", safeHasAdmin ? "YES" : "NO");

        // Check deployer has NO admin
        bool deployerHasNoAdmin = !loanRegistry.hasRole(DEFAULT_ADMIN, deployer) &&
                                  !vaultRegistry.hasRole(DEFAULT_ADMIN, deployer) &&
                                  !poolManager.hasRole(DEFAULT_ADMIN, deployer) &&
                                  !vaultFactory.hasRole(DEFAULT_ADMIN, deployer);

        console2.log("Deployer has NO admin on any contract:", deployerHasNoAdmin ? "YES" : "NO");
        console2.log("");

        if (safeHasAdmin && deployerHasNoAdmin) {
            console2.log("SUCCESS: All permissions correctly transferred to Safe!");
        } else {
            console2.log("WARNING: Permission transfer may be incomplete!");
        }
        console2.log("");
    }
}
