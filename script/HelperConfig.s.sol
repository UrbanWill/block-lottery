// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 twoDigitGameFee1 = 0.01 ether;
    uint256 twoDigitGameFee2 = 0.02 ether;
    uint256 twoDigitGameFee3 = 0.03 ether;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    struct NetworkConfig {
        uint256 deployerKey;
        uint256 twoDigitGameFee1;
        uint256 twoDigitGameFee2;
        uint256 twoDigitGameFee3;
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            deployerKey: vm.envUint("PRIVATE_KEY"),
            twoDigitGameFee1: twoDigitGameFee1,
            twoDigitGameFee2: twoDigitGameFee2,
            twoDigitGameFee3: twoDigitGameFee3
        });
    }

    function getOrCreateAnvilEthConfig() public view returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.deployerKey != 0) {
            return activeNetworkConfig;
        }

        anvilNetworkConfig = NetworkConfig({
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY,
            twoDigitGameFee1: twoDigitGameFee1,
            twoDigitGameFee2: twoDigitGameFee2,
            twoDigitGameFee3: twoDigitGameFee3
        });
    }
}
