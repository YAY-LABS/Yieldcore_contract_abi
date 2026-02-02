// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BaseTest} from "../unit/BaseTest.sol";
import {RWAVault} from "../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../src/interfaces/IRWAVault.sol";
import {MockERC20} from "../unit/mocks/MockERC20.sol";

/// @title VaultHandler
/// @notice Handler contract for invariant testing - wraps vault operations
contract VaultHandler is Test {
    RWAVault public vault;
    MockERC20 public usdc;

    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalTransferred;

    mapping(address => uint256) public ghost_userDeposits;

    constructor(RWAVault _vault, MockERC20 _usdc, address[] memory _actors) {
        vault = _vault;
        usdc = _usdc;
        actors = _actors;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Handler: Deposit random amount
    function deposit(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        // Only in Collecting phase
        if (vault.currentPhase() != IRWAVault.Phase.Collecting) return;

        // Bound amount
        uint256 minDeposit = vault.minDeposit();
        uint256 maxDeposit = vault.maxDeposit(currentActor);
        if (maxDeposit < minDeposit) return;

        amount = bound(amount, minDeposit, maxDeposit);

        // Mint and approve
        usdc.mint(currentActor, amount);
        usdc.approve(address(vault), amount);

        // Deposit
        vault.deposit(amount, currentActor);

        // Track
        ghost_totalDeposited += amount;
        ghost_userDeposits[currentActor] += amount;
    }

    /// @notice Handler: Transfer shares
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public useActor(fromSeed) {
        address to = actors[bound(toSeed, 0, actors.length - 1)];
        if (to == currentActor) return;

        uint256 balance = vault.balanceOf(currentActor);
        if (balance == 0) return;

        // Respect MIN_SHARE_TRANSFER
        uint256 minTransfer = 1e6; // MIN_SHARE_TRANSFER from RWAConstants
        if (balance < minTransfer) return;

        amount = bound(amount, minTransfer, balance);

        // Check remaining wouldn't be dust
        uint256 remaining = balance - amount;
        if (remaining > 0 && remaining < minTransfer) {
            amount = balance; // Transfer all
        }

        vault.transfer(to, amount);
        ghost_totalTransferred += amount;
    }

    /// @notice Get all actors
    function getActors() external view returns (address[] memory) {
        return actors;
    }
}

/// @title RWAVaultInvariantTest
/// @notice Invariant tests for RWAVault
contract RWAVaultInvariantTest is BaseTest {
    RWAVault public vault;
    VaultHandler public handler;

    address[] public actors;

    function setUp() public override {
        super.setUp();
        vault = RWAVault(_createDefaultVault());

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }

        // Create handler
        handler = new VaultHandler(vault, usdc, actors);

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Exclude other contracts
        excludeContract(address(vault));
        excludeContract(address(usdc));
        excludeContract(address(poolManager));
        excludeContract(address(vaultFactory));
        excludeContract(address(vaultRegistry));
        excludeContract(address(loanRegistry));
    }

    // ============ Invariants ============

    /// @notice Invariant: totalSupply equals sum of all balances
    function invariant_totalSupplyEqualsBalanceSum() public view {
        uint256 sum = 0;
        address[] memory allActors = handler.getActors();

        for (uint256 i = 0; i < allActors.length; i++) {
            sum += vault.balanceOf(allActors[i]);
        }

        // totalSupply should equal sum of tracked actor balances
        // Note: There might be other holders we don't track
        assertLe(sum, vault.totalSupply(), "Sum exceeds totalSupply");
    }

    /// @notice Invariant: totalPrincipal equals sum of user principals
    function invariant_totalPrincipalConsistency() public view {
        uint256 sum = 0;
        address[] memory allActors = handler.getActors();

        for (uint256 i = 0; i < allActors.length; i++) {
            (, uint256 principal,,) = vault.getDepositInfo(allActors[i]);
            sum += principal;
        }

        // Sum of tracked principals should not exceed total
        assertLe(sum, vault.totalPrincipal(), "Principal sum exceeds total");
    }

    /// @notice Invariant: share balance matches depositInfo shares
    function invariant_sharesMatchDepositInfo() public view {
        address[] memory allActors = handler.getActors();

        for (uint256 i = 0; i < allActors.length; i++) {
            address actor = allActors[i];
            (uint256 infoShares,,,) = vault.getDepositInfo(actor);
            uint256 balance = vault.balanceOf(actor);

            assertEq(infoShares, balance, "Shares mismatch for actor");
        }
    }

    /// @notice Invariant: vault USDC balance >= availableLiquidity
    function invariant_liquidityConsistency() public view {
        uint256 vaultBalance = usdc.balanceOf(address(vault));
        uint256 available = vault.availableLiquidity();

        assertGe(vaultBalance, available, "Available exceeds balance");
    }

    /// @notice Invariant: totalAssets >= totalPrincipal (no negative interest)
    function invariant_noNegativeInterest() public view {
        // Only check if there are deposits
        if (vault.totalPrincipal() == 0) return;

        assertGe(vault.totalAssets(), vault.totalPrincipal(), "Negative interest detected");
    }

    /// @notice Invariant: totalSupply should equal totalPrincipal in Collecting phase
    function invariant_collectingPhaseShareRatio() public view {
        if (vault.currentPhase() != IRWAVault.Phase.Collecting) return;

        // In collecting phase, 1 share = 1 asset
        assertEq(vault.totalSupply(), vault.totalPrincipal(), "Share ratio broken in Collecting");
    }

    /// @notice Invariant: ghost tracking matches actual deposits
    function invariant_ghostTrackingAccuracy() public view {
        // Ghost total deposited should match totalPrincipal
        // (assuming no withdrawals in Collecting phase)
        if (vault.currentPhase() == IRWAVault.Phase.Collecting) {
            assertEq(
                handler.ghost_totalDeposited(),
                vault.totalPrincipal(),
                "Ghost tracking mismatch"
            );
        }
    }

    // ============ Helper to view state after invariant run ============

    function invariant_callSummary() public view {
        console2.log("Total Deposited:", handler.ghost_totalDeposited());
        console2.log("Total Transferred:", handler.ghost_totalTransferred());
        console2.log("Vault totalSupply:", vault.totalSupply());
        console2.log("Vault totalPrincipal:", vault.totalPrincipal());
    }
}
