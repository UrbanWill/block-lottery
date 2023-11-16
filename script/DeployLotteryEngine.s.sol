// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployLotteryEngine is Script {
    HelperConfig helperConfig = new HelperConfig();

    function run() external returns (address engineProxy, address ticketProxy) {
        (engineProxy, ticketProxy) = deployLotteryEngine();
    }

    function deployLotteryEngine() public returns (address, address) {
        (uint256 deployerKey) = helperConfig.activeNetworkConfig();
        address owner = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        LotteryEngineV1 lotteryEngine = new LotteryEngineV1();
        ERC1967Proxy engineProxy = new ERC1967Proxy(address(lotteryEngine), "");
        LotteryEngineV1(address(engineProxy)).initialize(owner);
        TicketV1 ticket = new TicketV1();
        ERC1967Proxy ticketProxy = new ERC1967Proxy(address(ticket), "");
        TicketV1(address(ticketProxy)).initialize(owner, address(engineProxy), owner);
        vm.stopBroadcast();
        return (address(engineProxy), address(ticketProxy));
    }
}
