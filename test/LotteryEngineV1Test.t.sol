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
    address USER = makeAddr("user");

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,,) = deployLotteryEngine.run();
        lotteryEngineV1 = LotteryEngineV1(engineProxyAddress);

        vm.deal(USER, 100 ether);
    }

    ////////////////////////////////////////
    // Events                             //
    ////////////////////////////////////////

    event TicketBought(
        uint16 indexed round, DataTypesLib.GameEntryTier indexed tier, uint8 indexed number, address player
    );

    ////////////////////////////////////////
    // Modifiers & Helpers                //
    ////////////////////////////////////////

    modifier createNewRound() {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        _;
    }
    ////////////////////////////////////////
    // createRound Tests                  //
    ////////////////////////////////////////

    function testLEV1CreateRoundRevertsWhenRoundIsOpen() public createNewRound {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__CurrentRoundOngoing.selector);
        lotteryEngineV1.createRound();
    }

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
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        uint16 round = 1;
        uint8 number = 33;
        lotteryEngineV1.buyTicket(round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number);
    }

    function testLEV1BuyTicketRevertsWhenTierFeeIsIncorrect() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 incorrectAmount = 4 ether;

        vm.expectRevert(LotteryEngineV1.LotteryEngine__IncorrectTierFee.selector);
        lotteryEngineV1.buyTicket{value: incorrectAmount}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number
        );
    }

    function testLEV1BuyTicketRevertIfGameDigitNotSupported() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Three, DataTypesLib.GameEntryTier.One);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__GameDigitNotSupported.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Three, DataTypesLib.GameEntryTier.One, number
        );
    }

    function testLEV1BuyTicketRevertIfGameDigitsIsTwoAndNumberIsOutOfRange() public createNewRound {
        uint16 round = 1;
        uint8 numberAboveRange = 100;
        uint8 numberBelowRange = 0;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, numberAboveRange
        );
        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, numberBelowRange
        );
    }

    function testLEV1BuyTicketUpdatesRoundStatsAndEmits() public createNewRound {
        uint256 expectedTicketSold = 1;
        uint16 round = 1;
        uint8 number = 33;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        vm.expectEmit(true, true, true, true, engineProxyAddress);
        emit TicketBought(round, DataTypesLib.GameEntryTier.One, number, USER);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number
        );

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

        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number
        );

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
