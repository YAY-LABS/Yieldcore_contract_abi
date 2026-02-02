// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../../src/interfaces/IRWAVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RWAVault Recovery Tests
/// @notice Tests for asset recovery functions (recoverAssetDust, recoverETH)
contract RWAVaultRecoveryTest is BaseTest {
    RWAVault public vault;
    address public recipient;

    // Helper contract to force-send ETH
    ForceETHSender public ethSender;

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());
        recipient = makeAddr("recipient");
        ethSender = new ForceETHSender();
    }

    // ============ recoverAssetDust Tests ============

    function test_RecoverAssetDust_Success() public {
        // Setup: User deposits, withdraws, leaving dust
        _depositToVault(address(vault), user1, 10000e6);

        // Warp to collection end and activate
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Deposit interest to cover payments
        _depositInterest(address(vault), 5000e6);

        // Warp to maturity
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();

        // User redeems all shares
        vm.startPrank(user1);
        uint256 userShares = vault.balanceOf(user1);
        vault.redeem(userShares, user1, user1);
        vm.stopPrank();

        // Manually send some dust to vault (simulating rounding leftovers)
        usdc.mint(address(vault), 100); // 0.0001 USDC dust

        // Verify vault has dust and no shares
        assertEq(vault.totalSupply(), 0, "Should have no shares");
        assertGt(usdc.balanceOf(address(vault)), 0, "Should have dust");

        uint256 dustAmount = usdc.balanceOf(address(vault));
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        // Recover dust via PoolManager
        vm.prank(admin);
        poolManager.recoverAssetDust(address(vault), recipient);

        // Verify
        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should be empty");
        assertEq(
            usdc.balanceOf(recipient),
            recipientBalanceBefore + dustAmount,
            "Recipient should receive dust"
        );
    }

    function test_RecoverAssetDust_RevertWhenSharesExist() public {
        // User deposits
        _depositToVault(address(vault), user1, 10000e6);

        // Try to recover dust while shares exist
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidPhase.selector);
        poolManager.recoverAssetDust(address(vault), recipient);
    }

    function test_RecoverAssetDust_RevertWhenNoDust() public {
        // Create scenario with no shares and no dust
        // Deploy fresh vault, don't deposit anything, just verify it fails

        // Warp to collection end (no deposits)
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        // Warp to maturity
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();

        // totalSupply should be 0
        assertEq(vault.totalSupply(), 0, "Should have no shares");
        assertEq(usdc.balanceOf(address(vault)), 0, "Should have no USDC");

        // Try to recover when no dust
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.recoverAssetDust(address(vault), recipient);
    }

    function test_RecoverAssetDust_RevertWhenZeroRecipient() public {
        // Setup empty vault with dust
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();

        // Add some dust
        usdc.mint(address(vault), 100);

        // Try to recover to zero address
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        poolManager.recoverAssetDust(address(vault), address(0));
    }

    function test_RecoverAssetDust_RevertWhenNotAdmin() public {
        // Setup empty vault with dust
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();
        usdc.mint(address(vault), 100);

        // Try from non-admin
        vm.prank(user1);
        vm.expectRevert();
        poolManager.recoverAssetDust(address(vault), recipient);
    }

    // ============ recoverETH Tests ============

    function test_RecoverETH_Success() public {
        // Force send ETH to vault using selfdestruct
        uint256 ethAmount = 1 ether;
        vm.deal(address(ethSender), ethAmount);
        ethSender.forceETH(address(vault));

        // Verify vault has ETH
        assertEq(address(vault).balance, ethAmount, "Vault should have ETH");

        uint256 recipientBalanceBefore = recipient.balance;

        // Recover ETH via PoolManager
        vm.prank(admin);
        poolManager.recoverETH(address(vault), payable(recipient));

        // Verify
        assertEq(address(vault).balance, 0, "Vault should have no ETH");
        assertEq(
            recipient.balance,
            recipientBalanceBefore + ethAmount,
            "Recipient should receive ETH"
        );
    }

    function test_RecoverETH_RevertWhenNoETH() public {
        // Verify vault has no ETH
        assertEq(address(vault).balance, 0, "Vault should have no ETH");

        // Try to recover when no ETH
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.recoverETH(address(vault), payable(recipient));
    }

    function test_RecoverETH_RevertWhenZeroRecipient() public {
        // Force send ETH to vault
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        // Try to recover to zero address
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        poolManager.recoverETH(address(vault), payable(address(0)));
    }

    function test_RecoverETH_RevertWhenNotAdmin() public {
        // Force send ETH to vault
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        // Try from non-admin
        vm.prank(user1);
        vm.expectRevert();
        poolManager.recoverETH(address(vault), payable(recipient));
    }

    function test_RecoverETH_WorksAtAnyPhase() public {
        // Force send ETH
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        // Test during Collecting phase
        assertEq(uint256(vault.currentPhase()), uint256(IRWAVault.Phase.Collecting));

        vm.prank(admin);
        poolManager.recoverETH(address(vault), payable(recipient));
        assertEq(address(vault).balance, 0);

        // Send more ETH and test during Active phase
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();

        vm.prank(admin);
        poolManager.recoverETH(address(vault), payable(recipient));
        assertEq(address(vault).balance, 0);

        // Send more ETH and test during Matured phase
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();

        vm.prank(admin);
        poolManager.recoverETH(address(vault), payable(recipient));
        assertEq(address(vault).balance, 0);
    }

    // ============ recoverERC20 Tests (existing functionality) ============

    function test_RecoverERC20_Success() public {
        // Deploy a random ERC20 token
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(vault), 1000e18);

        uint256 recipientBalanceBefore = randomToken.balanceOf(recipient);

        // Recover via PoolManager
        vm.prank(admin);
        poolManager.recoverERC20(address(vault), address(randomToken), 1000e18, recipient);

        assertEq(randomToken.balanceOf(address(vault)), 0);
        assertEq(randomToken.balanceOf(recipient), recipientBalanceBefore + 1000e18);
    }

    function test_RecoverERC20_RevertWhenRecoveringAsset() public {
        // Try to recover USDC (the asset) via recoverERC20
        usdc.mint(address(vault), 1000e6);

        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        poolManager.recoverERC20(address(vault), address(usdc), 1000e6, recipient);
    }

    // ============ Direct Call Tests (should fail, must go through PoolManager) ============

    function test_RecoverAssetDust_RevertWhenCalledDirectly() public {
        // Setup empty vault with dust
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vault.activateVault();
        vm.warp(vault.maturityTime() + 1);
        vm.prank(admin);
        vault.matureVault();
        usdc.mint(address(vault), 100);

        // Try to call directly (not through PoolManager)
        vm.prank(admin);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        vault.recoverAssetDust(recipient);
    }

    function test_RecoverETH_RevertWhenCalledDirectly() public {
        // Force send ETH
        vm.deal(address(ethSender), 1 ether);
        ethSender.forceETH(address(vault));

        // Try to call directly (not through PoolManager)
        vm.prank(admin);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        vault.recoverETH(payable(recipient));
    }
}

/// @notice Helper contract to force-send ETH via selfdestruct
contract ForceETHSender {
    function forceETH(address target) external {
        selfdestruct(payable(target));
    }

    receive() external payable {}
}
