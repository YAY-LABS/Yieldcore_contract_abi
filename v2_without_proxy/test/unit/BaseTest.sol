// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {LoanRegistry} from "../../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../../src/core/VaultRegistry.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../src/libraries/RWAErrors.sol";
import {ILoanRegistry} from "../../src/interfaces/ILoanRegistry.sol";
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";

/// @title BaseTest
/// @notice Base test contract with common setup
abstract contract BaseTest is Test {
    // ============ Contracts ============
    MockERC20 public usdc;
    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;

    // ============ Addresses ============
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public curator = makeAddr("curator");
    address public operator = makeAddr("operator");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public borrower = makeAddr("borrower");

    // ============ Constants ============
    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 public constant PROTOCOL_FEE = 500; // 5%
    uint256 public constant MIN_CAPITAL = 10_000e6; // 10K USDC

    // ============ Setup ============

    function setUp() public virtual {
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Mint initial balances
        usdc.mint(admin, INITIAL_BALANCE);
        usdc.mint(curator, INITIAL_BALANCE);
        usdc.mint(operator, INITIAL_BALANCE);
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(borrower, INITIAL_BALANCE);

        // Deploy contracts
        _deployCore();

        // Mint USDC to poolManager for depositInterest calls
        usdc.mint(address(poolManager), INITIAL_BALANCE);
    }

    function _deployCore() internal {
        vm.startPrank(admin);

        // 1. Deploy LoanRegistry
        loanRegistry = new LoanRegistry(admin);

        // 2. Deploy VaultRegistry
        vaultRegistry = new VaultRegistry(admin);

        // 3. Deploy PoolManager
        poolManager = new PoolManager(
            admin,
            address(usdc),
            address(loanRegistry),
            treasury,
            PROTOCOL_FEE
        );

        // 4. Deploy VaultFactory
        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            address(usdc),
            address(vaultRegistry)
        );

        // 5. Setup roles
        // Grant POOL_MANAGER_ROLE to poolManager on loanRegistry
        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));

        // Grant CURATOR_ROLE to curator
        poolManager.grantRole(RWAConstants.CURATOR_ROLE, curator);

        // Grant OPERATOR_ROLE to operator
        poolManager.grantRole(RWAConstants.OPERATOR_ROLE, operator);

        // Grant DEFAULT_ADMIN_ROLE to vaultFactory on vaultRegistry (for addVault)
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        // Grant DEFAULT_ADMIN_ROLE to vaultFactory on poolManager (for registerVault)
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        vm.stopPrank();
    }

    // ============ Helpers ============

    function _createDefaultVault() internal returns (address vault) {
        vm.startPrank(admin);

        // Create a vault with:
        // - Collection period: 7 days from now
        // - Interest start: 7 days from now
        // - Term: 180 days
        // - 15% APY
        uint256 interestStart = block.timestamp + 7 days;
        uint256 maturityTime = interestStart + 180 days;

        // Period end dates (actual end of each interest period)
        uint256[] memory periodEndDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
        }

        // Payment dates (when interest becomes claimable - a few days after period end)
        uint256[] memory paymentDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "YieldCore RWA Vault",
            symbol: "ycRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 1500, // 15%
            minDeposit: 100e6, // 100 USDC
            maxCapacity: 10_000_000e6, // 10M USDC
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        vault = vaultFactory.createVault(params);

        vm.stopPrank();
    }

    function _createVaultWithParams(
        uint256 collectionDuration,
        uint256 termDuration,
        uint256 fixedAPY
    ) internal returns (address vault) {
        vm.startPrank(admin);

        // Generate interest dates based on term duration
        uint256 interestStart = block.timestamp + collectionDuration;
        uint256 maturityTime = interestStart + termDuration;
        uint256 monthCount = termDuration / 30 days;
        if (monthCount == 0) monthCount = 1;

        // Period end dates (actual end of each interest period)
        uint256[] memory periodEndDates = new uint256[](monthCount);
        for (uint256 i = 0; i < monthCount; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
        }

        // Payment dates (when interest becomes claimable - a few days after period end)
        uint256[] memory paymentDates = new uint256[](monthCount);
        for (uint256 i = 0; i < monthCount; i++) {
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "YieldCore RWA Vault",
            symbol: "ycRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + collectionDuration,
            interestStartTime: interestStart,
            termDuration: termDuration,
            fixedAPY: fixedAPY,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });

        vault = vaultFactory.createVault(params);

        vm.stopPrank();
    }

    function _depositToVault(address vault, address user, uint256 amount) internal {
        vm.startPrank(user);
        usdc.approve(vault, amount);
        RWAVault(vault).deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Helper to deploy capital through PoolManager with timelock
    /// @dev Calls announceDeployCapital, warps time, then executeDeployCapital
    function _deployCapital(address vault, uint256 amount, address recipient) internal {
        vm.startPrank(curator);
        poolManager.announceDeployCapital(vault, amount, recipient);
        vm.stopPrank();

        // Warp past timelock
        uint256 delay = RWAVault(vault).deploymentDelay();
        vm.warp(block.timestamp + delay + 1);

        vm.startPrank(curator);
        poolManager.executeDeployCapital(vault);
        vm.stopPrank();
    }

    /// @notice Helper to deploy capital with custom caller
    function _deployCapitalAs(address vault, uint256 amount, address recipient, address caller) internal {
        vm.startPrank(caller);
        poolManager.announceDeployCapital(vault, amount, recipient);
        vm.stopPrank();

        uint256 delay = RWAVault(vault).deploymentDelay();
        vm.warp(block.timestamp + delay + 1);

        vm.startPrank(caller);
        poolManager.executeDeployCapital(vault);
        vm.stopPrank();
    }

    /// @notice Helper to return capital through PoolManager
    function _returnCapital(address vault, uint256 amount) internal {
        vm.startPrank(operator);
        usdc.approve(address(poolManager), amount);
        poolManager.returnCapital(vault, amount);
        vm.stopPrank();
    }

    /// @notice Helper to deposit interest through PoolManager
    function _depositInterest(address vault, uint256 amount) internal {
        vm.startPrank(operator);
        usdc.approve(address(poolManager), amount);
        poolManager.depositInterest(vault, amount);
        vm.stopPrank();
    }
}
