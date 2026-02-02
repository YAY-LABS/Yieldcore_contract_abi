// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {IVaultRegistry} from "../../../src/interfaces/IVaultRegistry.sol";
import {IVaultFactory} from "../../../src/interfaces/IVaultFactory.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";

contract VaultRegistryTest is BaseTest {
    address public testVault;

    function setUp() public override {
        super.setUp();
    }

    // ============ Initialization Tests ============

    function test_initialize() public view {
        assertEq(vaultRegistry.getVaultCount(), 0);
    }

    function test_initialize_grantsAdminRole() public view {
        assertTrue(vaultRegistry.hasRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ============ addVault Tests ============

    function test_addVault_success() public {
        address vault = makeAddr("vault");

        vm.prank(admin);
        vaultRegistry.addVault(
            vault,
            "Test Vault",
            "TV",
            180 days,
            1500
        );

        assertEq(vaultRegistry.getVaultCount(), 1);
        assertTrue(vaultRegistry.isRegistered(vault));
    }

    function test_addVault_setsCorrectMetadata() public {
        address vault = makeAddr("vault");
        string memory name = "Test Vault";
        string memory symbol = "TV";
        uint256 termDuration = 180 days;
        uint256 fixedAPY = 1500;

        vm.prank(admin);
        vaultRegistry.addVault(vault, name, symbol, termDuration, fixedAPY);

        IVaultRegistry.VaultMetadata memory metadata = vaultRegistry.getVault(vault);

        assertEq(metadata.vault, vault);
        assertEq(metadata.name, name);
        assertEq(metadata.symbol, symbol);
        assertEq(metadata.termDuration, termDuration);
        assertEq(metadata.fixedAPY, fixedAPY);
        assertEq(metadata.createdAt, block.timestamp);
        assertTrue(metadata.active);
    }

    function test_addVault_revertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        vaultRegistry.addVault(address(0), "Test", "T", 180 days, 1500);
    }

    function test_addVault_revertAlreadyRegistered() public {
        address vault = makeAddr("vault");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault, "Test", "T", 180 days, 1500);

        vm.expectRevert(RWAErrors.VaultAlreadyRegistered.selector);
        vaultRegistry.addVault(vault, "Test2", "T2", 180 days, 1500);
        vm.stopPrank();
    }

    function test_addVault_revertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vaultRegistry.addVault(makeAddr("vault"), "Test", "T", 180 days, 1500);
    }

    // ============ removeVault Tests ============

    function test_removeVault_success() public {
        address vault = makeAddr("vault");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault, "Test", "T", 180 days, 1500);

        assertTrue(vaultRegistry.isRegistered(vault));

        vaultRegistry.removeVault(vault);

        assertFalse(vaultRegistry.isRegistered(vault));
        vm.stopPrank();
    }

    function test_removeVault_revertNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultRegistry.removeVault(makeAddr("nonexistent"));
    }

    // ============ setVaultStatus Tests ============

    function test_setVaultStatus_deactivate() public {
        address vault = makeAddr("vault");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault, "Test", "T", 180 days, 1500);

        vaultRegistry.setVaultStatus(vault, false);

        IVaultRegistry.VaultMetadata memory metadata = vaultRegistry.getVault(vault);
        assertFalse(metadata.active);
        vm.stopPrank();
    }

    function test_setVaultStatus_reactivate() public {
        address vault = makeAddr("vault");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault, "Test", "T", 180 days, 1500);
        vaultRegistry.setVaultStatus(vault, false);
        vaultRegistry.setVaultStatus(vault, true);

        IVaultRegistry.VaultMetadata memory metadata = vaultRegistry.getVault(vault);
        assertTrue(metadata.active);
        vm.stopPrank();
    }

    function test_setVaultStatus_revertNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultRegistry.setVaultStatus(makeAddr("nonexistent"), false);
    }

    // ============ View Function Tests ============

    function test_getVault_revertNotRegistered() public {
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultRegistry.getVault(makeAddr("nonexistent"));
    }

    function test_getAllVaults() public {
        address vault1 = makeAddr("vault1");
        address vault2 = makeAddr("vault2");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault1, "V1", "V1", 180 days, 1500);
        vaultRegistry.addVault(vault2, "V2", "V2", 90 days, 1000);
        vm.stopPrank();

        address[] memory vaults = vaultRegistry.getAllVaults();
        assertEq(vaults.length, 2);
        assertEq(vaults[0], vault1);
        assertEq(vaults[1], vault2);
    }

    function test_getActiveVaults() public {
        address vault1 = makeAddr("vault1");
        address vault2 = makeAddr("vault2");
        address vault3 = makeAddr("vault3");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault1, "V1", "V1", 180 days, 1500);
        vaultRegistry.addVault(vault2, "V2", "V2", 90 days, 1000);
        vaultRegistry.addVault(vault3, "V3", "V3", 30 days, 500);

        // Deactivate vault2
        vaultRegistry.setVaultStatus(vault2, false);
        vm.stopPrank();

        address[] memory activeVaults = vaultRegistry.getActiveVaults();
        assertEq(activeVaults.length, 2);
        assertEq(activeVaults[0], vault1);
        assertEq(activeVaults[1], vault3);
    }

    function test_getVaultsByTerm() public {
        address vault1 = makeAddr("vault1");
        address vault2 = makeAddr("vault2");
        address vault3 = makeAddr("vault3");

        vm.startPrank(admin);
        vaultRegistry.addVault(vault1, "V1", "V1", 180 days, 1500);
        vaultRegistry.addVault(vault2, "V2", "V2", 180 days, 1000);
        vaultRegistry.addVault(vault3, "V3", "V3", 90 days, 500);
        vm.stopPrank();

        address[] memory vaults180 = vaultRegistry.getVaultsByTerm(180 days);
        address[] memory vaults90 = vaultRegistry.getVaultsByTerm(90 days);

        assertEq(vaults180.length, 2);
        assertEq(vaults90.length, 1);
        assertEq(vaults180[0], vault1);
        assertEq(vaults180[1], vault2);
        assertEq(vaults90[0], vault3);
    }

    function test_isRegistered() public {
        address vault = makeAddr("vault");

        assertFalse(vaultRegistry.isRegistered(vault));

        vm.prank(admin);
        vaultRegistry.addVault(vault, "Test", "T", 180 days, 1500);

        assertTrue(vaultRegistry.isRegistered(vault));
    }

    function test_getTotalTVL() public {
        // Create vaults through factory (they will be ERC4626)
        testVault = _createDefaultVault();

        // Deposit to vault
        _depositToVault(testVault, user1, 100_000e6);

        uint256 tvl = vaultRegistry.getTotalTVL();
        assertEq(tvl, 100_000e6);
    }

    function test_getTotalTVL_multipleVaults() public {
        // Create first vault
        vm.startPrank(admin);

        uint256 interestStart1 = block.timestamp + 7 days;
        uint256 maturityTime1 = interestStart1 + 180 days;
        uint256[] memory periodEndDates1 = new uint256[](6);
        uint256[] memory paymentDates1 = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates1[i] = interestStart1 + (i + 1) * 30 days;
            paymentDates1[i] = interestStart1 + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params1 = IVaultFactory.VaultParams({
            name: "Vault 1",
            symbol: "V1",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart1,
            termDuration: 180 days,
            fixedAPY: 1500,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates1,
            interestPaymentDates: paymentDates1,
            withdrawalStartTime: maturityTime1
        });
        address vault1 = vaultFactory.createVault(params1);

        uint256 interestStart2 = block.timestamp + 7 days;
        uint256 maturityTime2 = interestStart2 + 90 days;
        uint256[] memory periodEndDates2 = new uint256[](3);
        uint256[] memory paymentDates2 = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            periodEndDates2[i] = interestStart2 + (i + 1) * 30 days;
            paymentDates2[i] = interestStart2 + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params2 = IVaultFactory.VaultParams({
            name: "Vault 2",
            symbol: "V2",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart2,
            termDuration: 90 days,
            fixedAPY: 1000,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates2,
            interestPaymentDates: paymentDates2,
            withdrawalStartTime: maturityTime2
        });
        address vault2 = vaultFactory.createVault(params2);

        vm.stopPrank();

        // Deposit to vaults
        _depositToVault(vault1, user1, 100_000e6);
        _depositToVault(vault2, user2, 200_000e6);

        uint256 tvl = vaultRegistry.getTotalTVL();
        assertEq(tvl, 300_000e6);
    }

    function test_getTotalTVL_excludesInactiveVaults() public {
        // Create vaults
        vm.startPrank(admin);

        uint256 interestStart1 = block.timestamp + 7 days;
        uint256 maturityTime1 = interestStart1 + 180 days;
        uint256[] memory periodEndDates1 = new uint256[](6);
        uint256[] memory paymentDates1 = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates1[i] = interestStart1 + (i + 1) * 30 days;
            paymentDates1[i] = interestStart1 + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params1 = IVaultFactory.VaultParams({
            name: "Vault 1",
            symbol: "V1",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart1,
            termDuration: 180 days,
            fixedAPY: 1500,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates1,
            interestPaymentDates: paymentDates1,
            withdrawalStartTime: maturityTime1
        });
        address vault1 = vaultFactory.createVault(params1);

        uint256 interestStart2 = block.timestamp + 7 days;
        uint256 maturityTime2 = interestStart2 + 90 days;
        uint256[] memory periodEndDates2 = new uint256[](3);
        uint256[] memory paymentDates2 = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            periodEndDates2[i] = interestStart2 + (i + 1) * 30 days;
            paymentDates2[i] = interestStart2 + (i + 1) * 30 days + 3 days;
        }

        IVaultFactory.VaultParams memory params2 = IVaultFactory.VaultParams({
            name: "Vault 2",
            symbol: "V2",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart2,
            termDuration: 90 days,
            fixedAPY: 1000,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates2,
            interestPaymentDates: paymentDates2,
            withdrawalStartTime: maturityTime2
        });
        address vault2 = vaultFactory.createVault(params2);

        vm.stopPrank();

        // Deposit to vaults
        _depositToVault(vault1, user1, 100_000e6);
        _depositToVault(vault2, user2, 200_000e6);

        // Deactivate vault2
        vm.prank(admin);
        vaultFactory.deactivateVault(vault2);

        uint256 tvl = vaultRegistry.getTotalTVL();
        assertEq(tvl, 100_000e6);
    }

    // ============ Pause Tests ============

    function test_pause_unpause() public {
        vm.startPrank(admin);
        vaultRegistry.pause();
        assertTrue(vaultRegistry.paused());

        vaultRegistry.unpause();
        assertFalse(vaultRegistry.paused());
        vm.stopPrank();
    }
}
