// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";

contract LotteryEngineV1Test is StdCheats, Test {
    using DataTypesLib for DataTypesLib.GameEntryFees;

    DeployLotteryEngine public deployLotteryEngine;
    LotteryEngineV1 public lotteryEngineV1;

    address engineProxyAddress;
    address ticketProxyAddress;
    address USER = address(0x1);

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,) = deployLotteryEngine.run();
        lotteryEngineV1 = LotteryEngineV1(engineProxyAddress);
    }

    ////////////////////////////////////////
    // createRound Tests                  //
    ///////////////////////////////////////

    function testLEV1CreateRoundRevertsNotOwner() public {
        vm.expectRevert();
        lotteryEngineV1.createRound();
    }

    function testLEV1CreateRoundWorks() public {
        uint16 currentRound = lotteryEngineV1.getCurrentRound();
        uint16 expectedRound = 1;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        assertEq(currentRound + 1, expectedRound);
    }

    function testLEV1RoundIsCreatedWithCorrectStatus() public {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();

        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Open);
        uint256 roundStatus = uint256(lotteryEngineV1.getRoundStatus(1));
        assertEq(roundStatus, expectedStatus);
    }
}
