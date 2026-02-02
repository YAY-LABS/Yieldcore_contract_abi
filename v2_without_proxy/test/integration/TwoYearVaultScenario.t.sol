// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20} from "../unit/mocks/MockERC20.sol";
import {LoanRegistry} from "../../src/core/LoanRegistry.sol";
import {VaultRegistry} from "../../src/core/VaultRegistry.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";
import {RWAConstants} from "../../src/libraries/RWAConstants.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";

/// @title TwoYearVaultScenario
/// @notice 2-year term real-world scenario integration test
/// @dev Scenario: $1M hard cap, $1K-$10K allocation, 12% APY, 24 months, 100 users
contract TwoYearVaultScenarioTest is Test {
    MockERC20 public usdc;
    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;
    RWAVault public vault;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public operator = makeAddr("operator");

    uint256 public constant HARD_CAP = 1_000_000e6;
    uint256 public constant MIN_ALLOCATION = 1_000e6;
    uint256 public constant MAX_ALLOCATION = 10_000e6;
    uint256 public constant APY = 1200; // 12%
    uint256 public constant TERM_DURATION = 730 days; // ~2 years
    uint256 public constant COLLECTION_PERIOD = 14 days;
    uint256 public constant NUM_USERS = 100;

    address[] public users;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            users.push(user);
            usdc.mint(user, MAX_ALLOCATION * 2);
        }

        _deployCore();
        _createTwoYearVault();

        usdc.mint(address(poolManager), 500_000e6);
    }

    function _deployCore() internal {
        vm.startPrank(admin);

        loanRegistry = new LoanRegistry(admin);
        vaultRegistry = new VaultRegistry(admin);

        poolManager = new PoolManager(
            admin,
            address(usdc),
            address(loanRegistry),
            treasury,
            500
        );

        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            address(usdc),
            address(vaultRegistry)
        );

        loanRegistry.grantRole(RWAConstants.POOL_MANAGER_ROLE, address(poolManager));
        poolManager.grantRole(RWAConstants.OPERATOR_ROLE, operator);
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        vm.stopPrank();
    }

    function _createTwoYearVault() internal {
        vm.startPrank(admin);

        uint256 interestStart = block.timestamp + COLLECTION_PERIOD;
        uint256 maturityTime = interestStart + TERM_DURATION;
        uint256 monthCount = 24;

        uint256[] memory periodEndDates = new uint256[](monthCount);
        for (uint256 i = 0; i < monthCount; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
        }

        uint256[] memory paymentDates = new uint256[](monthCount);
        for (uint256 i = 0; i < monthCount; i++) {
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "YieldCore 2Y RWA Vault",
            symbol: "yc2YRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + COLLECTION_PERIOD,
            interestStartTime: interestStart,
            termDuration: TERM_DURATION,
            fixedAPY: APY,
            minDeposit: MIN_ALLOCATION,
            maxCapacity: HARD_CAP,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime + 3 days
        });

        address vaultAddr = vaultFactory.createVault(params);
        vault = RWAVault(vaultAddr);

        vm.stopPrank();
    }

    function test_fullTwoYearScenario() public {
        console2.log("=== 2 Year Vault Full Scenario Test ===");
        console2.log("Hard Cap:", HARD_CAP / 1e6, "USDC");
        console2.log("APY:", APY / 100, "%");
        console2.log("Users:", NUM_USERS);

        // Phase 1: Collection
        console2.log("\n--- Phase 1: Collection ---");

        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(vault), MAX_ALLOCATION);
            vault.deposit(MAX_ALLOCATION, users[i]);
            vm.stopPrank();
        }

        assertEq(vault.totalAssets(), HARD_CAP, "Cap should be filled");
        assertEq(vault.totalPrincipal(), HARD_CAP, "Total principal should match");
        console2.log("Total deposited:", vault.totalAssets() / 1e6, "USDC");
        console2.log("Cap filled: 100%");

        // Phase 2: Activate Vault
        console2.log("\n--- Phase 2: Activate Vault ---");

        vm.warp(block.timestamp + COLLECTION_PERIOD + 1);

        vm.prank(admin);
        vault.activateVault();

        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Active), "Vault should be active");
        console2.log("Vault activated at:", block.timestamp);

        // Phase 3: Deploy Capital
        console2.log("\n--- Phase 3: Deploy Capital ---");

        uint256 deployAmount = (HARD_CAP * 80) / 100;
        vm.prank(address(poolManager));
        vault.deployCapital(deployAmount, address(poolManager));

        assertEq(vault.totalDeployed(), deployAmount, "Deploy amount mismatch");
        console2.log("Deployed:", deployAmount / 1e6, "USDC (80%)");
        console2.log("Remaining liquidity:", vault.availableLiquidity() / 1e6, "USDC");

        // Phase 4: Monthly Interest Claims
        console2.log("\n--- Phase 4: Interest Claims ---");

        uint256 monthlyInterestPerUser = (MAX_ALLOCATION * APY) / (12 * 10000);
        console2.log("Expected monthly interest per user:", monthlyInterestPerUser / 1e6, "USDC");

        uint256 totalClaimedByUser0 = 0;
        for (uint256 month = 1; month <= 6; month++) {
            uint256 paymentDate = vault.interestPaymentDates(month - 1);
            vm.warp(paymentDate + 1);

            uint256 totalMonthlyInterest = (HARD_CAP * APY) / (12 * 10000);
            vm.startPrank(address(poolManager));
            usdc.approve(address(vault), totalMonthlyInterest);
            vault.depositInterest(totalMonthlyInterest);
            vm.stopPrank();

            address sampleUser = users[0];
            uint256 balanceBefore = usdc.balanceOf(sampleUser);

            vm.prank(sampleUser);
            vault.claimInterest();

            uint256 claimed = usdc.balanceOf(sampleUser) - balanceBefore;
            totalClaimedByUser0 += claimed;
            console2.log("Month %d - User0 claimed: %d USDC", month, claimed / 1e6);

            assertApproxEqRel(claimed, monthlyInterestPerUser, 0.05e18, "Monthly interest mismatch");
        }

        uint256 expectedTotal6Months = monthlyInterestPerUser * 6;
        assertApproxEqRel(totalClaimedByUser0, expectedTotal6Months, 0.02e18, "Total 6-month interest mismatch");

        // Phase 5: Return Capital
        console2.log("\n--- Phase 5: Return Capital ---");

        vm.warp(block.timestamp + 500 days);

        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), deployAmount);
        vault.returnCapital(deployAmount);
        vm.stopPrank();

        assertEq(vault.totalDeployed(), 0, "All capital should be returned");
        console2.log("Capital returned:", deployAmount / 1e6, "USDC");

        // Phase 6: Maturity & Withdrawal
        console2.log("\n--- Phase 6: Maturity & Withdrawal ---");

        vm.warp(vault.withdrawalStartTime() + 1);

        vm.prank(admin);
        vault.matureVault();
        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Matured), "Vault should be matured");

        uint256 remainingMonths = 18;
        uint256 remainingInterest = (HARD_CAP * APY * remainingMonths) / (12 * 10000);
        vm.startPrank(address(poolManager));
        usdc.approve(address(vault), remainingInterest);
        vault.depositInterest(remainingInterest);
        vm.stopPrank();

        console2.log("Remaining interest deposited:", remainingInterest / 1e6, "USDC");

        for (uint256 i = 0; i < 5; i++) {
            address user = users[i];
            uint256 shares = vault.balanceOf(user);
            uint256 balanceBefore = usdc.balanceOf(user);

            vm.prank(user);
            vault.redeem(shares, user, user);

            uint256 received = usdc.balanceOf(user) - balanceBefore;
            console2.log("User %d withdrew: %d USDC", i, received / 1e6);

            if (i == 0) {
                uint256 expectedRemaining = MAX_ALLOCATION + (MAX_ALLOCATION * APY * 18) / (12 * 10000);
                assertApproxEqRel(received, expectedRemaining, 0.05e18, "User0 withdrawal mismatch");
            } else {
                uint256 expectedFull = MAX_ALLOCATION + (MAX_ALLOCATION * APY * 24) / (12 * 10000);
                assertApproxEqRel(received, expectedFull, 0.05e18, "User withdrawal mismatch");
            }
        }

        console2.log("\n=== Test Complete ===");
    }

    function test_minAllocationEnforced() public {
        address smallUser = makeAddr("smallUser");
        usdc.mint(smallUser, MIN_ALLOCATION);

        vm.startPrank(smallUser);
        usdc.approve(address(vault), MIN_ALLOCATION - 1);
        vm.expectRevert();
        vault.deposit(MIN_ALLOCATION - 1, smallUser);
        vm.stopPrank();
    }

    function test_capacityExceeded() public {
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(vault), MAX_ALLOCATION);
            vault.deposit(MAX_ALLOCATION, users[i]);
            vm.stopPrank();
        }

        address extraUser = makeAddr("extraUser");
        usdc.mint(extraUser, MIN_ALLOCATION);

        vm.startPrank(extraUser);
        usdc.approve(address(vault), MIN_ALLOCATION);
        vm.expectRevert();
        vault.deposit(MIN_ALLOCATION, extraUser);
        vm.stopPrank();
    }

    function test_interestClaimBeforePaymentDate() public {
        vm.startPrank(users[0]);
        usdc.approve(address(vault), MAX_ALLOCATION);
        vault.deposit(MAX_ALLOCATION, users[0]);
        vm.stopPrank();

        vm.warp(block.timestamp + COLLECTION_PERIOD + 1);
        vm.prank(admin);
        vault.activateVault();

        vm.prank(users[0]);
        vm.expectRevert();
        vault.claimInterest();
    }

    function test_withdrawBeforeMaturity() public {
        vm.startPrank(users[0]);
        usdc.approve(address(vault), MAX_ALLOCATION);
        vault.deposit(MAX_ALLOCATION, users[0]);
        vm.stopPrank();

        vm.warp(block.timestamp + COLLECTION_PERIOD + 1);
        vm.prank(admin);
        vault.activateVault();

        uint256 shares = vault.balanceOf(users[0]);
        vm.prank(users[0]);
        vm.expectRevert();
        vault.redeem(shares, users[0], users[0]);
    }
}
