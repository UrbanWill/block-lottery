// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";
import {GasHelpers} from "./helpers/GasHelpers.sol";

contract LotteryEngineV1Test is StdCheats, Test, GasHelpers {
    DeployLotteryEngine public deployLotteryEngine;
    LotteryEngineV1 public lotteryEngineV1;
    TicketV1 public ticketV1;

    address engineProxyAddress;
    address ticketProxyAddress;
    address USER = makeAddr("user");
    address RAMONA = makeAddr("ramona");
    address LOTTERY_OWNER = makeAddr("lottery-owner");
    string constant PUG_URI = "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";
    uint256[3] twoDigitGameFees = [1 ether, 2 ether, 3 ether];

    uint256 ethUsdOraclePrice = 2000;
    uint16 CLAIMABLE_DELAY = 1 hours;

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,,) = deployLotteryEngine.run();
        lotteryEngineV1 = LotteryEngineV1(engineProxyAddress);
        ticketV1 = TicketV1(ticketProxyAddress);

        vm.deal(USER, 100 ether);
        vm.deal(engineProxyAddress, 100 ether);
    }

    ////////////////////////////////////////
    // Events                             //
    ////////////////////////////////////////

    event RoundCreated(uint16 indexed round, uint256 timestamp);
    event RoundPaused(uint16 indexed round, uint256 timestamp);
    event RoundUnpaused(uint16 indexed round, uint256 timestamp);
    event RoundResultsPosted(
        uint16 indexed round, uint8 indexed lowerWinner, uint8 indexed upperWinner, uint256 timestamp
    );
    event RoundResultsAmended(
        uint16 indexed round, uint8 indexed lowerWinner, uint16 indexed upperWinner, uint256 timestamp
    );
    event RoundClosed(uint16 indexed round, uint16 winners, uint16 claimed, uint256 timestamp);
    event TicketBought(
        uint16 indexed round,
        DataTypesLib.GameDigits digits,
        DataTypesLib.GameType indexed gameType,
        DataTypesLib.GameEntryTier indexed tier,
        uint8 number,
        address player
    );
    event TicketClaimed(
        uint16 indexed round,
        DataTypesLib.GameDigits digits,
        DataTypesLib.GameType indexed gameType,
        DataTypesLib.GameEntryTier indexed tier,
        uint8 number,
        uint256 tokenId,
        uint256 winnings,
        address player
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

    function testLEV1CreateRoundWorksAndEmmits() public {
        uint16 expectedRound = 1;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundCreated(expectedRound, block.timestamp);

        lotteryEngineV1.createRound();

        uint16 currentRound = lotteryEngineV1.getCurrentRound();
        assertEq(currentRound, expectedRound);
    }

    function testLEV1RoundIsCreatedWithCorrectStatus() public createNewRound {
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Open);
        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(1);
        uint256 roundStatus = uint256(status);
        assertEq(roundStatus, expectedStatus);
    }
    ////////////////////////////////////////
    // pauseRound Tests                   //
    ////////////////////////////////////////

    function testLEV1PauseRoundRevertsWhenRoundIsNotOpen() public {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        lotteryEngineV1.pauseRound();
    }

    function testLEV1PauseRoundRevertsNotOwner() public createNewRound {
        vm.expectRevert();
        lotteryEngineV1.pauseRound();
    }

    function testLEV1PauseRoundWorksAndEmmits() public createNewRound {
        uint16 round = 1;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Paused);

        vm.expectEmit(true, true, false, false, engineProxyAddress);
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        emit RoundPaused(round, block.timestamp);
        lotteryEngineV1.pauseRound();

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(1);

        uint256 roundStatus = uint256(status);
        assertEq(roundStatus, expectedStatus);
    }

    ////////////////////////////////////////
    // unpauseRound Tests                 //
    ////////////////////////////////////////

    function testLEV1UnpauseRoundRevertsWhenNotOwner() public createNewRound {
        vm.expectRevert();
        lotteryEngineV1.unpauseRound();
    }

    function testLEV1UnpauseRoundRevertsWhenNotPaused() public {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBePaused.selector);
        lotteryEngineV1.unpauseRound();
    }

    function testLEV1UnpauseRoundWorksAndEmmits() public createNewRound {
        uint16 round = 1;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Open);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundUnpaused(round, block.timestamp);
        lotteryEngineV1.unpauseRound();
        vm.stopPrank();

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(1);

        uint256 roundStatus = uint256(status);
        assertEq(roundStatus, expectedStatus);
    }

    ////////////////////////////////////////
    // postRoundResults Tests             //
    ////////////////////////////////////////

    function testLEV1PostRoundResultsRevertsNotOwner() public createNewRound {
        vm.expectRevert();
        lotteryEngineV1.pauseRound();
    }

    function testLEV1PostRoundResultsRevertWhenRoundIsNotPaused() public {
        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBePaused.selector);
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
    }

    function testLEV1PostRoundResultsUpdatesStatusAndEmits(uint8 lowerWinner, uint8 upperWinner)
        public
        createNewRound
    {
        lowerWinner = uint8(bound(lowerWinner, 1, 99));
        upperWinner = uint8(bound(upperWinner, 1, 99));

        uint16 round = 1;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Closed);
        uint256 expectedClaimableAt = block.timestamp + CLAIMABLE_DELAY;
        uint16 expectedWinners = 0;
        uint16 expectedClaimed = 0;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();

        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundResultsPosted(round, lowerWinner, upperWinner, block.timestamp);
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundClosed(round, expectedWinners, expectedClaimed, block.timestamp);
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        (DataTypesLib.GameStatus status, uint8 lowerWinnerResult, uint8 upperWinnerResult,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(lowerWinnerResult, lowerWinner);
        assertEq(upperWinnerResult, upperWinner);
        assertEq(claimableAt, expectedClaimableAt);
    }

    function testLEV1PostRoundResultsRoundIsClaimableWhenThereAreWinners() public createNewRound buyTwoDigitsTicket {
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint16 round = 1;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Claimable);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
    }

    function testLEV1PostRoundResultsUpdatesCorrectRound(uint8 lowerWinner, uint8 upperWinner) public createNewRound {
        lowerWinner = uint8(bound(lowerWinner, 1, 99));
        upperWinner = uint8(bound(upperWinner, 1, 99));
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Closed);

        uint8 roundOneLowerWinner = 22;
        uint8 roundOneUpperWinner = 23;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(roundOneLowerWinner, roundOneUpperWinner);
        vm.stopPrank();

        // Creates and closes round 2
        vm.warp(100);
        uint16 roundTwo = 2;
        uint256 expectedClaimableAt = block.timestamp + CLAIMABLE_DELAY;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        lotteryEngineV1.pauseRound();

        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        // Round two assertions:
        (DataTypesLib.GameStatus status, uint8 lowerWinnerResult, uint8 upperWinnerResult,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(roundTwo);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(lowerWinnerResult, lowerWinner);
        assertEq(upperWinnerResult, upperWinner);
        assertEq(claimableAt, expectedClaimableAt);
    }

    ////////////////////////////////////////
    // amendRoundResults Tests            //
    ////////////////////////////////////////

    function testLEV1AmendRoundResultsRevertsNotOwner() public createNewRound {
        uint8 amendedLowerWinner = 33;
        uint8 amendedUpperWinner = 32;

        vm.expectRevert();
        lotteryEngineV1.amendRoundResults(amendedLowerWinner, amendedUpperWinner);
    }

    function testLEV1AmendResultsRevertWhenNotOnTime() public createNewRound {
        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;
        uint8 amendedLowerWinner = 33;
        uint8 amendedUpperWinner = 32;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);

        vm.warp(61 minutes);
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundResultAmendMustBeWithinTime.selector);
        lotteryEngineV1.amendRoundResults(amendedLowerWinner, amendedUpperWinner);
        vm.stopPrank();
    }

    function testLEV1AmendResultsUpdatesStorageAndEmits() public createNewRound {
        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;
        uint8 amendedLowerWinner = 33;
        uint8 amendedUpperWinner = 32;
        uint16 round = 1;
        uint256 warpTime = 59 minutes;

        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Closed);
        uint256 expectedClaimableAt = block.timestamp + warpTime + CLAIMABLE_DELAY - 1;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.warp(warpTime);
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundResultsAmended(round, amendedLowerWinner, amendedUpperWinner, block.timestamp);
        lotteryEngineV1.amendRoundResults(amendedLowerWinner, amendedUpperWinner);
        vm.stopPrank();

        (DataTypesLib.GameStatus status, uint8 lowerWinerResult, uint8 upperWinnerResult,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(lowerWinerResult, amendedLowerWinner);
        assertEq(upperWinnerResult, amendedUpperWinner);
        assertEq(claimableAt, expectedClaimableAt);
    }

    function testLEV1AmendRoundResultsUpdatesRoundToClaimableWhenThereIsAWinner()
        public
        createNewRound
        buyTwoDigitsTicket
    {
        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;
        uint8 amendedLowerWinner = 33;
        uint8 amendedUpperWinner = 32;
        uint16 round = 1;

        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Claimable);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        lotteryEngineV1.amendRoundResults(amendedLowerWinner, amendedUpperWinner);
        vm.stopPrank();

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
    }

    ////////////////////////////////////////
    // withdrawl Tests                    //
    ////////////////////////////////////////

    function testLEV1WithdrawRevertsWhenNotOwner() public {
        vm.expectRevert();
        lotteryEngineV1.withdraw(LOTTERY_OWNER, 1 ether);
    }

    function testLEV1WithdrawRevertsWhenRoundIsOngoing() public createNewRound {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__CurrentRoundOngoing.selector);
        lotteryEngineV1.withdraw(LOTTERY_OWNER, 1 ether);
    }

    function testLEV1WithdrawRevertsWhenAmountBiggerThanDebt() public createNewRound buyTwoDigitsTicket {
        uint8 number = 99;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, DataTypesLib.GameType.Lower, tier, number, PUG_URI);

        uint256 lotteryEngineBalance = address(engineProxyAddress).balance;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__AmountMustBeLessThanTotalUnclaimedWinnings.selector);
        lotteryEngineV1.withdraw(LOTTERY_OWNER, lotteryEngineBalance);
    }

    function testLEV1WithdrawWorks() public createNewRound buyTwoDigitsTicket {
        uint8 number = 99;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, DataTypesLib.GameType.Lower, tier, number, PUG_URI);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 lotteryEngineBalance = address(engineProxyAddress).balance;
        uint256 lotteryEngineDebt = lotteryEngineV1.getTotalUnclaimedWinnings();
        uint256 availableBalance = lotteryEngineBalance - lotteryEngineDebt;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.withdraw(LOTTERY_OWNER, availableBalance);

        assertEq(address(LOTTERY_OWNER).balance, availableBalance);
        assertEq(address(engineProxyAddress).balance, lotteryEngineDebt);
    }

    ////////////////////////////////////////
    // buyTwoDigits Tests                 //
    ////////////////////////////////////////

    function testLEV1BuyTwoDigitsRevertsWhenRoundIsNotOpen() public {
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        uint16 round = 1;
        uint8 number = 33;
        lotteryEngineV1.buyTwoDigitsTicket(
            round, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
    }

    function testLEV1BuyTwoDigitsRevertsWhenRoundIsPaused() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        lotteryEngineV1.buyTwoDigitsTicket(
            round, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
    }

    function testLEV1BuyTwoDigitsRevertsWhenTierFeeIsIncorrect(uint256 _tier, uint8 number) public createNewRound {
        number = uint8(bound(number, 1, 99));
        _tier = bound(_tier, 0, 2);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint16 round = 1;
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 incorrectAmount = gameFee + 1 wei;
        vm.expectRevert(LotteryEngineV1.LotteryEngine__IncorrectTierFee.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: incorrectAmount}(
            round, DataTypesLib.GameType.Upper, tier, number, PUG_URI
        );
    }

    function testLEV1BuyTwoDigitsRevertIfGameDigitsIsTwoAndNumberIsOutOfRange(uint8 numberAboveRange)
        public
        createNewRound
    {
        numberAboveRange = uint8(bound(numberAboveRange, 100, 255));
        uint16 round = 1;
        uint8 numberBelowRange = 0;
        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.One, numberAboveRange, PUG_URI
        );
        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.One, numberBelowRange, PUG_URI
        );
    }

    // TODO: Split this test into multiple tests, "Reverse" game types and "Regular" game types
    function testLEV1BuyTwoDigitsUpdatesRoundStatsAndEmits(uint256 _gameType, uint256 _tier, uint256 number)
        public
        createNewRound
    {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 3);
        number = bound(number, 1, 99);

        uint16 round = 1;
        uint256 expectedTicketSold = 1;
        uint256 expectedNumberSold = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);
        uint256 initialBalance = address(engineProxyAddress).balance;
        uint256 expectedBalance = initialBalance + gameFee;

        if (gameType == DataTypesLib.GameType.Upper || gameType == DataTypesLib.GameType.Reverse) {
            expectedTicketSold = 2;
        } else if (gameType == DataTypesLib.GameType.UpperReverse) {
            expectedTicketSold = 4;
        }

        if (gameType == DataTypesLib.GameType.Reverse || gameType == DataTypesLib.GameType.UpperReverse) {
            uint8 reversedNumber = lotteryEngineV1.reverseTwoDigitUint8(uint8(number));
            if (reversedNumber == number) {
                expectedNumberSold = expectedNumberSold * 2;
            }
        }

        vm.prank(USER);
        vm.expectEmit(true, true, true, true, engineProxyAddress);
        emit TicketBought(round, DataTypesLib.GameDigits.Two, gameType, tier, uint8(number), USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);

        assertEq(lotteryEngineV1.getTierTicketCountSoldPerRound(round, tier), expectedTicketSold);
        assertEq(
            lotteryEngineV1.getTwoDigitsNumberCountPerType(round, gameType, tier, uint8(number)), expectedNumberSold
        );
        assertEq(address(engineProxyAddress).balance, expectedBalance);
    }

    function testLEV1BuyTwoDigitsOnlyUpdatesCorrectRoundStats(uint256 number) public createNewRound {
        number = bound(number, 1, 99);

        uint256 expectedTicketSold = 0;
        uint16 round = 1;
        uint256 gameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One, uint8(number), PUG_URI
        );

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Two), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Three), expectedTicketSold
        );

        assertEq(
            lotteryEngineV1.getTwoDigitsNumberCountPerType(
                round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.Two, uint8(number)
            ),
            expectedTicketSold
        );

        assertEq(
            lotteryEngineV1.getTwoDigitsNumberCountPerType(
                round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.Three, uint8(number)
            ),
            expectedTicketSold
        );
    }

    function testLEV1BuyTwoDigitsMintsNft(uint256 _gameType, uint256 _tier, uint256 number) public createNewRound {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 3);
        number = bound(number, 1, 99);

        uint16 round = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);
        startMeasuringGas("buyTicket gas:");
        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);
        stopMeasuringGas();

        assertEq(ticketV1.ownerOf(0), USER);
    }
    ////////////////////////////////////////
    // claimWinnings Tests                //
    ////////////////////////////////////////

    modifier buyTwoDigitsTicket() {
        uint8 number = 33;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, DataTypesLib.GameType.Lower, tier, number, PUG_URI);

        _;
    }

    function testLEV1ClaimWinningsRevertsWhenRoundIsNotClaimable() public createNewRound {
        uint256 tokenId = 1;
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeClaimable.selector);
        lotteryEngineV1.claimWinnings(tokenId);
    }

    function testLEV1ClaimWinningsRevertsWhenNotTicketOwner() public createNewRound buyTwoDigitsTicket {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.prank(RAMONA);
        vm.expectRevert(LotteryEngineV1.LotteryEngine__OnlyTicketOwnerCanClaimWinnings.selector);
        lotteryEngineV1.claimWinnings(tokenId);
    }

    function testLEV1ClaimWinningsRevertsWhenTicketAlreadyClaimed() public createNewRound buyTwoDigitsTicket {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        // Buys one more winning ticket to prevent the round from closing when the only winner claims their ticket
        uint16 round = 1;
        uint256 gameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One) * 2;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Upper, DataTypesLib.GameEntryTier.One, uint8(upperWinner), PUG_URI
        );

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokenId);

        vm.expectRevert(LotteryEngineV1.LotteryEngine__TicketAlreadyClaimed.selector);
        lotteryEngineV1.claimWinnings(tokenId);
        vm.stopPrank();
    }

    function testLEV1ClaimWinningsClosesRoundWhenLastWinnerClaims() public createNewRound buyTwoDigitsTicket {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        DataTypesLib.GameStatus expectedStatus = DataTypesLib.GameStatus.Closed;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokenId);

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(1);

        assertEq(uint256(status), uint256(expectedStatus));
    }

    function testLEV1ClaimWinningsUpdatesWinnersClaimedCount() public createNewRound buyTwoDigitsTicket {
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint256 expectedWinnersClaimedCount = 1;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokenId);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTierWinnersClaimedPerRound(round, tier), expectedWinnersClaimedCount);
    }

    function testLEV1ClaimWinningsPaysAndEmits() public createNewRound buyTwoDigitsTicket {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint256 expectedWinnings = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * lotteryEngineV1.s_paymentFactor();
        uint256 expectedBalance = address(USER).balance + expectedWinnings;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit TicketClaimed(
            1,
            DataTypesLib.GameDigits.Two,
            DataTypesLib.GameType.Lower,
            DataTypesLib.GameEntryTier.One,
            lowerWinner,
            tokenId,
            expectedWinnings,
            USER
        );
        lotteryEngineV1.claimWinnings(tokenId);
        vm.stopPrank();

        assertEq(address(USER).balance, expectedBalance);
    }

    function testLEV1ClaimWinningsDoesNotPayWhenNotWinner() public createNewRound buyTwoDigitsTicket {
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint8 number = 24;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        vm.prank(USER);
        uint256 loserTokenId = lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Lower, tier, number, PUG_URI
        );

        uint256 expectedBalance = address(USER).balance;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(loserTokenId);
        vm.stopPrank();

        assertEq(address(USER).balance, expectedBalance);
    }
    ////////////////////////////////////////
    // Price Tests                        //
    ////////////////////////////////////////

    function testLEV1GetTokenAmountFromUsd(uint256 usdAmountInWei) public {
        vm.assume(usdAmountInWei < 1000 ether);

        /**
         *  @notice: Keeping this here for reference:
         */
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        // uint256 expectedWeth = 0.05 ether;
        // uint256 amountWeth = lotteryEngineV1.getTokenAmountFromUsd(100 ether);
        // assertEq(amountWeth, expectedWeth);

        uint256 expectedWeth = usdAmountInWei / ethUsdOraclePrice;
        uint256 amountWeth = lotteryEngineV1.getTokenAmountFromUsd(usdAmountInWei);
        assertEq(amountWeth, expectedWeth);
    }

    function testLEV1GetGameTokenAmountFee() public {
        uint256 expectedTierOneFee =
            lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One) / ethUsdOraclePrice;

        uint256 tierOneResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        assertEq(tierOneResultFee, expectedTierOneFee);
        /**
         * @dev: expectedTierTwoFee and expectedTierThreeFee Does the same as expectedTierOneFee but not dynamic.
         * If fee value change in HelperConfig, these will need to be updated.
         */
        uint256 expectedTierTwoFee = 0.001 ether;
        uint256 tierTwoResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        assertEq(tierTwoResultFee, expectedTierTwoFee);

        uint256 expectedTierThreeFee = 0.0015 ether;
        uint256 tierThreeResultFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);
        assertEq(tierThreeResultFee, expectedTierThreeFee);
    }

    function testLEV1getUsdValueFromToken(uint256 ethAmount) public {
        vm.assume(ethAmount < 1000 ether);

        /**
         *  @dev: Keeping this here for reference:
         */
        // uint256 ethAmount = 15e18;
        // // 15e18 * 2000/ETH = 30,000e18
        // uint256 expectedUsd = 30000e18;
        // uint256 actual = lotteryEngineV1.getUsdValueFromToken(ethAmount);

        // assertEq(actual, expectedUsd);

        // uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = ethAmount * ethUsdOraclePrice;
        uint256 actual = lotteryEngineV1.getUsdValueFromToken(ethAmount);

        assertEq(actual, expectedUsd);
    }

    function testLEV1CalculateTwoDigitsTicketFee() public {
        uint256 expectedLowerFee =
            lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One) / ethUsdOraclePrice;

        uint256 actualLowerFee = lotteryEngineV1.calculateTwoDigitsTicketFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One
        );
        uint256 actualUpperFee = lotteryEngineV1.calculateTwoDigitsTicketFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameType.Upper, DataTypesLib.GameEntryTier.One
        );
        uint256 actualReverseFee = lotteryEngineV1.calculateTwoDigitsTicketFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameType.Upper, DataTypesLib.GameEntryTier.One
        );
        uint256 actualUpperReverseFee = lotteryEngineV1.calculateTwoDigitsTicketFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameType.UpperReverse, DataTypesLib.GameEntryTier.One
        );

        assertEq(actualLowerFee, expectedLowerFee);
        assertEq(actualUpperFee, expectedLowerFee * 2);
        assertEq(actualReverseFee, expectedLowerFee * 2);
        assertEq(actualUpperReverseFee, expectedLowerFee * 4);
    }

    ////////////////////////////////////////
    // View & Pure functions tests        //
    ////////////////////////////////////////

    function testLEV1GetCurrentRoud() public createNewRound {
        uint16 expectedRound = 1;
        uint16 currentRound = lotteryEngineV1.getCurrentRound();
        assertEq(currentRound, expectedRound);
    }

    function testLEVGetRoundInfo() public createNewRound {
        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Closed);
        uint256 expectedClaimableAt = block.timestamp + CLAIMABLE_DELAY;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        (DataTypesLib.GameStatus status, uint8 lowerWinnerResult, uint8 upperWinnerResult,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(lowerWinnerResult, lowerWinner);
        assertEq(upperWinnerResult, upperWinner);
        assertEq(claimableAt, expectedClaimableAt);
    }

    function testLEV1GetTierTicketCountSoldPerRound() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 expectedTierOneTicketsSold = 2;
        uint256 expectedTierTwoTicketsSold = 1;
        uint256 expectedTierThreeTicketsSold = 3;
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;

        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, number, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        vm.stopPrank();

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.One),
            expectedTierOneTicketsSold
        );
        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Two),
            expectedTierTwoTicketsSold
        );
        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Three),
            expectedTierThreeTicketsSold
        );
    }

    function testLEV1GetTierWinnersClaimedPerRound(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8 loweNumber = 33;
        uint256 expectedWinnersClaimedCount = 3;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);

        vm.startPrank(USER);
        uint256 tokendIdOne =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        uint256 tokendIdTwo =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        uint256 tokendIdThree =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);

        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokendIdOne);
        lotteryEngineV1.claimWinnings(tokendIdTwo);
        lotteryEngineV1.claimWinnings(tokendIdThree);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTierWinnersClaimedPerRound(round, tier), expectedWinnersClaimedCount);
    }

    function testLEV1getTotalWinnersClaimedPerRound() public createNewRound {
        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8 loweNumber = 33;
        uint256 expectedWinnersClaimedCount = 3;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        vm.startPrank(USER);
        uint256 tokendIdOne = lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, uint8(loweNumber), PUG_URI
        );
        uint256 tokendIdTwo = lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, uint8(loweNumber), PUG_URI
        );
        uint256 tokendIdThree = lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, uint8(loweNumber), PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);

        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokendIdOne);
        lotteryEngineV1.claimWinnings(tokendIdTwo);
        lotteryEngineV1.claimWinnings(tokendIdThree);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTotalWinnersClaimedPerRound(round), expectedWinnersClaimedCount);
    }

    function testLEV1GetTwoDigitsNumberCountPerType(uint256 _gameType, uint256 _tier, uint256 number)
        public
        createNewRound
    {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 3);
        number = bound(number, 1, 99);

        uint16 round = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);

        uint256 expectedNumberSold = 3;

        // handles cases where number is the same as the reversed number, eg: single digit numbers or 11, 22, 33...
        if (gameType == DataTypesLib.GameType.Reverse || gameType == DataTypesLib.GameType.UpperReverse) {
            uint8 reversedNumber = lotteryEngineV1.reverseTwoDigitUint8(uint8(number));
            if (reversedNumber == number) {
                expectedNumberSold = expectedNumberSold * 2;
            }
        }

        vm.startPrank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);
        vm.stopPrank();

        assertEq(
            lotteryEngineV1.getTwoDigitsNumberCountPerType(round, gameType, tier, uint8(number)), expectedNumberSold
        );
    }

    function testLEV1GetTierWinnerCountPerRound(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8 loweNumber = 33;
        uint256 expectedWinnersCount = 3;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);

        vm.startPrank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(loweNumber), PUG_URI);
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTierWinnerCountPerRound(round, tier), expectedWinnersCount);
    }

    function testLEV1GetTotalWinnersCountPerRound() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 tierOneTicketCount = 2;
        uint256 tierTwoTicketCount = 1;
        uint256 tierThreeTicketCount = 3;
        uint256 expectedWinnersCount = tierOneTicketCount + tierTwoTicketCount + tierThreeTicketCount;
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, number, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTotalWinnersCountPerRound(round), expectedWinnersCount);
    }

    function testLEV1GetUnclaimedWinningsPerTierAndRound() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 unclaimedTierOneTickets = 2;
        uint256 unclaimedTierTwoTickets = 1;
        uint256 unclaimedTierThreeTickets = 3;
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        uint256 expectedUnclaimedTierOne = tierOneGameFee * unclaimedTierOneTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierTwo = tierTwoGameFee * unclaimedTierTwoTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierThree =
            tierThreeGameFee * unclaimedTierThreeTickets * lotteryEngineV1.s_paymentFactor();

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, number, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        assertEq(
            lotteryEngineV1.getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.One),
            expectedUnclaimedTierOne
        );
        assertEq(
            lotteryEngineV1.getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.Two),
            expectedUnclaimedTierTwo
        );
        assertEq(
            lotteryEngineV1.getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.Three),
            expectedUnclaimedTierThree
        );
    }

    function testLEV1GetTotalUnclaimedWinningsPerRound() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 unclaimedTierOneTickets = 2;
        uint256 unclaimedTierTwoTickets = 1;
        uint256 unclaimedTierThreeTickets = 3;
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        uint256 expectedUnclaimedTierOne = tierOneGameFee * unclaimedTierOneTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierTwo = tierTwoGameFee * unclaimedTierTwoTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierThree =
            tierThreeGameFee * unclaimedTierThreeTickets * lotteryEngineV1.s_paymentFactor();

        uint256 expectedTotalUnclaimed =
            expectedUnclaimedTierOne + expectedUnclaimedTierTwo + expectedUnclaimedTierThree;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, number, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTotalUnclaimedWinningsPerRound(round), expectedTotalUnclaimed);
    }

    function testLEV1GetTotalUnclaimedWinnings() public createNewRound {
        uint16 round = 1;
        uint8 number = 33;
        uint256 unclaimedTierOneTickets = 2;
        uint256 unclaimedTierTwoTickets = 1;
        uint256 unclaimedTierThreeTickets = 3;
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint256 tierOneGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeGameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three);

        uint256 expectedUnclaimedTierOne = tierOneGameFee * unclaimedTierOneTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierTwo = tierTwoGameFee * unclaimedTierTwoTickets * lotteryEngineV1.s_paymentFactor();
        uint256 expectedUnclaimedTierThree =
            tierThreeGameFee * unclaimedTierThreeTickets * lotteryEngineV1.s_paymentFactor();

        uint256 totalUnclaimedRoundOne =
            expectedUnclaimedTierOne + expectedUnclaimedTierTwo + expectedUnclaimedTierThree;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, number, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, number, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        lotteryEngineV1.createRound();
        vm.stopPrank();

        uint16 roundTwo = 2;
        uint256 unclaimedTierOneTicketsRoundTwo = 1;
        uint256 expectedUnclaimedTierOneRoundTwo =
            tierOneGameFee * unclaimedTierOneTicketsRoundTwo * lotteryEngineV1.s_paymentFactor();
        uint256 expectedTotalUnclaimed = totalUnclaimedRoundOne + expectedUnclaimedTierOneRoundTwo;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            roundTwo, gameType, DataTypesLib.GameEntryTier.One, number, PUG_URI
        );

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTotalUnclaimedWinnings(), expectedTotalUnclaimed);
    }

    function testLEV1GetGameFee() public {
        assertEq(
            LotteryEngineV1(engineProxyAddress).getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One),
            twoDigitGameFees[0]
        );
        assertEq(
            LotteryEngineV1(engineProxyAddress).getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two),
            twoDigitGameFees[1]
        );
        assertEq(
            LotteryEngineV1(engineProxyAddress).getGameFee(
                DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three
            ),
            twoDigitGameFees[2]
        );
    }

    function testLEV1ReveseTwoDigitUint8Reverts() public {
        uint8 number = 0;
        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.reverseTwoDigitUint8(number);

        number = 100;
        vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
        lotteryEngineV1.reverseTwoDigitUint8(number);
    }

    function testLEV1ReverseTwoDigitUint8() public {
        uint8 number = 33;
        uint8 expectedReversedNumber = 33;
        uint8 reversedNumber = lotteryEngineV1.reverseTwoDigitUint8(number);
        assertEq(reversedNumber, expectedReversedNumber);

        number = 12;
        expectedReversedNumber = 21;
        reversedNumber = lotteryEngineV1.reverseTwoDigitUint8(number);
        assertEq(reversedNumber, expectedReversedNumber);

        number = 99;
        expectedReversedNumber = 99;
        reversedNumber = lotteryEngineV1.reverseTwoDigitUint8(number);
        assertEq(reversedNumber, expectedReversedNumber);
    }

    function testLEV1Version() public {
        assertEq(lotteryEngineV1.version(), 1);
    }
}
