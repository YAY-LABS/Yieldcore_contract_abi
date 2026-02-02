// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.sol";
import {RWAVault} from "../../../src/vault/RWAVault.sol";
import {IRWAVault} from "../../../src/interfaces/IRWAVault.sol";
import {IPoolManager} from "../../../src/interfaces/IPoolManager.sol";
import {ILoanRegistry} from "../../../src/interfaces/ILoanRegistry.sol";
import {RWAConstants} from "../../../src/libraries/RWAConstants.sol";
import {RWAErrors} from "../../../src/libraries/RWAErrors.sol";

contract PoolManagerTest is BaseTest {
    address public testVault;

    function setUp() public override {
        super.setUp();
        testVault = _createDefaultVault();

        // Deposit to vault for liquidity
        _depositToVault(testVault, user1, 500_000e6);

        // Warp past collection end time
        vm.warp(block.timestamp + 8 days);
    }

    // ============ Initialization Tests ============

    function test_initialize() public view {
        assertEq(address(poolManager.asset()), address(usdc));
        assertEq(address(poolManager.loanRegistry()), address(loanRegistry));
        assertEq(poolManager.treasury(), treasury);
        assertEq(poolManager.protocolFee(), PROTOCOL_FEE);
    }

    function test_initialize_grantsRoles() public view {
        assertTrue(poolManager.hasRole(poolManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(poolManager.hasRole(RWAConstants.CURATOR_ROLE, admin));
        assertTrue(poolManager.hasRole(RWAConstants.CURATOR_ROLE, curator));
        assertTrue(poolManager.hasRole(RWAConstants.OPERATOR_ROLE, admin));
        assertTrue(poolManager.hasRole(RWAConstants.OPERATOR_ROLE, operator));
    }

    // ============ Capital Deployment Tests ============

    function test_announceDeployCapital_success() public {
        uint256 amount = 100_000e6;

        vm.prank(curator);
        poolManager.announceDeployCapital(testVault, amount, borrower);

        // Check pending deployment on vault
        (uint256 pendingAmount, address pendingRecipient, , bool active) = RWAVault(testVault).getPendingDeployment();
        assertEq(pendingAmount, amount);
        assertEq(pendingRecipient, borrower);
        assertTrue(active);
    }

    function test_executeDeployCapital_success() public {
        uint256 amount = 100_000e6;
        uint256 borrowerBalanceBefore = usdc.balanceOf(borrower);

        // Announce deployment
        vm.prank(curator);
        poolManager.announceDeployCapital(testVault, amount, borrower);

        // Warp past timelock
        uint256 delay = RWAVault(testVault).deploymentDelay();
        vm.warp(block.timestamp + delay + 1);

        // Execute deployment
        vm.prank(curator);
        poolManager.executeDeployCapital(testVault);

        // Verify capital deployed
        assertEq(usdc.balanceOf(borrower) - borrowerBalanceBefore, amount);
        assertEq(RWAVault(testVault).totalDeployed(), amount);
    }

    function test_cancelDeployCapital_success() public {
        uint256 amount = 100_000e6;

        vm.prank(curator);
        poolManager.announceDeployCapital(testVault, amount, borrower);

        vm.prank(curator);
        poolManager.cancelDeployCapital(testVault);

        // Check pending deployment cleared
        (, , , bool active) = RWAVault(testVault).getPendingDeployment();
        assertFalse(active);
    }

    function test_announceDeployCapital_revertUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        poolManager.announceDeployCapital(testVault, 100_000e6, borrower);
    }

    function test_announceDeployCapital_revertVaultNotRegistered() public {
        address fakeVault = makeAddr("fakeVault");

        vm.prank(curator);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        poolManager.announceDeployCapital(fakeVault, 100_000e6, borrower);
    }

    // ============ Capital Management Tests ============

    function test_returnCapital_success() public {
        // First deploy capital
        _deployCapital(testVault, 100_000e6, borrower);

        // Return capital
        uint256 returnAmount = 50_000e6;
        vm.startPrank(operator);
        usdc.approve(address(poolManager), returnAmount);
        poolManager.returnCapital(testVault, returnAmount);
        vm.stopPrank();

        assertEq(RWAVault(testVault).totalDeployed(), 50_000e6);
    }

    function test_depositInterest_success() public {
        uint256 interestAmount = 10_000e6;

        vm.startPrank(operator);
        usdc.approve(address(poolManager), interestAmount);
        poolManager.depositInterest(testVault, interestAmount);
        vm.stopPrank();

        // Interest deposited to vault
        assertGe(usdc.balanceOf(testVault), interestAmount);
    }

    function test_triggerDefault_success() public {
        // Activate vault first
        vm.prank(admin);
        RWAVault(testVault).activateVault();

        vm.prank(curator);
        poolManager.triggerDefault(testVault);

        assertEq(uint8(RWAVault(testVault).currentPhase()), uint8(IRWAVault.Phase.Defaulted));
    }

    function test_recoverERC20_success() public {
        // Send some other token to vault
        MockERC20 otherToken = new MockERC20("Other", "OTHER", 18);
        otherToken.mint(testVault, 1000e18);

        uint256 treasuryBalanceBefore = otherToken.balanceOf(treasury);

        vm.prank(admin);
        poolManager.recoverERC20(testVault, address(otherToken), 1000e18, treasury);

        assertEq(otherToken.balanceOf(treasury) - treasuryBalanceBefore, 1000e18);
    }

    // ============ registerLoan Tests ============

    function test_registerLoan_success() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();

        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        assertEq(loanId, 1);

        // Check loan registry
        ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
        assertEq(loan.principal, params.principal);
        assertEq(loan.interestRate, params.interestRate);
        assertEq(loan.term, params.term);
        assertEq(loan.collateralValue, params.collateralValue);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Active));

        // Note: registerLoan does NOT deploy capital - that's separate
    }

    function test_registerLoan_revertUnauthorized() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();

        vm.prank(user1);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertZeroAmount() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.principal = 0;

        vm.prank(curator);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertInvalidLoanTerm_tooShort() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.term = 29 days;

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidLoanTerm.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertInvalidLoanTerm_tooLong() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.term = 366 days;

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidLoanTerm.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertInvalidInterestRate_tooLow() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.interestRate = 99; // < 1%

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidInterestRate.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertInvalidInterestRate_tooHigh() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.interestRate = 5001; // > 50%

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidInterestRate.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertInvalidCollateralValue() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.collateralValue = 0;

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidCollateralValue.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertExceedsMaxLTV() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        // LTV = 100k / 100k = 100% > 80%
        params.collateralValue = 100_000e6;

        vm.prank(curator);
        vm.expectRevert(RWAErrors.InvalidCollateralValue.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertVaultNotRegistered() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        params.vault = makeAddr("unregistered");

        vm.prank(curator);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        poolManager.registerLoan(params);
    }

    function test_registerLoan_revertWhenPaused() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();

        vm.prank(admin);
        poolManager.pause();

        vm.prank(curator);
        vm.expectRevert();
        poolManager.registerLoan(params);
    }

    // ============ recordRepayment Tests ============

    function test_recordRepayment_success() public {
        // Register loan and deploy capital
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        _deployCapital(testVault, params.principal, address(poolManager));

        // Warp some time
        vm.warp(block.timestamp + 30 days);

        // Record repayment
        uint256 principalAmount = 50_000e6;
        uint256 interestAmount = 5_000e6;
        uint256 totalPayment = principalAmount + interestAmount;

        vm.startPrank(operator);
        usdc.approve(address(poolManager), totalPayment);
        poolManager.recordRepayment(loanId, principalAmount, interestAmount);
        vm.stopPrank();

        // Check loan updated
        ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
        assertEq(loan.totalRepaid, principalAmount);
        assertEq(loan.totalInterestPaid, interestAmount);

        // Protocol fee is disabled - no fees collected
        assertEq(poolManager.accumulatedFees(), 0);
    }

    function test_recordRepayment_fullRepayment() public {
        // Register loan and deploy capital
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        _deployCapital(testVault, params.principal, address(poolManager));

        // Warp some time
        vm.warp(block.timestamp + 180 days);

        // Full repayment
        uint256 principalAmount = params.principal;
        uint256 interestAmount = 20_000e6;
        uint256 totalPayment = principalAmount + interestAmount;

        vm.startPrank(operator);
        usdc.approve(address(poolManager), totalPayment);
        poolManager.recordRepayment(loanId, principalAmount, interestAmount);
        vm.stopPrank();

        // Check loan status
        ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILoanRegistry.LoanStatus.Repaid));
    }

    function test_recordRepayment_revertUnauthorized() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        vm.prank(user1);
        vm.expectRevert(RWAErrors.Unauthorized.selector);
        poolManager.recordRepayment(loanId, 10_000e6, 1_000e6);
    }

    function test_recordRepayment_revertZeroAmount() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        vm.prank(operator);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.recordRepayment(loanId, 0, 0);
    }

    function test_recordRepayment_revertLoanNotActive() public {
        IPoolManager.LoanParams memory params = _createTestLoanParams();

        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        _deployCapital(testVault, params.principal, address(poolManager));

        // Fully repay the loan
        vm.startPrank(operator);
        usdc.approve(address(poolManager), params.principal + 10_000e6);
        poolManager.recordRepayment(loanId, params.principal, 10_000e6);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(RWAErrors.LoanNotActive.selector);
        poolManager.recordRepayment(loanId, 10_000e6, 1_000e6);
    }

    // ============ Vault Management Tests ============

    function test_registerVault_success() public {
        address newVault = makeAddr("newVault");

        vm.prank(admin);
        poolManager.registerVault(newVault);

        assertTrue(poolManager.isRegisteredVault(newVault));
    }

    function test_registerVault_revertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        poolManager.registerVault(address(0));
    }

    function test_registerVault_revertAlreadyRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultAlreadyRegistered.selector);
        poolManager.registerVault(testVault);
    }

    function test_unregisterVault_success() public {
        vm.prank(admin);
        poolManager.unregisterVault(testVault);

        assertFalse(poolManager.isRegisteredVault(testVault));
    }

    function test_unregisterVault_revertNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.VaultNotRegistered.selector);
        poolManager.unregisterVault(makeAddr("notRegistered"));
    }

    // ============ Fee Management Tests ============
    // Note: Protocol fee is currently disabled in recordRepayment()
    // These tests verify the fee infrastructure still works for future use

    function test_noFeesCollected_afterRepayment() public {
        // Register loan and deploy capital
        IPoolManager.LoanParams memory params = _createTestLoanParams();
        vm.prank(curator);
        uint256 loanId = poolManager.registerLoan(params);

        _deployCapital(testVault, params.principal, address(poolManager));

        uint256 interestAmount = 10_000e6;
        vm.startPrank(operator);
        usdc.approve(address(poolManager), params.principal + interestAmount);
        poolManager.recordRepayment(loanId, params.principal, interestAmount);
        vm.stopPrank();

        // Protocol fee is disabled - no fees collected
        assertEq(poolManager.accumulatedFees(), 0);

        // withdrawFees should revert with zero amount
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAmount.selector);
        poolManager.withdrawFees();
    }

    function test_setProtocolFee_success() public {
        uint256 newFee = 800;

        vm.prank(admin);
        poolManager.setProtocolFee(newFee);

        assertEq(poolManager.protocolFee(), newFee);
    }

    function test_setProtocolFee_revertExceedsMax() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.InvalidAmount.selector);
        poolManager.setProtocolFee(RWAConstants.MAX_PROTOCOL_FEE + 1);
    }

    function test_setTreasury_success() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        poolManager.setTreasury(newTreasury);

        assertEq(poolManager.treasury(), newTreasury);
    }

    function test_setTreasury_revertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(RWAErrors.ZeroAddress.selector);
        poolManager.setTreasury(address(0));
    }

    // ============ Pause Tests ============

    function test_pause_unpause() public {
        vm.startPrank(admin);
        poolManager.pause();
        assertTrue(poolManager.paused());

        poolManager.unpause();
        assertFalse(poolManager.paused());
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _createTestLoanParams() internal view returns (IPoolManager.LoanParams memory) {
        return IPoolManager.LoanParams({
            vault: testVault,
            borrowerId: keccak256("borrower1"),
            principal: 100_000e6,
            interestRate: 2000, // 20%
            term: 180 days,
            collateralValue: 150_000e6
        });
    }
}

// Mock for testing recoverERC20
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }
    function decimals() public view override returns (uint8) { return _decimals; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
