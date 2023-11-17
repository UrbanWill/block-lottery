// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";

contract DeployLotteryEngine is Script {
    using DataTypesLib for DataTypesLib.GameEntryFees;

    HelperConfig helperConfig = new HelperConfig();
    address owner;
    address engineProxyAddr;
    uint256 deployerKey;

    constructor() {
        (deployerKey) = helperConfig.activeNetworkConfig();
        // owner = address(uint160(uint256(deployerKey)));
        owner = vm.addr(deployerKey);
    }

    function run() external returns (address engineProxy, address ticketProxy, address contractOwner) {
        (engineProxy) = deployLotteryEngine();
        (ticketProxy) = deployTicket();
        contractOwner = owner;
    }

    function deployLotteryEngine() public returns (address) {
        DataTypesLib.GameEntryFees memory twoDigitGameFees =
            DataTypesLib.GameEntryFees(0.01 ether, 0.02 ether, 0.03 ether);

        vm.startBroadcast(deployerKey);

        LotteryEngineV1 lotteryEngine = new LotteryEngineV1();
        ERC1967Proxy engineProxy = new ERC1967Proxy(address(lotteryEngine), "");
        engineProxyAddr = address(engineProxy);
        LotteryEngineV1(engineProxyAddr).initialize(owner, twoDigitGameFees);
        vm.stopBroadcast();

        return address(engineProxy);
    }

    function deployTicket() public returns (address) {
        vm.startBroadcast(deployerKey);
        TicketV1 ticket = new TicketV1();
        ERC1967Proxy ticketProxy = new ERC1967Proxy(address(ticket), "");
        TicketV1(address(ticketProxy)).initialize(owner, engineProxyAddr, owner);
        vm.stopBroadcast();

        return address(ticketProxy);
    }
}
