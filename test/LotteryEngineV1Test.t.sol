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
    TicketV1 public ticketV1;

    address engineProxyAddress;
    address ticketProxyAddress;
    address USER = makeAddr("user");
    string constant PUG_URI = "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,,) = deployLotteryEngine.run();
        lotteryEngineV1 = LotteryEngineV1(engineProxyAddress);
        ticketV1 = TicketV1(ticketProxyAddress);

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
        lotteryEngineV1.buyTicket(round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number, PUG_URI);
    }

    function testLEV1BuyTicketRevertsWhenTierFeeIsIncorrect() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 incorrectAmount = 4 ether;

        vm.expectRevert(LotteryEngineV1.LotteryEngine__IncorrectTierFee.selector);
        lotteryEngineV1.buyTicket{value: incorrectAmount}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
    }

    function testLEV1BuyTicketRevertIfGameDigitNotSupported() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Three, DataTypesLib.GameEntryTier.One);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__GameDigitNotSupported.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Three, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
    }

    function testLEV1BuyTicketRevertIfGameDigitsIsTwoAndNumberIsOutOfRange() public createNewRound {
        uint16 round = 1;
        uint8 numberAboveRange = 100;
        uint8 numberBelowRange = 0;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, numberAboveRange, PUG_URI
        );
        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, numberBelowRange, PUG_URI
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
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.One), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.One, number),
            expectedTicketSold
        );

        assertEq(address(engineProxyAddress).balance, gameFee);
    }

    function testLEV1BuyTicketOnlyUpdatesCorrectRoundStats() public createNewRound {
        uint256 expectedTicketSold = 0;
        uint16 round = 1;
        uint8 number = 33;

        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number, PUG_URI
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

    function testLEV1BuyTicketMintsNft() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        lotteryEngineV1.buyTicket{value: gameFee}(
            round, DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );

        assertEq(ticketV1.ownerOf(0), USER);
    }
    ////////////////////////////////////////
    // Price Tests                        //
    ////////////////////////////////////////

    function testLEV1GetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = lotteryEngineV1.getTokenAmountFromUsd(100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function testLEV1GetGameTokenAmountFee() public {
        uint256 expectedTierOneFee = 0.0005 ether;
        uint256 tierOneResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        assertEq(tierOneResultFee, expectedTierOneFee);

        uint256 expectedTierTwoFee = 0.001 ether;
        uint256 tierTwoResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        assertEq(tierTwoResultFee, expectedTierTwoFee);

        uint256 expectedTierThreeFee = 0.0015 ether;
        uint256 tierThreeResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);
        assertEq(tierThreeResultFee, expectedTierThreeFee);
    }
}
