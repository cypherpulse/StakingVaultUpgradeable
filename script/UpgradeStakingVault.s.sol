// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StakingVaultV2Upgradeable} from "src/StakingVaultV2Upgradeable.sol";

/// @title UpgradeStakingVault
/// @notice Upgrade script for StakingVaultUpgradeable to V2 on Celo network.
/// @dev Run with: forge script script/UpgradeStakingVault.s.sol --rpc-url <celo-rpc> --private-key <owner-key> --broadcast
contract UpgradeStakingVault is Script {
    function run() external {
        // The existing proxy address on Celo
        address proxyAddressOnCelo = 0x1234567890123456789012345678901234567890; // Replace with actual proxy address

        vm.startBroadcast();

        // Upgrade the proxy to V2
        Upgrades.upgradeProxy(
            proxyAddressOnCelo,
            "StakingVaultV2Upgradeable.sol",
            ""
        );

        // Initialize V2 if needed
        StakingVaultV2Upgradeable vault = StakingVaultV2Upgradeable(proxyAddressOnCelo);
        vault.initializeV2(false); // Start unpaused

        console.log("StakingVault upgraded to V2 at:", proxyAddressOnCelo);

        vm.stopBroadcast();
    }
}