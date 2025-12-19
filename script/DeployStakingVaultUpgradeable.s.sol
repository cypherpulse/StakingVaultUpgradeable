// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StakingVaultUpgradeable} from "src/StakingVaultUpgradeable.sol";

/// @title DeployStakingVaultUpgradeable
/// @notice Deployment script for StakingVaultUpgradeable on Celo network.
/// @dev Run with: forge script script/DeployStakingVaultUpgradeable.s.sol --rpc-url <celo-rpc> --private-key <key> --broadcast
contract DeployStakingVaultUpgradeable is Script {
    function run() external {
        // Configuration - replace with actual values for Celo
        address stakingTokenAddressOnCelo = 0x765DE816845861e75A25fCA122bb6898B8B1282a; // Example: cUSD on Celo
        uint256 initialRewardRate = 1e15; // 0.001 tokens per second per staked token

        vm.startBroadcast();

        // Deploy UUPS proxy
        address proxy = Upgrades.deployUUPSProxy(
            "StakingVaultUpgradeable.sol",
            abi.encodeCall(StakingVaultUpgradeable.initialize, (stakingTokenAddressOnCelo, initialRewardRate))
        );

        // Cast to contract for verification
        StakingVaultUpgradeable vault = StakingVaultUpgradeable(proxy);

        // Log the proxy address - this is what Celo users will interact with
        console.log("StakingVaultUpgradeable deployed at:", proxy);
        console.log("Implementation at:", Upgrades.getImplementationAddress(proxy));

        vm.stopBroadcast();
    }
}