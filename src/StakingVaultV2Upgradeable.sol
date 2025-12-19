// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract
//
// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions
//
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {StakingVaultUpgradeable} from "./StakingVaultUpgradeable.sol";

/// @title StakingVaultV2Upgradeable
/// @notice Upgradeable single-asset staking vault V2 for the Celo network, with added pausable functionality.
/// @dev This contract is designed for the Celo network (but works on any EVM). It is upgradeable, deployed behind a proxy, and must always be interacted with via the proxy address.
/// @custom:oz-upgrades-from StakingVaultUpgradeable
contract StakingVaultV2Upgradeable is StakingVaultUpgradeable {
    // New state variables for V2
    bool private s_paused;

    // Adjust gap if needed (original had 50, we add 1, so reduce by 1)
    uint256[49] private __gap;

    // New events
    event Paused();
    event Unpaused();

    // New custom errors
    error StakingVaultV2Upgradeable__Paused();

    /// @notice Initializes V2 with paused state.
    /// @param paused Initial paused state.
    function initializeV2(bool paused) public reinitializer(2) {
        s_paused = paused;
    }

    /// @notice Pauses staking operations.
    /// @dev Only callable by the owner.
    function pause() external onlyOwner {
        s_paused = true;
        emit Paused();
    }

    /// @notice Unpauses staking operations.
    /// @dev Only callable by the owner.
    function unpause() external onlyOwner {
        s_paused = false;
        emit Unpaused();
    }

    /// @notice Checks if the contract is paused.
    /// @return True if paused, false otherwise.
    function paused() external view returns (bool) {
        return s_paused;
    }

    // Override stake to check paused
    function stake(uint256 amount) external override nonReentrant {
        if (s_paused) revert StakingVaultV2Upgradeable__Paused();
        super.stake(amount);
    }

    // Override withdraw to check paused
    function withdraw(uint256 amount) external override nonReentrant {
        if (s_paused) revert StakingVaultV2Upgradeable__Paused();
        super.withdraw(amount);
    }

    // Override claimRewards to check paused
    function claimRewards() external override nonReentrant {
        if (s_paused) revert StakingVaultV2Upgradeable__Paused();
        super.claimRewards();
    }

    // Override exit to check paused
    function exit() external override nonReentrant {
        if (s_paused) revert StakingVaultV2Upgradeable__Paused();
        super.exit();
    }
}