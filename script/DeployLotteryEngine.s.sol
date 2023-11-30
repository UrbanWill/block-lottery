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
    uint256 deployerKey;
    address priceFeed;
    uint256[3] twoDigitGameFees;
    uint8 payoutFactor;

    constructor() {
        (
            uint256 _deployerKey,
            address _priceFeed,
            uint256 twoDigitGameFee1,
            uint256 twoDigitGameFee2,
            uint256 twoDigitGameFee3,
            uint8 _payoutFactor
        ) = helperConfig.activeNetworkConfig();
        // owner = address(uint160(uint256(deployerKey)));
        owner = vm.addr(_deployerKey);
        deployerKey = _deployerKey;
        priceFeed = _priceFeed;
        payoutFactor = _payoutFactor;
        twoDigitGameFees = [twoDigitGameFee1, twoDigitGameFee2, twoDigitGameFee3];
    }

    function run()
        external
        returns (
            address engineProxy,
            address ticketProxy,
            address contractOwner,
            uint256[3] memory _twoDigitGameFees,
            uint8 _payoutFactor
        )
    {
        (engineProxy) = deployLotteryEngine();
        (ticketProxy) = deployTicket();
        initializeContracts(ticketProxy, engineProxy);
        contractOwner = owner;
        _twoDigitGameFees = twoDigitGameFees;
        _payoutFactor = payoutFactor;
    }

    function deployLotteryEngine() public returns (address) {
        vm.startBroadcast(deployerKey);
        LotteryEngineV1 lotteryEngine = new LotteryEngineV1();
        ERC1967Proxy engineProxy = new ERC1967Proxy(address(lotteryEngine), "");
        vm.stopBroadcast();

        return address(engineProxy);
    }

    function deployTicket() public returns (address) {
        vm.startBroadcast(deployerKey);
        TicketV1 ticket = new TicketV1();
        ERC1967Proxy ticketProxy = new ERC1967Proxy(address(ticket), "");
        vm.stopBroadcast();

        return address(ticketProxy);
    }

    function initializeContracts(address ticketProxy, address engineProxy) public {
        vm.startBroadcast(deployerKey);
        LotteryEngineV1(engineProxy).initialize(owner, ticketProxy, priceFeed, twoDigitGameFees, payoutFactor);
        TicketV1(address(ticketProxy)).initialize(owner, engineProxy, owner);
        vm.stopBroadcast();
    }
}
