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
    DeployLotteryEngine public deployLotteryEngine;
    LotteryEngineV1 public lotteryEngineV1;

    address engineProxyAddress;
    address ticketProxyAddress;
    address USER = address(0x1);

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,,) = deployLotteryEngine.run();
        lotteryEngineV1 = LotteryEngineV1(engineProxyAddress);
    }

    ////////////////////////////////////////
    // odifiers & Helpers                 //
    ////////////////////////////////////////

    modifier createNewRound() {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        _;
    }
    ////////////////////////////////////////
    // createRound Tests                  //
    ////////////////////////////////////////

    function testLEV1CreateRoundRevertsNotOwner() public {
        vm.expectRevert();
        lotteryEngineV1.createRound();
    }

    function testLEV1CreateRoundWorks() public createNewRound {
        uint16 currentRound = lotteryEngineV1.getCurrentRound();
        uint16 expectedRound = 1;

        assertEq(currentRound, expectedRound);
    }

    function testLEV1RoundIsCreatedWithCorrectStatus() public createNewRound {
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Open);
        uint256 roundStatus = uint256(lotteryEngineV1.getRoundStatus(1));
        assertEq(roundStatus, expectedStatus);
    }

    ////////////////////////////////////////
    // buyTicket Tests                    //
    ////////////////////////////////////////

    function testLEV1BuyTicketRevertsWhenRoundIsNotOpen() public {
        vm.expectRevert();
        lotteryEngineV1.buyTicket(1, DataTypesLib.GameEntryTier.One, 1);
    }

    function testLEV1BuyTicketUpdatesRoundStats() public createNewRound {
        uint256 expectedTicketSold = 1;
        uint16 round = 1;
        uint8 number = 33;

        vm.prank(USER);
        lotteryEngineV1.buyTicket(round, DataTypesLib.GameEntryTier.One, number);

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.One), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.One, number),
            expectedTicketSold
        );
    }

    function testLEV1BuyTicketOnlyUpdatesCorrectRoundStats() public createNewRound {
        uint256 expectedTicketSold = 0;
        uint16 round = 1;
        uint8 number = 33;

        vm.prank(USER);
        lotteryEngineV1.buyTicket(round, DataTypesLib.GameEntryTier.One, number);

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Two), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Three), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.Two, number),
            expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.Three, number),
            expectedTicketSold
        );
    }
}
