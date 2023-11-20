// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";

contract DeployLotteryEngine is Script {
    HelperConfig helperConfig = new HelperConfig();
    address owner;
    address engineProxyAddr;
    uint256 deployerKey;
    uint256[3] twoDigitGameFees;

    constructor() {
        (uint256 _deployerKey, uint256 twoDigitGameFee1, uint256 twoDigitGameFee2, uint256 twoDigitGameFee3) =
            helperConfig.activeNetworkConfig();
        // owner = address(uint160(uint256(deployerKey)));
        deployerKey = _deployerKey;
        twoDigitGameFees = [twoDigitGameFee1, twoDigitGameFee2, twoDigitGameFee3];
        owner = vm.addr(deployerKey);
    }

    function run()
        external
        returns (address engineProxy, address ticketProxy, address contractOwner, uint256[3] memory _twoDigitGameFees)
    {
        (engineProxy) = deployLotteryEngine();
        (ticketProxy) = deployTicket();
        contractOwner = owner;
        _twoDigitGameFees = twoDigitGameFees;
    }

    function deployLotteryEngine() public returns (address) {
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
