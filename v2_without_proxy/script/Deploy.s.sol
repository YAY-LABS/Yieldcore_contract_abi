// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {LoanRegistry} from "../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../src/core/VaultRegistry.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {RWAVault} from "../src/vault/RWAVault.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {RWAConstants} from "../src/libraries/RWAConstants.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @title DeployYieldCoreRWA
/// @notice Deployment script for YieldCore RWA Protocol
/// @dev Run with: forge script script/Deploy.s.sol:DeployYieldCoreRWA --rpc-url <RPC_URL> --broadcast --verify
contract DeployYieldCoreRWA is Script {
    // ============ Deployment Config ============

    /// @notice Protocol fee in basis points (5%)
    uint256 public constant PROTOCOL_FEE = 500;

    // ============ Deployed Contracts ============

    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;

    /// @notice Main deployment function
    function run() external {
        // Load config from environment
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address asset = vm.envAddress("ASSET_ADDRESS"); // USDC address

        console2.log("=== YieldCore RWA Protocol Deployment ===");
        console2.log("Admin:", admin);
        console2.log("Treasury:", treasury);
        console2.log("Asset:", asset);
        console2.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy all contracts
        _deployCore(admin, treasury, asset);
        _setupRoles(admin);

        vm.stopBroadcast();

        // Log deployed addresses
        _logDeployedAddresses();
    }

    /// @notice Deploys core protocol contracts
    function _deployCore(address admin, address treasury, address asset) internal {
        console2.log("Deploying core contracts...");

        // 1. Deploy LoanRegistry
        console2.log("1. Deploying LoanRegistry...");
        loanRegistry = new LoanRegistry(admin);
        console2.log("   LoanRegistry:", address(loanRegistry));

        // 2. Deploy VaultRegistry
        console2.log("2. Deploying VaultRegistry...");
        vaultRegistry = new VaultRegistry(admin);
        console2.log("   VaultRegistry:", address(vaultRegistry));

        // 3. Deploy PoolManager
        console2.log("3. Deploying PoolManager...");
        poolManager = new PoolManager(
            admin,
            asset,
            address(loanRegistry),
            treasury,
            PROTOCOL_FEE
        );
        console2.log("   PoolManager:", address(poolManager));

        // 4. Deploy VaultFactory
        console2.log("4. Deploying VaultFactory...");
        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            asset,
            address(vaultRegistry)
        );
        console2.log("   VaultFactory:", address(vaultFactory));

        console2.log("");
    }

    /// @notice Sets up roles between contracts
    function _setupRoles(address admin) internal {
        console2.log("Setting up roles...");

        // Grant POOL_MANAGER_ROLE to poolManager on loanRegistry
        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));
        console2.log("   Granted POOL_MANAGER_ROLE on LoanRegistry to PoolManager");

        // Grant DEFAULT_ADMIN_ROLE to vaultFactory on vaultRegistry
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        console2.log("   Granted DEFAULT_ADMIN_ROLE on VaultRegistry to VaultFactory");

        // Grant DEFAULT_ADMIN_ROLE to vaultFactory on poolManager
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        console2.log("   Granted DEFAULT_ADMIN_ROLE on PoolManager to VaultFactory");

        console2.log("");
    }

    /// @notice Logs all deployed contract addresses
    function _logDeployedAddresses() internal view {
        console2.log("=== Deployed Contract Addresses ===");
        console2.log("LoanRegistry:      ", address(loanRegistry));
        console2.log("VaultRegistry:     ", address(vaultRegistry));
        console2.log("PoolManager:       ", address(poolManager));
        console2.log("VaultFactory:      ", address(vaultFactory));
        console2.log("===================================");
    }
}

