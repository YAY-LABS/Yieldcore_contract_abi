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
import {IVaultFactory} from "../../src/interfaces/IVaultFactory.sol";

contract GasTest36Month is Test {
    MockERC20 public usdc;
    LoanRegistry public loanRegistry;
    VaultRegistry public vaultRegistry;
    PoolManager public poolManager;
    VaultFactory public vaultFactory;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);

        vm.startPrank(admin);

        loanRegistry = new LoanRegistry(admin);
        vaultRegistry = new VaultRegistry(admin);
        poolManager = new PoolManager(
            admin,
            address(usdc),
            address(loanRegistry),
            treasury,
            500 // 5% fee
        );
        vaultFactory = new VaultFactory(
            admin,
            address(poolManager),
            address(usdc),
            address(vaultRegistry)
        );

        // Grant roles
        vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(vaultFactory));
        poolManager.grantRole(poolManager.DEFAULT_ADMIN_ROLE(), address(vaultFactory));

        vm.stopPrank();
    }

    function test_Create36MonthVault_GasUsage() public {
        uint256 startTime = block.timestamp;
        uint256 collectionEnd = startTime + 7 days;
        uint256 interestStart = collectionEnd + 1 days;

        // Create 36 months of dates
        uint256[] memory periodEndDates = new uint256[](36);
        uint256[] memory paymentDates = new uint256[](36);

        for (uint256 i = 0; i < 36; i++) {
            periodEndDates[i] = interestStart + (30 days * (i + 1));
            paymentDates[i] = interestStart + (30 days * (i + 1)) + 3 days;
        }

        uint256 maturityTime = periodEndDates[35]; // Last period end
        uint256 withdrawalStart = maturityTime + 1 days;

        IVaultFactory.VaultParams memory params = IVaultFactory.VaultParams({
            name: "36 Month Vault",
            symbol: "V36M",
            collectionStartTime: startTime,
            collectionEndTime: collectionEnd,
            interestStartTime: interestStart,
            termDuration: 36 * 30 days,
            fixedAPY: 1000, // 10%
            minDeposit: 100e6,
            maxCapacity: 10_000_000e6,
            interestPeriodEndDates: periodEndDates,
            interestPaymentDates: paymentDates,
            withdrawalStartTime: withdrawalStart
        });

        vm.prank(admin);
        uint256 gasBefore = gasleft();
        address vault = vaultFactory.createVault(params);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("=== 36 Month Vault Gas Report ===");
        console2.log("Gas used for createVault:", gasUsed);
        console2.log("Vault address:", vault);
        console2.log("Period end dates count:", RWAVault(vault).getInterestPeriodEndDates().length);
        console2.log("Payment dates count:", RWAVault(vault).getInterestPaymentDates().length);
        console2.log("Maturity time:", RWAVault(vault).maturityTime());

        // Verify
        assertEq(RWAVault(vault).getInterestPeriodEndDates().length, 36);
        assertEq(RWAVault(vault).getInterestPaymentDates().length, 36);

        // Gas should be reasonable (under 5M for standard block limit of 30M)
        assertLt(gasUsed, 5_000_000, "Gas usage too high");
    }
}
