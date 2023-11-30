// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {TicketV2} from "../src/TicketV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract UpgradeTicket is Script {
    HelperConfig helperConfig = new HelperConfig();
    uint256 deployerKey;

    constructor() {
        (deployerKey,,,,,) = helperConfig.activeNetworkConfig();
    }

    function run() external returns (address) {
        address mostRecentlyDeployedProxy = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);

        vm.startBroadcast(deployerKey);
        TicketV2 newTicket = new TicketV2();
        vm.stopBroadcast();
        address proxy = upgradeTicket(mostRecentlyDeployedProxy, address(newTicket));
        return proxy;
    }

    function upgradeTicket(address proxyAddress, address newTicket) public returns (address) {
        vm.startBroadcast(deployerKey);
        TicketV1 proxy = TicketV1(payable(proxyAddress));
        proxy.upgradeToAndCall(address(newTicket), "");
        vm.stopBroadcast();
        return address(proxy);
    }
}
