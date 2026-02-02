// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {IVaultFactory} from "../../../src/interfaces/IVaultFactory.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";

contract VaultFactoryTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Initialization Tests ============

    function test_initialize() public view {
        assertEq(vaultFactory.poolManager(), address(poolManager));
        assertEq(vaultFactory.asset(), address(usdc));
        assertEq(vaultFactory.vaultRegistry(), address(vaultRegistry));
    }

    function test_initialize_grantsAdminRole() public view {
        assertTrue(vaultFactory.hasRole(vaultFactory.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ============ createVault Tests ============

    function test_createVault_success() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        address vault = vaultFactory.createVault(params);

        assertTrue(vault != address(0));
        assertEq(vaultFactory.getVaultCount(), 1);
        assertTrue(vaultFactory.isRegisteredVault(vault));
    }

    function test_createVault_setsCorrectParams() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        address vault = vaultFactory.createVault(params);

        RWAVault rwaVault = RWAVault(vault);
        assertEq(rwaVault.name(), params.name);
        assertEq(rwaVault.symbol(), params.symbol);
        assertEq(rwaVault.termDuration(), params.termDuration);
        assertEq(rwaVault.fixedAPY(), params.fixedAPY);
        assertEq(rwaVault.minDeposit(), params.minDeposit);
        assertEq(rwaVault.maxCapacity(), params.maxCapacity);
    }

    function test_createVault_registersInPoolManager() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        address vault = vaultFactory.createVault(params);

        assertTrue(poolManager.isRegisteredVault(vault));
    }

    function test_createVault_registersInVaultRegistry() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        address vault = vaultFactory.createVault(params);

        assertTrue(vaultRegistry.isRegistered(vault));
    }

    function test_createVault_multipleVaults() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params1 = _createDefaultVaultParams();
        params1.name = "Vault 1";
        params1.symbol = "V1";
        address vault1 = vaultFactory.createVault(params1);

        IVaultFactory.VaultParams memory params2 = _createDefaultVaultParams();
        params2.name = "Vault 2";
        params2.symbol = "V2";
        params2.termDuration = 90 days;
        address vault2 = vaultFactory.createVault(params2);

        vm.stopPrank();

        assertEq(vaultFactory.getVaultCount(), 2);
        assertTrue(vault1 != vault2);

        address[] memory allVaults = vaultFactory.getAllVaults();
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], vault1);
        assertEq(allVaults[1], vault2);
    }

    function test_createVault_revertInvalidParams_emptyName() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        params.name = "";

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidVaultParams.selector);
        vaultFactory.createVault(params);
    }

    function test_createVault_revertInvalidParams_emptySymbol() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        params.symbol = "";

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidVaultParams.selector);
        vaultFactory.createVault(params);
    }

    function test_createVault_revertInvalidCollectionEndTime() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        params.collectionEndTime = block.timestamp; // Must be in future

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        vaultFactory.createVault(params);
    }

    function test_createVault_revertInvalidInterestStartTime() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        params.interestStartTime = block.timestamp; // Must be >= collectionEndTime

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        vaultFactory.createVault(params);
    }

    function test_createVault_revertInvalidAPY() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        params.fixedAPY = RWAConstants.MAX_TARGET_APY + 1;

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAPY.selector);
        vaultFactory.createVault(params);
    }

    function test_createVault_revertUnauthorized() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(user1);
        vm.expectRevert();
        vaultFactory.createVault(params);
    }

    function test_createVault_revertWhenPaused() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        vaultFactory.pause();

        vm.prank(admin);
        vm.expectRevert();
        vaultFactory.createVault(params);
    }

    function test_createVault_revertPeriodEndDatesTooLong() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        // Create array with 37 elements (exceeds MAX_PAYMENT_PERIODS = 36)
        uint256[] memory tooManyPeriods = new uint256[](37);
        uint256 interestStart = block.timestamp + 7 days;
        for (uint256 i = 0; i < 37; i++) {
            tooManyPeriods[i] = interestStart + (i + 1) * 30 days;
        }
        params.interestPeriodEndDates = tooManyPeriods;

        vm.prank(admin);
        vm.expectRevert(RWAErrors.ArrayTooLong.selector);
        vaultFactory.createVault(params);
    }

    // ============ deactivateVault Tests ============

    function test_deactivateVault_success() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        address vault = vaultFactory.createVault(params);

        // Factory updates its tracking and registry
        vaultFactory.deactivateVault(vault);

        // Vault admin must call setActive separately (Factory no longer has vault admin role)
        RWAVault(vault).setActive(false);

        vm.stopPrank();

        IVaultFactory.VaultInfo memory info = vaultFactory.getVaultInfo(vault);
        assertFalse(info.active);

        RWAVault rwaVault = RWAVault(vault);
        assertFalse(rwaVault.active());
    }

    function test_deactivateVault_revertNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultFactory.deactivateVault(makeAddr("notRegistered"));
    }

    // ============ reactivateVault Tests ============

    function test_reactivateVault_success() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        address vault = vaultFactory.createVault(params);

        // Deactivate
        vaultFactory.deactivateVault(vault);
        RWAVault(vault).setActive(false);

        // Reactivate
        vaultFactory.reactivateVault(vault);
        RWAVault(vault).setActive(true);

        vm.stopPrank();

        IVaultFactory.VaultInfo memory info = vaultFactory.getVaultInfo(vault);
        assertTrue(info.active);

        RWAVault rwaVault = RWAVault(vault);
        assertTrue(rwaVault.active());
    }

    function test_reactivateVault_revertNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultFactory.reactivateVault(makeAddr("notRegistered"));
    }

    // ============ View Function Tests ============

    function test_getAllVaults() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();
        address vault = vaultFactory.createVault(params);

        vm.stopPrank();

        address[] memory vaults = vaultFactory.getAllVaults();
        assertEq(vaults.length, 1);
        assertEq(vaults[0], vault);
    }

    function test_getActiveVaults() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params1 = _createDefaultVaultParams();
        params1.name = "Vault 1";
        params1.symbol = "V1";
        address vault1 = vaultFactory.createVault(params1);

        IVaultFactory.VaultParams memory params2 = _createDefaultVaultParams();
        params2.name = "Vault 2";
        params2.symbol = "V2";
        address vault2 = vaultFactory.createVault(params2);

        vaultFactory.deactivateVault(vault1);

        vm.stopPrank();

        address[] memory activeVaults = vaultFactory.getActiveVaults();
        assertEq(activeVaults.length, 1);
        assertEq(activeVaults[0], vault2);
    }

    function test_getVaultInfo() public {
        IVaultFactory.VaultParams memory params = _createDefaultVaultParams();

        vm.prank(admin);
        address vault = vaultFactory.createVault(params);

        IVaultFactory.VaultInfo memory info = vaultFactory.getVaultInfo(vault);

        assertEq(info.vaultAddress, vault);
        assertEq(info.name, params.name);
        assertEq(info.symbol, params.symbol);
        assertEq(info.termDuration, params.termDuration);
        assertEq(info.fixedAPY, params.fixedAPY);
        assertEq(info.tvl, 0);
        assertTrue(info.active);
        assertEq(info.createdAt, block.timestamp);
    }

    function test_getVaultInfo_revertNotRegistered() public {
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        vaultFactory.getVaultInfo(makeAddr("notRegistered"));
    }

    function test_getTotalTVL() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params1 = _createDefaultVaultParams();
        params1.name = "Vault 1";
        params1.symbol = "V1";
        address vault1 = vaultFactory.createVault(params1);

        IVaultFactory.VaultParams memory params2 = _createDefaultVaultParams();
        params2.name = "Vault 2";
        params2.symbol = "V2";
        address vault2 = vaultFactory.createVault(params2);

        vm.stopPrank();

        // Deposit to vaults
        _depositToVault(vault1, user1, 100_000e6);
        _depositToVault(vault2, user2, 200_000e6);

        assertEq(vaultFactory.getTotalTVL(), 300_000e6);
    }

    function test_getTotalTVL_excludesInactiveVaults() public {
        vm.startPrank(admin);

        IVaultFactory.VaultParams memory params1 = _createDefaultVaultParams();
        params1.name = "Vault 1";
        params1.symbol = "V1";
        address vault1 = vaultFactory.createVault(params1);

        IVaultFactory.VaultParams memory params2 = _createDefaultVaultParams();
        params2.name = "Vault 2";
        params2.symbol = "V2";
        address vault2 = vaultFactory.createVault(params2);

        vm.stopPrank();

        // Deposit to vaults
        _depositToVault(vault1, user1, 100_000e6);
        _depositToVault(vault2, user2, 200_000e6);

        // Deactivate vault1
        vm.prank(admin);
        vaultFactory.deactivateVault(vault1);

        assertEq(vaultFactory.getTotalTVL(), 200_000e6);
    }

    // ============ Pause Tests ============

    function test_pause_unpause() public {
        vm.startPrank(admin);
        vaultFactory.pause();
        assertTrue(vaultFactory.paused());

        vaultFactory.unpause();
        assertFalse(vaultFactory.paused());
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _createDefaultVaultParams() internal view returns (IVaultFactory.VaultParams memory) {
        uint256 interestStart = block.timestamp + 7 days;
        uint256 maturityTime = interestStart + 180 days;

        // Period end dates (actual end of each interest period)
        uint256[] memory periodEndDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            periodEndDates[i] = interestStart + (i + 1) * 30 days;
        }

        // Payment dates (when interest becomes claimable)
        uint256[] memory paymentDates = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            paymentDates[i] = interestStart + (i + 1) * 30 days + 3 days;
        }

        return IVaultFactory.VaultParams({
            name: "YieldCore RWA Vault",
            symbol: "ycRWA",
            collectionStartTime: 0,
            collectionEndTime: block.timestamp + 7 days,
            interestStartTime: interestStart,
            termDuration: 180 days,
            fixedAPY: 1500,
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: maturityTime
        });
    }
}