/// @title CreateVault
/// @notice Script to create a new RWA Fixed-term Vault
/// @dev Run with: forge script script/Deploy.s.sol:CreateVault --rpc-url <RPC_URL> --broadcast
contract CreateVault is Script {
    function run() external {
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY_ADDRESS");

        // Vault parameters
        string memory name = vm.envOr("VAULT_NAME", string("YieldCore RWA Vault"));
        string memory symbol = vm.envOr("VAULT_SYMBOL", string("ycRWA"));
        uint256 collectionDuration = vm.envOr("COLLECTION_DURATION", uint256(7 days));
        uint256 termDuration = vm.envOr("TERM_DURATION", uint256(180 days));
        uint256 fixedAPY = vm.envOr("FIXED_APY", uint256(1500)); // 15%
        uint256 minDeposit = vm.envOr("MIN_DEPOSIT", uint256(100e6)); // 100 USDC
        uint256 maxCapacity = vm.envOr("MAX_CAPACITY", uint256(10_000_000e6)); // 10M USDC

        console2.log("=== Creating New Fixed-term Vault ===");
        console2.log("Name:", name);
        console2.log("Symbol:", symbol);
        console2.log("Collection Duration:", collectionDuration / 1 days, "days");
        console2.log("Term Duration:", termDuration / 1 days, "days");
        console2.log("Fixed APY:", fixedAPY, "bps");
        console2.log("Min Deposit:", minDeposit / 1e6, "USDC");
        console2.log("Max Capacity:", maxCapacity / 1e6, "USDC");
        console2.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddress);

        // Generate monthly interest period end dates and payment dates
        uint256 interestStartTime = block.timestamp + collectionDuration;
        uint256 months = termDuration / 30 days;
        if (months == 0) months = 1;

        // Period end dates (actual end of each interest period)
        uint256[] memory periodEndDates = new uint256[](months);
        for (uint256 i = 0; i < months; i++) {
            periodEndDates[i] = interestStartTime + ((i + 1) * 30 days);
        }

        // Payment dates (when interest becomes claimable - a few days after period end)
        uint256[] memory paymentDates = new uint256[](months);
        for (uint256 i = 0; i < months; i++) {
            paymentDates[i] = interestStartTime + ((i + 1) * 30 days) + 3 days;
        }

        uint256 maturityTime = interestStartTime + termDuration;

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: name,
            symbol: symbol,
            collectionStartTime: 0, // 0 = immediate deposit allowed
            collectionEndTime: block.timestamp + collectionDuration,
            interestStartTime: interestStartTime,
            termDuration: termDuration,
            fixedAPY: fixedAPY,
            minDeposit: minDeposit,
            maxCapacity: maxCapacity,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        address vault = vaultFactory.createVault(params);

        vm.stopBroadcast();

        console2.log("=== Vault Created ===");
        console2.log("Vault Address:", vault);
    }
}

/// @title DepositToVault
/// @notice Script to deposit USDC to a vault
/// @dev Run with: forge script script/Deploy.s.sol:DepositToVault --rpc-url <RPC_URL> --broadcast
contract DepositToVault is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(1000e6)); // Default 1000 USDC

        console2.log("=== Depositing to Vault ===");
        console2.log("Vault:", vaultAddress);
        console2.log("Asset:", assetAddress);
        console2.log("Amount:", depositAmount / 1e6, "USDC");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address depositor = vm.addr(deployerPrivateKey);
        console2.log("Depositor:", depositor);

        vm.startBroadcast(deployerPrivateKey);

        // Approve vault to spend USDC
        IERC20(assetAddress).approve(vaultAddress, depositAmount);
        console2.log("Approved vault to spend USDC");

        // Deposit to vault
        RWAVault vault = RWAVault(vaultAddress);
        uint256 shares = vault.deposit(depositAmount, depositor);

        vm.stopBroadcast();

        console2.log("=== Deposit Complete ===");
        console2.log("Shares received:", shares);
        console2.log("Total assets in vault:", vault.totalAssets() / 1e6, "USDC");
    }
}

/// @title ClaimInterest
/// @notice Script to claim accrued interest from a vault
/// @dev Run with: forge script script/Deploy.s.sol:ClaimInterest --rpc-url <RPC_URL> --broadcast
contract ClaimInterest is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");

        console2.log("=== Claiming Interest ===");
        console2.log("Vault:", vaultAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address claimer = vm.addr(deployerPrivateKey);
        console2.log("Claimer:", claimer);

        RWAVault vault = RWAVault(vaultAddress);

        // Check pending interest
        uint256 pendingInterest = vault.getPendingInterest(claimer);
        console2.log("Pending interest:", pendingInterest / 1e6, "USDC");

        if (pendingInterest == 0) {
            console2.log("No interest to claim");
            return;
        }

        // Get balance before claim
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(claimer);

        vm.startBroadcast(deployerPrivateKey);

        vault.claimInterest();

        vm.stopBroadcast();

        uint256 balanceAfter = IERC20(assetAddress).balanceOf(claimer);
        uint256 claimed = balanceAfter - balanceBefore;

        console2.log("=== Claim Complete ===");
        console2.log("Interest claimed:", claimed / 1e6, "USDC");
    }
}

