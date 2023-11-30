// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {LotteryEngineV2} from "../src/LotteryEngineV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract UpgradeLotteryEngine is Script {
    HelperConfig helperConfig = new HelperConfig();
    uint256 deployerKey;

    constructor() {
        (deployerKey,,,,,) = helperConfig.activeNetworkConfig();
    }

    function run() external returns (address) {
        address mostRecentlyDeployedProxy = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);

        vm.startBroadcast(deployerKey);
        LotteryEngineV2 newLotteryEngine = new LotteryEngineV2();
        vm.stopBroadcast();
        address proxy = upgradeLotteryEngine(mostRecentlyDeployedProxy, address(newLotteryEngine));
        return proxy;
    }

    function upgradeLotteryEngine(address proxyAddress, address newLotteryEngine) public returns (address) {
        vm.startBroadcast(deployerKey);
        LotteryEngineV1 proxy = LotteryEngineV1(payable(proxyAddress));
        proxy.upgradeToAndCall(address(newLotteryEngine), "");
        vm.stopBroadcast();
        return address(proxy);
    }
}
