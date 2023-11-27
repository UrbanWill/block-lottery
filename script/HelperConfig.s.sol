// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    int256 public constant ETH_USD_PRICE = 2000e8;
    uint8 public constant DECIMALS = 8;

    // 1 ETH = 1 USD
    uint256 twoDigitGameFee1 = 1 ether;
    uint256 twoDigitGameFee2 = 2 ether;
    uint256 twoDigitGameFee3 = 3 ether;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    struct NetworkConfig {
        uint256 deployerKey;
        address priceFeed;
        uint256 twoDigitGameFee1;
        uint256 twoDigitGameFee2;
        uint256 twoDigitGameFee3;
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            deployerKey: vm.envUint("PRIVATE_KEY"),
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD
            twoDigitGameFee1: twoDigitGameFee1,
            twoDigitGameFee2: twoDigitGameFee2,
            twoDigitGameFee3: twoDigitGameFee3
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.deployerKey != 0) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY,
            priceFeed: address(ethUsdPriceFeed),
            twoDigitGameFee1: twoDigitGameFee1,
            twoDigitGameFee2: twoDigitGameFee2,
            twoDigitGameFee3: twoDigitGameFee3
        });
    }
}
