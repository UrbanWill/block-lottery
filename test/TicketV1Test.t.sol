// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {UpgradeLotteryEngine} from "../script/UpgradeLotteryEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";

contract TicketV1Test is StdCheats, Test {
    DeployLotteryEngine public deployLotteryEngine;
    TicketV1 public ticketV1;

    address engineProxyAddress; // MinterRole
    address ticketProxyAddress;

    address USER = address(0x1);

    string constant MOCKED_URI = "test";
    uint16 constant MOCKE_ROUND = 1;

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,) = deployLotteryEngine.run();
        ticketV1 = TicketV1(ticketProxyAddress);
    }

    ///////////////////////
    // safeMint Tests    //
    ///////////////////////

    function testTicketV1SafeMintRevertsNotMinterRole() public {
        vm.expectRevert();
        ticketV1.safeMint(USER, MOCKED_URI, MOCKE_ROUND);
    }

    function testTicketV1SafeMintWorks() public {
        vm.prank(engineProxyAddress);
        ticketV1.safeMint(USER, MOCKED_URI, MOCKE_ROUND);
        assertEq(ticketV1.ownerOf(0), USER);
    }
}
