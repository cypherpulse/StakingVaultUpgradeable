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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title StakingVaultUpgradeable
/// @notice Upgradeable single-asset staking vault for the Celo network, where users stake one ERC20 token and earn time-based rewards.
/// @dev This contract is designed for the Celo network (but works on any EVM). It is upgradeable, deployed behind a proxy, and must always be interacted with via the proxy address.
contract StakingVaultUpgradeable is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // State variables
    IERC20Upgradeable private s_stakingToken;
    uint256 private s_rewardRate; // reward rate per second
    uint256 private s_lastUpdateTime;
    uint256 private s_accRewardPerToken; // scaled by 1e18
    uint256 private s_totalStaked;
    mapping(address => uint256) private s_balances;
    mapping(address => uint256) private s_userRewardPerTokenPaid;
    mapping(address => uint256) private s_rewards;

    // Storage gap for future upgrades
    uint256[50] private __gap;

    // Custom errors
    error StakingVaultUpgradeable__ZeroAmount();
    error StakingVaultUpgradeable__InsufficientBalance();
    error StakingVaultUpgradeable__NoRewards();

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Initializes the staking vault with the staking token and initial reward rate.
    /// @dev This contract is meant to be used via a proxy on Celo. The stakingToken must be an ERC20 deployed on Celo.
    /// @param stakingToken The address of the ERC20 token to be staked.
    /// @param initialRewardRate The initial reward rate per second.
    function initialize(address stakingToken, uint256 initialRewardRate) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        s_stakingToken = IERC20Upgradeable(stakingToken);
        s_rewardRate = initialRewardRate;
        s_lastUpdateTime = block.timestamp;
    }

    /// @notice Authorizes upgrades to the contract implementation.
    /// @dev Only the owner can upgrade logic while keeping Celo users' balances at the proxy.
    /// @param newImplementation The address of the new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Updates the reward accounting for the given account.
    /// @param account The account to update rewards for.
    function _updateReward(address account) internal {
        uint256 _lastUpdateTime = s_lastUpdateTime;
        uint256 currentTime = block.timestamp;
        if (s_totalStaked > 0) {
            uint256 elapsed = currentTime - _lastUpdateTime;
            s_accRewardPerToken += elapsed * s_rewardRate * 1e18 / s_totalStaked;
        }
        s_lastUpdateTime = currentTime;

        if (account != address(0)) {
            uint256 earnedSoFar =
                s_balances[account] * (s_accRewardPerToken - s_userRewardPerTokenPaid[account]) / 1e18;
            s_rewards[account] += earnedSoFar;
            s_userRewardPerTokenPaid[account] = s_accRewardPerToken;
        }
    }

    /// @notice Stakes the specified amount of tokens.
    /// @dev This runs on Celo and expects the staking token to be approved from the user's Celo wallet.
    /// @param amount The amount of tokens to stake.
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert StakingVaultUpgradeable__ZeroAmount();
        _updateReward(msg.sender);
        s_totalStaked += amount;
        s_balances[msg.sender] += amount;
        s_stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraws the specified amount of staked tokens.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert StakingVaultUpgradeable__ZeroAmount();
        if (amount > s_balances[msg.sender]) revert StakingVaultUpgradeable__InsufficientBalance();
        _updateReward(msg.sender);
        s_totalStaked -= amount;
        s_balances[msg.sender] -= amount;
        s_stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claims the accumulated rewards for the caller.
    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = s_rewards[msg.sender];
        if (reward == 0) revert StakingVaultUpgradeable__NoRewards();
        s_rewards[msg.sender] = 0;
        s_stakingToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Withdraws all staked tokens and claims all rewards.
    function exit() external nonReentrant {
        uint256 balance = s_balances[msg.sender];
        uint256 reward = s_rewards[msg.sender];
        _updateReward(msg.sender);
        s_totalStaked -= balance;
        s_balances[msg.sender] = 0;
        s_rewards[msg.sender] = 0;
        s_stakingToken.safeTransfer(msg.sender, balance + reward);
        emit Withdrawn(msg.sender, balance);
        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Sets the reward rate.
    /// @dev Only callable by the owner. Changing reward rate affects future accrual on Celo.
    /// @param newRate The new reward rate per second.
    function setRewardRate(uint256 newRate) external onlyOwner {
        _updateReward(address(0));
        uint256 oldRate = s_rewardRate;
        s_rewardRate = newRate;
        emit RewardRateUpdated(oldRate, newRate);
    }

    /// @notice Rescues tokens from the contract.
    /// @dev Only callable by the owner. Allows rescuing non-staking tokens. For staking token, only surplus above totalStaked.
    /// @param token The token to rescue.
    /// @param amount The amount to rescue.
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        if (token == address(s_stakingToken)) {
            uint256 balance = s_stakingToken.balanceOf(address(this));
            require(amount <= balance - s_totalStaked, "Cannot rescue staked tokens");
        }
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    }

    /// @notice Returns the total amount staked.
    /// @return The total staked amount.
    function totalStaked() external view returns (uint256) {
        return s_totalStaked;
    }

    /// @notice Returns the staked balance of the given account.
    /// @param account The account to query.
    /// @return The staked balance.
    function balanceOf(address account) external view returns (uint256) {
        return s_balances[account];
    }

    /// @notice Returns the current reward per token.
    /// @return The reward per token.
    function rewardPerToken() public view returns (uint256) {
        uint256 _lastUpdateTime = s_lastUpdateTime;
        uint256 currentTime = block.timestamp;
        uint256 accRewardPerToken = s_accRewardPerToken;
        if (s_totalStaked > 0) {
            uint256 elapsed = currentTime - _lastUpdateTime;
            accRewardPerToken += elapsed * s_rewardRate * 1e18 / s_totalStaked;
        }
        return accRewardPerToken;
    }

    /// @notice Returns the staking token address.
    /// @return The staking token address.
    function stakingToken() external view returns (address) {
        return address(s_stakingToken);
    }
}