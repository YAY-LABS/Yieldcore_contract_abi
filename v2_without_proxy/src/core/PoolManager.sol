// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {YieldCoreBase} from "./YieldCoreBase.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ILoanRegistry} from "../interfaces/ILoanRegistry.sol";
import {IRWAVault} from "../interfaces/IRWAVault.sol";
import {RWAConstants} from "../libraries/RWAConstants.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";
import {RWAEvents} from "../libraries/RWAEvents.sol";

/// @title PoolManager
/// @notice Singleton contract for managing loans and capital allocation
contract PoolManager is YieldCoreBase, IPoolManager {
    using SafeERC20 for IERC20;

    // ============ Storage ============

    /// @notice The underlying asset (e.g., USDC)
    IERC20 public asset;

    /// @notice Reference to loan registry
    ILoanRegistry public loanRegistry;

    /// @notice Treasury address for protocol fees
    address public treasury;

    /// @notice Protocol fee in basis points
    uint256 public protocolFee;

    /// @notice Accumulated protocol fees
    uint256 public accumulatedFees;

    /// @notice Mapping of registered vaults
    mapping(address => bool) private _registeredVaults;

    // ============ Constructor ============

    /// @notice Creates the pool manager
    /// @param admin_ The admin address
    /// @param asset_ The underlying asset address
    /// @param loanRegistry_ The loan registry address
    /// @param treasury_ The treasury address
    /// @param protocolFee_ The protocol fee in basis points
    constructor(
        address admin_,
        address asset_,
        address loanRegistry_,
        address treasury_,
        uint256 protocolFee_
    ) YieldCoreBase(admin_) {
        if (asset_ == address(0)) revert RWAErrors.ZeroAddress();
        if (loanRegistry_ == address(0)) revert RWAErrors.ZeroAddress();
        if (treasury_ == address(0)) revert RWAErrors.ZeroAddress();
        if (protocolFee_ > RWAConstants.MAX_PROTOCOL_FEE) revert RWAErrors.InvalidAmount();

        asset = IERC20(asset_);
        loanRegistry = ILoanRegistry(loanRegistry_);
        treasury = treasury_;
        protocolFee = protocolFee_;

        // Grant roles
        _grantRole(RWAConstants.CURATOR_ROLE, admin_);
        _grantRole(RWAConstants.OPERATOR_ROLE, admin_);
    }

    // ============ Modifiers ============

    modifier onlyRegisteredVault(address vault) {
        if (!_registeredVaults[vault]) revert RWAErrors.VaultNotRegistered();
        _;
    }

    // ============ Capital Deployment (Timelock) ============

    /// @notice Announces a capital deployment (starts timelock)
    /// @param vault The vault address
    /// @param amount The amount to deploy
    /// @param recipient The recipient address
    function announceDeployCapital(address vault, uint256 amount, address recipient)
        external
        nonReentrant
        whenNotPaused
        onlyCurator
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).announceDeployCapital(amount, recipient);
    }

    /// @notice Executes a pending deployment after timelock
    /// @param vault The vault address
    function executeDeployCapital(address vault)
        external
        nonReentrant
        whenNotPaused
        onlyCurator
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).executeDeployCapital();
    }

    /// @notice Cancels a pending deployment
    /// @param vault The vault address
    function cancelDeployCapital(address vault)
        external
        nonReentrant
        whenNotPaused
        onlyCurator
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).cancelDeployCapital();
    }

    // ============ Capital Management ============

    /// @notice Returns capital to a vault
    /// @param vault The vault address
    /// @param amount The amount to return
    function returnCapital(address vault, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyOperator
        onlyRegisteredVault(vault)
    {
        if (amount == 0) revert RWAErrors.ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(vault, amount);
        IRWAVault(vault).returnCapital(amount);
    }

    /// @notice Deposits interest to a vault
    /// @param vault The vault address
    /// @param amount The amount to deposit
    function depositInterest(address vault, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyOperator
        onlyRegisteredVault(vault)
    {
        if (amount == 0) revert RWAErrors.ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(vault, amount);
        IRWAVault(vault).depositInterest(amount);
    }

    /// @notice Triggers default on a vault
    /// @param vault The vault address
    function triggerDefault(address vault)
        external
        nonReentrant
        whenNotPaused
        onlyCurator
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).triggerDefault();
    }

    /// @notice Recovers accidentally sent tokens from a vault
    /// @param vault The vault address
    /// @param token The token address to recover
    /// @param amount The amount to recover
    /// @param recipient The recipient address
    function recoverERC20(address vault, address token, uint256 amount, address recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).recoverERC20(token, amount, recipient);
    }

    /// @notice Recovers remaining asset dust from a vault after all shares are burned
    /// @param vault The vault address
    /// @param recipient The recipient address
    function recoverAssetDust(address vault, address recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).recoverAssetDust(recipient);
    }

    /// @notice Recovers ETH accidentally sent to a vault
    /// @param vault The vault address
    /// @param recipient The recipient address
    function recoverETH(address vault, address payable recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyRegisteredVault(vault)
    {
        IRWAVault(vault).recoverETH(recipient);
    }

    // ============ Loan Management ============

    /// @notice Registers a new loan (without deployment - use announceDeployCapital separately)
    /// @param params The loan parameters
    /// @return loanId The created loan ID
    function registerLoan(LoanParams calldata params)
        external
        nonReentrant
        whenNotPaused
        onlyCurator
        onlyRegisteredVault(params.vault)
        returns (uint256 loanId)
    {
        // Validate parameters
        if (params.principal == 0) revert RWAErrors.ZeroAmount();
        if (params.term < RWAConstants.MIN_LOAN_TERM || params.term > RWAConstants.MAX_LOAN_TERM) {
            revert RWAErrors.InvalidLoanTerm();
        }
        if (params.interestRate < RWAConstants.MIN_INTEREST_RATE ||
            params.interestRate > RWAConstants.MAX_INTEREST_RATE) {
            revert RWAErrors.InvalidInterestRate();
        }
        if (params.collateralValue == 0) revert RWAErrors.InvalidCollateralValue();

        // Check LTV
        uint256 ltv = (params.principal * RWAConstants.BASIS_POINTS) / params.collateralValue;
        if (ltv > RWAConstants.MAX_LTV_RATIO) revert RWAErrors.InvalidCollateralValue();

        // Register loan (no deployment - must be done separately via announceDeployCapital)
        ILoanRegistry.Loan memory loan = ILoanRegistry.Loan({
            id: 0,
            vault: params.vault,
            borrowerId: params.borrowerId,
            principal: params.principal,
            interestRate: params.interestRate,
            term: params.term,
            collateralValue: params.collateralValue,
            startTime: 0,
            lastRepaymentTime: 0,
            totalRepaid: 0,
            totalInterestPaid: 0,
            status: ILoanRegistry.LoanStatus.Active
        });

        loanId = loanRegistry.registerLoan(loan);

        emit RWAEvents.LoanCreated(
            loanId,
            params.vault,
            params.borrowerId,
            params.principal,
            params.interestRate,
            params.term,
            params.collateralValue
        );
    }

    /// @notice Records a loan repayment
    /// @param loanId The loan ID
    /// @param principalAmount The principal amount being repaid
    /// @param interestAmount The interest amount being paid
    function recordRepayment(
        uint256 loanId,
        uint256 principalAmount,
        uint256 interestAmount
    ) external nonReentrant whenNotPaused onlyOperator {
        ILoanRegistry.Loan memory loan = loanRegistry.getLoan(loanId);

        if (loan.status != ILoanRegistry.LoanStatus.Active) revert RWAErrors.LoanNotActive();

        uint256 totalPayment = principalAmount + interestAmount;
        if (totalPayment == 0) revert RWAErrors.ZeroAmount();

        // Validate principal doesn't exceed vault's deployed amount
        uint256 vaultDeployed = IRWAVault(loan.vault).totalDeployed();
        if (principalAmount > vaultDeployed) revert RWAErrors.RepaymentExceedsOutstanding();

        // Transfer payment from operator to this contract
        asset.safeTransferFrom(msg.sender, address(this), totalPayment);

        // Approve and return principal to vault (Pull pattern)
        asset.forceApprove(loan.vault, principalAmount);
        IRWAVault(loan.vault).returnCapital(principalAmount);

        // Approve and deposit interest to vault (no protocol fee)
        if (interestAmount > 0) {
            asset.forceApprove(loan.vault, interestAmount);
            IRWAVault(loan.vault).depositInterest(interestAmount);
        }

        // Update loan registry
        loanRegistry.addRepayment(loanId, principalAmount, interestAmount);

        emit RWAEvents.RepaymentRecorded(
            loanId,
            principalAmount,
            interestAmount,
            0, // No protocol fee
            loan.principal - loan.totalRepaid - principalAmount
        );
    }

    // ============ Vault Management ============

    /// @notice Registers a vault
    /// @param vault The vault address
    function registerVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vault == address(0)) revert RWAErrors.ZeroAddress();
        if (_registeredVaults[vault]) revert RWAErrors.VaultAlreadyRegistered();

        _registeredVaults[vault] = true;

        emit RWAEvents.VaultRegistered(vault);
    }

    /// @notice Unregisters a vault
    /// @param vault The vault address
    function unregisterVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_registeredVaults[vault]) revert RWAErrors.VaultNotRegistered();

        _registeredVaults[vault] = false;

        emit RWAEvents.VaultUnregistered(vault);
    }

    /// @notice Checks if a vault is registered
    /// @param vault The vault address
    /// @return True if registered
    function isRegisteredVault(address vault) external view returns (bool) {
        return _registeredVaults[vault];
    }

    // ============ Fee Management ============

    /// @notice Withdraws accumulated protocol fees to treasury
    function withdrawFees() external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert RWAErrors.ZeroAmount();

        accumulatedFees = 0;
        asset.safeTransfer(treasury, amount);

        emit RWAEvents.FeesWithdrawn(treasury, amount);
    }

    /// @notice Sets the protocol fee
    /// @param newFee The new fee in basis points
    function setProtocolFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > RWAConstants.MAX_PROTOCOL_FEE) revert RWAErrors.InvalidAmount();

        uint256 oldFee = protocolFee;
        protocolFee = newFee;

        emit RWAEvents.ProtocolFeeUpdated(oldFee, newFee);
    }

    /// @notice Sets the treasury address
    /// @param newTreasury The new treasury address
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert RWAErrors.ZeroAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit RWAEvents.TreasuryUpdated(oldTreasury, newTreasury);
    }
}
