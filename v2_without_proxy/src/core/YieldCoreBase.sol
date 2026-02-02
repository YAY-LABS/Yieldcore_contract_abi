// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {RWAConstants} from "../libraries/RWAConstants.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";

/// @title YieldCoreBase
/// @notice Abstract base contract for YieldCore RWA protocol
/// @dev Provides AccessControl, Pausable, and ReentrancyGuard functionality
abstract contract YieldCoreBase is
    AccessControl,
    Pausable,
    ReentrancyGuard
{
    // ============ Modifiers ============

    /// @notice Ensures the caller has the PAUSER_ROLE
    modifier onlyPauser() {
        if (!hasRole(RWAConstants.PAUSER_ROLE, msg.sender)) {
            revert RWAErrors.Unauthorized();
        }
        _;
    }

    /// @notice Ensures the caller has the OPERATOR_ROLE
    modifier onlyOperator() {
        if (!hasRole(RWAConstants.OPERATOR_ROLE, msg.sender)) {
            revert RWAErrors.Unauthorized();
        }
        _;
    }

    /// @notice Ensures the caller has the CURATOR_ROLE
    modifier onlyCurator() {
        if (!hasRole(RWAConstants.CURATOR_ROLE, msg.sender)) {
            revert RWAErrors.Unauthorized();
        }
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the base contract
    /// @param admin_ The address to grant admin roles
    constructor(address admin_) {
        if (admin_ == address(0)) revert RWAErrors.ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(RWAConstants.PAUSER_ROLE, admin_);
    }

    // ============ Admin Functions ============

    /// @notice Pauses the contract
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyPauser {
        _unpause();
    }
}
