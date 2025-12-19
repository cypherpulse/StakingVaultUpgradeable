// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StakingVaultUpgradeable} from "src/StakingVaultUpgradeable.sol";
import {StakingVaultV2Upgradeable} from "src/StakingVaultV2Upgradeable.sol";
import {ERC20Mock} from "openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

/// @title StakingVaultUpgradeableTest
/// @notice Tests for StakingVaultUpgradeable, emulating how users on Celo would interact with the proxy.
contract StakingVaultUpgradeableTest is Test {
    StakingVaultUpgradeable public vault;
    ERC20Mock public stakingToken;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_REWARD_RATE = 1e15; // 0.001 per second
    uint256 public constant STAKE_AMOUNT = 100e18;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock staking token
        stakingToken = new ERC20Mock("Mock Token", "MTK", owner, 1000000e18);

        // Deploy implementation and proxy
        vm.startPrank(owner);
        address proxy = Upgrades.deployUUPSProxy(
            "StakingVaultUpgradeable.sol",
            abi.encodeCall(StakingVaultUpgradeable.initialize, (address(stakingToken), INITIAL_REWARD_RATE))
        );
        vault = StakingVaultUpgradeable(proxy);
        vm.stopPrank();

        // Transfer tokens to users
        stakingToken.transfer(user1, 1000e18);
        stakingToken.transfer(user2, 1000e18);

        // Approve vault to spend tokens
        vm.prank(user1);
        stakingToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        stakingToken.approve(address(vault), type(uint256).max);
    }

    function testInitialization() public {
        assertEq(address(vault.owner()), owner);
        assertEq(address(vault.stakingToken()), address(stakingToken));
        assertEq(vault.rewardRate(), INITIAL_REWARD_RATE);
        assertEq(vault.totalStaked(), 0);
    }

    function testStake() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, STAKE_AMOUNT);
        vault.stake(STAKE_AMOUNT);

        assertEq(vault.balanceOf(user1), STAKE_AMOUNT);
        assertEq(vault.totalStaked(), STAKE_AMOUNT);
        assertEq(stakingToken.balanceOf(address(vault)), STAKE_AMOUNT);
    }

    function testStakeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(StakingVaultUpgradeable.StakingVaultUpgradeable__ZeroAmount.selector);
        vault.stake(0);
    }

    function testWithdraw() public {
        vm.startPrank(user1);
        vault.stake(STAKE_AMOUNT);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, STAKE_AMOUNT / 2);
        vault.withdraw(STAKE_AMOUNT / 2);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), STAKE_AMOUNT / 2);
        assertEq(vault.totalStaked(), STAKE_AMOUNT / 2);
        assertEq(stakingToken.balanceOf(user1), 1000e18 - STAKE_AMOUNT / 2);
    }

    function testWithdrawInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert(StakingVaultUpgradeable.StakingVaultUpgradeable__InsufficientBalance.selector);
        vault.withdraw(STAKE_AMOUNT);
    }

    function testClaimRewards() public {
        vm.prank(user1);
        vault.stake(STAKE_AMOUNT);

        // Warp time to accrue rewards
        vm.warp(block.timestamp + 100);

        uint256 expectedReward = (STAKE_AMOUNT * INITIAL_REWARD_RATE * 100) / 1e18;
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RewardPaid(user1, expectedReward);
        vault.claimRewards();

        assertEq(vault.earned(user1), 0);
        assertEq(stakingToken.balanceOf(user1), 1000e18 - STAKE_AMOUNT + expectedReward);
    }

    function testClaimRewardsNoRewards() public {
        vm.prank(user1);
        vault.stake(STAKE_AMOUNT);

        vm.prank(user1);
        vm.expectRevert(StakingVaultUpgradeable.StakingVaultUpgradeable__NoRewards.selector);
        vault.claimRewards();
    }

    function testExit() public {
        vm.prank(user1);
        vault.stake(STAKE_AMOUNT);

        vm.warp(block.timestamp + 100);

        uint256 expectedReward = (STAKE_AMOUNT * INITIAL_REWARD_RATE * 100) / 1e18;
        vm.prank(user1);
        vault.exit();

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.totalStaked(), 0);
        assertEq(stakingToken.balanceOf(user1), 1000e18 + expectedReward);
    }

    function testSetRewardRate() public {
        uint256 newRate = 2e15;
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit RewardRateUpdated(INITIAL_REWARD_RATE, newRate);
        vault.setRewardRate(newRate);

        assertEq(vault.rewardRate(), newRate);
    }

    function testSetRewardRateNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setRewardRate(2e15);
    }

    function testUpgradeToV2() public {
        // Stake some tokens first
        vm.prank(user1);
        vault.stake(STAKE_AMOUNT);

        // Upgrade to V2
        vm.startPrank(owner);
        Upgrades.upgradeProxy(
            address(vault),
            "StakingVaultV2Upgradeable.sol",
            ""
        );
        StakingVaultV2Upgradeable vaultV2 = StakingVaultV2Upgradeable(address(vault));
        vaultV2.initializeV2(false);
        vm.stopPrank();

        // Check state persists
        assertEq(vaultV2.balanceOf(user1), STAKE_AMOUNT);
        assertEq(vaultV2.totalStaked(), STAKE_AMOUNT);
        assertFalse(vaultV2.paused());

        // Test new functionality
        vm.prank(owner);
        vaultV2.pause();
        assertTrue(vaultV2.paused());

        vm.prank(user1);
        vm.expectRevert(StakingVaultV2Upgradeable.StakingVaultV2Upgradeable__Paused.selector);
        vaultV2.stake(STAKE_AMOUNT);
    }
}