/// @title WithdrawFromVault
/// @notice Script to withdraw principal from a matured vault
/// @dev Run with: forge script script/Deploy.s.sol:WithdrawFromVault --rpc-url <RPC_URL> --broadcast
contract WithdrawFromVault is Script {
    function run() external {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        console2.log("=== Withdrawing from Vault ===");
        console2.log("Vault:", vaultAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address withdrawer = vm.addr(deployerPrivateKey);
        console2.log("Withdrawer:", withdrawer);

        RWAVault vault = RWAVault(vaultAddress);

        // Check current phase
        uint8 phase = uint8(vault.currentPhase());
        console2.log("Current phase:", phase);

        // Check balance
        uint256 shares = vault.balanceOf(withdrawer);
        console2.log("Shares owned:", shares);

        if (shares == 0) {
            console2.log("No shares to redeem");
            return;
        }

        // Check max redeemable
        uint256 maxRedeemable = vault.maxRedeem(withdrawer);
        console2.log("Max redeemable:", maxRedeemable);

        if (maxRedeemable == 0) {
            console2.log("Cannot redeem yet (check phase and withdrawalStartTime)");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        uint256 assets = vault.redeem(shares, withdrawer, withdrawer);

        vm.stopBroadcast();

        console2.log("=== Withdrawal Complete ===");
        console2.log("Assets received:", assets / 1e6, "USDC");
    }
}

/// @title VaultStatus
/// @notice Script to check vault status (view only, no broadcast)
/// @dev Run with: forge script script/Deploy.s.sol:VaultStatus --rpc-url <RPC_URL>
contract VaultStatus is Script {
    function run() external view {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        RWAVault vault = RWAVault(vaultAddress);

        console2.log("=== Vault Status ===");
        console2.log("Address:", vaultAddress);
        console2.log("Name:", vault.name());
        console2.log("Symbol:", vault.symbol());
        console2.log("");

        // Phase info
        uint8 phase = uint8(vault.currentPhase());
        string memory phaseName;
        if (phase == 0) phaseName = "Collecting";
        else if (phase == 1) phaseName = "Active";
        else if (phase == 2) phaseName = "Matured";
        else if (phase == 3) phaseName = "Defaulted";
        console2.log("Phase:", phaseName);
        console2.log("Active:", vault.active());
        console2.log("");

        // Financial info
        console2.log("Total Assets:", vault.totalAssets() / 1e6, "USDC");
        console2.log("Total Supply:", vault.totalSupply());
        console2.log("Total Principal:", vault.totalPrincipal() / 1e6, "USDC");
        console2.log("Fixed APY:", vault.fixedAPY(), "bps");
        console2.log("");

        // Time info
        console2.log("Collection End:", vault.collectionEndTime());
        console2.log("Interest Start:", vault.interestStartTime());
        console2.log("Maturity Time:", vault.maturityTime());
        console2.log("Withdrawal Start:", vault.withdrawalStartTime());
        console2.log("Current Time:", block.timestamp);
        console2.log("");

        // Capacity info
        console2.log("Max Capacity:", vault.maxCapacity() / 1e6, "USDC");
        console2.log("Min Deposit:", vault.minDeposit() / 1e6, "USDC");
    }
}

/// @title UserStatus
/// @notice Script to check user's position in a vault (view only)
/// @dev Run with: forge script script/Deploy.s.sol:UserStatus --rpc-url <RPC_URL>
contract UserStatus is Script {
    function run() external view {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address userAddress = vm.envAddress("USER_ADDRESS");

        RWAVault vault = RWAVault(vaultAddress);

        console2.log("=== User Status ===");
        console2.log("Vault:", vaultAddress);
        console2.log("User:", userAddress);
        console2.log("");

        // Get deposit info
        (uint256 shares, uint256 principal, uint256 lastClaimMonth, uint256 depositTime) = vault.getDepositInfo(userAddress);

        console2.log("Shares:", shares);
        console2.log("Principal:", principal / 1e6, "USDC");
        console2.log("Last Claim Month:", lastClaimMonth);
        console2.log("Deposit Time:", depositTime);
        console2.log("");

        // Get pending interest
        uint256 pendingInterest = vault.getPendingInterest(userAddress);
        console2.log("Pending Interest:", pendingInterest / 1e6, "USDC");

        // Get max actions
        console2.log("Max Withdraw:", vault.maxWithdraw(userAddress) / 1e6, "USDC");
        console2.log("Max Redeem:", vault.maxRedeem(userAddress));
    }
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
