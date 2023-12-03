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
    uint8 payoutFactor;

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
        (engineProxyAddress, ticketProxyAddress,,, payoutFactor) = deployLotteryEngine.run();
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
        uint8[] numbers,
        address player
    );
    event TicketClaimed(
        uint16 indexed round,
        DataTypesLib.GameDigits digits,
        DataTypesLib.GameType indexed gameType,
        DataTypesLib.GameEntryTier indexed tier,
        uint256 tokenId,
        uint256 winnings,
        address player
    );
    event EntryFeeChanged(
        DataTypesLib.GameDigits indexed digits, DataTypesLib.GameEntryTier indexed tier, uint256 indexed fee
    );
    event PayoutFactorChanged(uint8 indexed payoutFactor, uint256 timestamp);
    ////////////////////////////////////////
    // Modifiers & Helpers                //
    ////////////////////////////////////////

    modifier createNewRound() {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        _;
    }

    modifier buyNewTwoDigitsTicket() {
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 33;
        numbers[1] = 42;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, DataTypesLib.GameType.Lower, tier, numbers, PUG_URI);

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
        vm.expectEmit(true, false, false, false, engineProxyAddress);
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

    function testLEV1PostRoundResultsRoundIsClaimableWhenThereAreWinners()
        public
        createNewRound
        buyNewTwoDigitsTicket
    {
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
        buyNewTwoDigitsTicket
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
    // setGameEntryFee Tests              //
    ////////////////////////////////////////

    function testLEV1SetGameEntryFeeRevertsWhenNotOwner() public {
        uint256 gameFeeTierThree = 2 ether;

        vm.expectRevert();
        lotteryEngineV1.setGameEntryFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three, gameFeeTierThree);
    }

    function testLEV1SetGameEntryFeeRevertsWhenRoundOngoing() public createNewRound {
        uint256 gameFeeTierThree = 2 ether;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__CurrentRoundOngoing.selector);
        lotteryEngineV1.setGameEntryFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three, gameFeeTierThree);
    }

    function testLEV1SetGameEntryFeeRevertsWhenFeeIsZero() public {
        uint256 gameFeeTierThree = 0;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__InputCannotBeZero.selector);
        lotteryEngineV1.setGameEntryFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three, gameFeeTierThree);
    }

    function testLEV1SetGameEntryFeeUpdatesAndEmits(uint256 _tier) public {
        _tier = bound(_tier, 0, 2);

        uint256 updatedGameFee = 2 ether;
        uint256 expectedGameFee = updatedGameFee;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectEmit(true, true, true, false, engineProxyAddress);
        emit EntryFeeChanged(DataTypesLib.GameDigits.Two, tier, updatedGameFee);
        lotteryEngineV1.setGameEntryFee(DataTypesLib.GameDigits.Two, tier, updatedGameFee);

        uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, tier);
        assertEq(gameFee, expectedGameFee);
    }
    ////////////////////////////////////////
    // setGamePayoutFactor Tests          //
    ////////////////////////////////////////

    function testLEV1SetGamePayOutFactorRevertsWhenNotOwner() public {
        uint8 newPayoutFactor = 2;

        vm.expectRevert();
        lotteryEngineV1.setGamePayoutFactor(newPayoutFactor);
    }

    function testLEV1SetGamePayoutFactoRevertsWhenGameIsOngoing() public createNewRound {
        uint8 newPayoutFactor = 2;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__CurrentRoundOngoing.selector);
        lotteryEngineV1.setGamePayoutFactor(newPayoutFactor);
    }

    function testLEV1SetGamePayoutFactorRevertsIfInputIsZero() public {
        uint8 newPayoutFactor = 0;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__InputCannotBeZero.selector);
        lotteryEngineV1.setGamePayoutFactor(newPayoutFactor);
    }

    function testLEV1SeGamePayoutFactorUpdatesAndEmits(uint8 newPayoutFactor) public {
        newPayoutFactor = uint8(bound(newPayoutFactor, 1, 99));
        uint8 expectedPayoutFactor = newPayoutFactor;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectEmit(true, true, true, false, engineProxyAddress);
        emit PayoutFactorChanged(newPayoutFactor, block.timestamp);
        lotteryEngineV1.setGamePayoutFactor(newPayoutFactor);

        uint8 gamePayoutFactor = lotteryEngineV1.getPayoutFactor();
        assertEq(gamePayoutFactor, expectedPayoutFactor);
    }

    ////////////////////////////////////////
    // withdrawl Tests                    //
    ////////////////////////////////////////

    function testLEV1WithdrawRevertsWhenNotOwner() public {
        vm.expectRevert();
        lotteryEngineV1.withdraw(LOTTERY_OWNER, 1 ether);
    }

    function testLEV1WithdrawRevertsWhenAmountBiggerThanDebt() public createNewRound buyNewTwoDigitsTicket {
        uint8 lowerWinner = 33; // Winning number
        uint8 upperWinner = 98;
        uint256 lotteryEngineBalance = address(engineProxyAddress).balance;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__AmountMustBeLessThanTotalUnclaimedWinnings.selector);
        lotteryEngineV1.withdraw(LOTTERY_OWNER, lotteryEngineBalance);
    }

    function testLEV1WithdrawRevertsWhenRoundIsOngoing() public createNewRound {
        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__CurrentRoundOngoing.selector);
        lotteryEngineV1.withdraw(LOTTERY_OWNER, 1 ether);
    }

    function testLEV1WithdrawWorks() public createNewRound buyNewTwoDigitsTicket {
        uint8 lowerWinner = 99;
        uint8 upperWinner = 98;

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
    // buyTwoDigitsTicket Tests           //
    ////////////////////////////////////////

    function testLEV1BuyTwoDigitsRevertsWhenRoundIsNotOpen() public {
        uint16 round = 1;
        uint8[] memory numbers;
        vm.prank(USER);
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: 3 ether}(
            round, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
    }

    function testLEV1BuyTwoDigitsRevertsWhenRoundIsPaused() public createNewRound {
        uint16 round = 1;
        uint8[] memory numbers;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeOpen.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: 3 ether}(
            round, DataTypesLib.GameType.Lower, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
    }

    function testLEV1BuyTwoDigitsRevertsWhenTierFeeIsIncorrect(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint8[] memory numbers;
        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;
        uint256 incorrectAmount = gameFee + 1;

        vm.expectRevert(LotteryEngineV1.LotteryEngine__IncorrectTierFee.selector);
        lotteryEngineV1.buyTwoDigitsTicket{value: incorrectAmount}(
            round, DataTypesLib.GameType.Lower, tier, numbers, PUG_URI
        );
    }

    // function testLEV1BuyTwoDigitsRevertIfGameDigitsIsTwoAndNumberIsOutOfRange(uint8 numberAboveRange)
    //     public
    //     createNewRound
    // {
    //     numberAboveRange = uint8(bound(numberAboveRange, 100, 255));
    //     uint16 round = 1;
    //     uint8 numberBelowRange = 0;
    //     uint256 gameFee = lotteryEngineV1.getGameFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

    //     vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
    //     lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
    //         round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.One, numberAboveRange, PUG_URI
    //     );
    //     vm.expectRevert(LotteryEngineV1.LotteryEngine__NumberOutOfRange.selector);
    //     lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
    //         round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.One, numberBelowRange, PUG_URI
    //     );
    // }

    function testLEV1BuyTwoDigitsUpdatesRoundStatsAndEmits(uint256 _gameType, uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 1);

        uint16 round = 1;

        uint256 expectedNumberSold = 1;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 33;
        numbers[1] = 22;

        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 totalNumbersCount = numbers.length;
        uint256 expectedTicketsSold = totalNumbersCount;
        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * totalNumbersCount;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
            expectedTicketsSold = expectedTicketsSold * 2;
        }

        uint256 initialBalance = address(engineProxyAddress).balance;
        uint256 expectedBalance = initialBalance + gameFee;

        vm.prank(USER);
        vm.expectEmit(true, true, true, true, engineProxyAddress);
        emit TicketBought(round, DataTypesLib.GameDigits.Two, gameType, tier, numbers, USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);

        assertEq(lotteryEngineV1.getTierTicketCountSoldPerRound(round, tier), expectedTicketsSold);
        assertEq(lotteryEngineV1.getTwoDigitsNumberCountPerType(round, gameType, tier, numbers[0]), expectedNumberSold);
        assertEq(lotteryEngineV1.getTwoDigitsNumberCountPerType(round, gameType, tier, numbers[1]), expectedNumberSold);
        assertEq(address(engineProxyAddress).balance, expectedBalance);
    }

    function testLEV1BuyTwoDigitsMintsNft(uint256 _gameType, uint256 _tier, uint8[] calldata numbers)
        public
        createNewRound
    {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 1);
        vm.assume(numbers.length < 99);

        uint16 round = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
        }

        startMeasuringGas("buyTicket gas:");
        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        stopMeasuringGas();

        assertEq(ticketV1.ownerOf(0), USER);
    }

    // uint8[] numbersTest = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25];

    // function testLEV1BuyTwoDigitsMintsNftGasCalc(uint256 _tier) public createNewRound {
    //     _tier = bound(_tier, 0, 2);

    //     uint16 round = 1;
    //     DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;
    //     DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
    //     uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
    //     uint256 gameFee = tierFee * numbersTest.length * 2;

    //     startMeasuringGas("buyTicket gas:");
    //     vm.prank(USER);
    //     lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbersTest, PUG_URI);
    //     stopMeasuringGas();

    //     assertEq(ticketV1.ownerOf(0), USER);
    // }
    ////////////////////////////////////////
    // claimWinnings Tests                //
    ////////////////////////////////////////

    function testLEV1ClaimWinningsRevertsWhenRoundIsNotClaimable() public createNewRound {
        uint256 tokenId = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(59 minutes);
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeClaimable.selector);
        lotteryEngineV1.claimWinnings(tokenId);
    }

    function testLEV1ClaimWinningsRevertsWhenNotTicketOwner() public createNewRound buyNewTwoDigitsTicket {
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

    function testLEV1ClaimWinningsRevertsWhenTicketAlreadyClaimed() public createNewRound buyNewTwoDigitsTicket {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        // Buys one more winning ticket to prevent the round from closing when the only winner claims their ticket
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 33;
        numbers[1] = 42;

        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.One;

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, DataTypesLib.GameType.Lower, tier, numbers, PUG_URI);

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

    function testLEV1ClaimWinningsClosesAndEmiitsRoundWhenLastWinnerClaims()
        public
        createNewRound
        buyNewTwoDigitsTicket
    {
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 50;
        DataTypesLib.GameStatus expectedStatus = DataTypesLib.GameStatus.Closed;
        uint16 winnersCount = 3;
        uint16 claimedCount = 3;

        // Buys one more winning ticket
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 37;
        numbers[1] = upperWinner;

        uint16 round = 1;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.Three;

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length * 2;

        vm.prank(USER);
        uint256 tokenIdTwo = lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Upper, tier, numbers, PUG_URI
        );

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokenId);

        vm.warp(2 hours);
        vm.startPrank(USER);
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundClosed(round, winnersCount, claimedCount, block.timestamp);
        lotteryEngineV1.claimWinnings(tokenIdTwo);

        (DataTypesLib.GameStatus status,,,,) = lotteryEngineV1.getRoundInfo(1);

        assertEq(uint256(status), uint256(expectedStatus));
    }

    function testLEV1ClaimWinningsUpdatesWinnersClaimedCount() public createNewRound buyNewTwoDigitsTicket {
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

    function testLEV1ClaimWinningsPaysAndEmits() public createNewRound buyNewTwoDigitsTicket {
        uint16 round = 1;
        uint256 tokenId = 0;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint256 expectedWinnings = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * lotteryEngineV1.getPayoutFactor();
        uint256 expectedBalance = address(USER).balance + expectedWinnings;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);
        vm.startPrank(USER);
        vm.expectEmit(true, true, false, true, engineProxyAddress);

        emit TicketClaimed(
            round,
            DataTypesLib.GameDigits.Two,
            DataTypesLib.GameType.Lower,
            DataTypesLib.GameEntryTier.One,
            tokenId,
            expectedWinnings,
            USER
        );
        lotteryEngineV1.claimWinnings(tokenId);
        vm.stopPrank();

        assertEq(address(USER).balance, expectedBalance);
    }

    function testLEV1ClaimWinningsDoesNotPayWhenNotWinner() public createNewRound buyNewTwoDigitsTicket {
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint16 round = 1;
        // Buys a ticket that is not a winner
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 37;
        numbers[1] = 42;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier.Three;

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;

        vm.prank(USER);
        uint256 loserTokenId = lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Lower, tier, numbers, PUG_URI
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

    function testLEV1GetPayoutPerTier(uint256 _tier) public {
        _tier = bound(_tier, 0, 2);

        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 expectedPayout =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier) * lotteryEngineV1.getPayoutFactor();

        assertEq(lotteryEngineV1.getPayoutPerTier(DataTypesLib.GameDigits.Two, tier), expectedPayout);
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

    function testLEV1GetTierWinnersClaimedPerRound(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;
        uint256 expectedWinnersClaimedCount = 2;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
            expectedWinnersClaimedCount = expectedWinnersClaimedCount * 2;
        }

        vm.startPrank(USER);
        uint256 tokendIdOne =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        uint256 tokendIdTwo =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);

        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokendIdOne);
        lotteryEngineV1.claimWinnings(tokendIdTwo);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTierWinnersClaimedPerRound(round, tier), expectedWinnersClaimedCount);
    }

    function testLEV1getTotalWinnersClaimedPerRound(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;

        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Lower;
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;
        uint256 expectedWinnersClaimedCount = 2;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
            expectedWinnersClaimedCount = expectedWinnersClaimedCount * 2;
        }

        vm.startPrank(USER);
        uint256 tokendIdOne =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        uint256 tokendIdTwo =
            lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        vm.warp(61 minutes);

        vm.startPrank(USER);
        lotteryEngineV1.claimWinnings(tokendIdOne);
        lotteryEngineV1.claimWinnings(tokendIdTwo);
        vm.stopPrank();

        assertEq(lotteryEngineV1.getTotalWinnersClaimedPerRound(round), expectedWinnersClaimedCount);
    }

    function testLEV1GetTierWinnerCountPerRound(uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);

        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;

        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;
        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length * 2;

        vm.startPrank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 tierTicketCount = 3;
        uint256 winnerNumbersPerTicket = 2;
        uint256 expectedWinnersCount = tierTicketCount * winnerNumbersPerTicket;

        assertEq(lotteryEngineV1.getTierWinnerCountPerRound(round, tier), expectedWinnersCount);
    }

    function testLEV1GetTotalWinnersCountPerRound() public createNewRound {
        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;
        uint256 totalNumbersCount = numbers.length * 2;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;

        uint256 tierOneGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * totalNumbersCount;
        uint256 tierTwoGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two
        ) * totalNumbersCount;
        uint256 tierThreeGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three
        ) * totalNumbersCount;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, numbers, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 tierOneTicketCount = 2;
        uint256 tierTwoTicketCount = 1;
        uint256 tierThreeTicketCount = 3;
        uint256 winnerNumbersPerTicket = 2;
        uint256 expectedWinnersCount =
            (tierOneTicketCount + tierTwoTicketCount + tierThreeTicketCount) * winnerNumbersPerTicket;

        assertEq(lotteryEngineV1.getTotalWinnersCountPerRound(round), expectedWinnersCount);
    }

    function testLEV1GetUnclaimedWinningsPerTierAndRound() public createNewRound {
        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;
        uint256 totalNumbersCount = numbers.length * 2;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;

        uint256 tierOneGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * totalNumbersCount;
        uint256 tierTwoGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two
        ) * totalNumbersCount;
        uint256 tierThreeGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three
        ) * totalNumbersCount;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, numbers, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 winningTierOneTicketCount = 4; // 2 tickets * 2 wining numbers (upper and lower) per ticket = 4
        uint256 winningTierTwoTicketCount = 2;
        uint256 winningTierThreeTicketCount = 6;
        uint256 expectedUnclaimedTierOne = winningTierOneTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierTwo = winningTierTwoTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierThree = winningTierThreeTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three)
                    * lotteryEngineV1.getPayoutFactor()
            );

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
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;
        uint256 totalNumbersCount = numbers.length * 2;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;

        uint256 tierOneGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * totalNumbersCount;
        uint256 tierTwoGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two
        ) * totalNumbersCount;
        uint256 tierThreeGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three
        ) * totalNumbersCount;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, numbers, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 winningTierOneTicketCount = 4; // 2 tickets * 2 wining numbers (upper and lower) per ticket = 4
        uint256 winningTierTwoTicketCount = 2;
        uint256 winningTierThreeTicketCount = 6;
        uint256 expectedUnclaimedTierOne = winningTierOneTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierTwo = winningTierTwoTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierThree = winningTierThreeTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three)
                    * lotteryEngineV1.getPayoutFactor()
            );

        uint256 expectedTotalUnclaimed =
            expectedUnclaimedTierOne + expectedUnclaimedTierTwo + expectedUnclaimedTierThree;

        assertEq(lotteryEngineV1.getTotalUnclaimedWinningsPerRound(round), expectedTotalUnclaimed);
    }

    function testLEV1GetTotalUnclaimedWinnings() public createNewRound {
        uint16 round = 1;
        uint8 lowerWinner = 33;
        uint8 upperWinner = 98;
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;
        uint256 totalNumbersCount = numbers.length * 2;

        DataTypesLib.GameType gameType = DataTypesLib.GameType.Upper;

        uint256 tierOneGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One
        ) * totalNumbersCount;
        uint256 tierTwoGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two
        ) * totalNumbersCount;
        uint256 tierThreeGameFee = lotteryEngineV1.getGameTokenAmountFee(
            DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three
        ) * totalNumbersCount;

        vm.startPrank(USER);
        // Buys 2 tier One tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );
        // Buys 1 tier Two ticket
        lotteryEngineV1.buyTwoDigitsTicket{value: tierTwoGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Two, numbers, PUG_URI
        );
        // Buyst 3 tier Three tickets
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        lotteryEngineV1.buyTwoDigitsTicket{value: tierThreeGameFee}(
            round, gameType, DataTypesLib.GameEntryTier.Three, numbers, PUG_URI
        );
        vm.stopPrank();

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        lotteryEngineV1.createRound();
        vm.stopPrank();

        uint16 roundTwo = 2;
        uint256 winningTierOneTicketCountRoundTwo = 2;
        uint256 expectedUnclaimedTierOneRoundTwo = winningTierOneTicketCountRoundTwo
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One)
                    * lotteryEngineV1.getPayoutFactor()
            );

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: tierOneGameFee}(
            roundTwo, gameType, DataTypesLib.GameEntryTier.One, numbers, PUG_URI
        );

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 winningTierOneTicketCount = 4; // 2 tickets * 2 wining numbers (upper and lower) per ticket = 4
        uint256 winningTierTwoTicketCount = 2;
        uint256 winningTierThreeTicketCount = 6;
        uint256 expectedUnclaimedTierOne = winningTierOneTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierTwo = winningTierTwoTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Two)
                    * lotteryEngineV1.getPayoutFactor()
            );
        uint256 expectedUnclaimedTierThree = winningTierThreeTicketCount
            * (
                lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.Three)
                    * lotteryEngineV1.getPayoutFactor()
            );

        uint256 totalUnclaimedRoundOne =
            expectedUnclaimedTierOne + expectedUnclaimedTierTwo + expectedUnclaimedTierThree;

        uint256 expectedTotalUnclaimed = totalUnclaimedRoundOne + expectedUnclaimedTierOneRoundTwo;

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

    function testLEV1GetPayoutFactor() public {
        assertEq(LotteryEngineV1(engineProxyAddress).getPayoutFactor(), payoutFactor);
    }

    function testLEVGetTicketInfoReturnsIsWinnerTrue(uint256 _gameType, uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 1);

        uint16 round = 1;
        uint8 lowerWinner = 27;
        uint8 upperWinner = 72;

        uint8[] memory numbers = new uint8[](2);
        numbers[0] = lowerWinner;
        numbers[1] = upperWinner;

        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;
        uint8 expectedWinCount = 1;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
            expectedWinCount = 2;
        }

        vm.prank(USER);
        uint256 tokenId = lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 expectedTicketPayOut = expectedWinCount * tierFee * lotteryEngineV1.getPayoutFactor();

        (,,,,,, uint256 ticketWinCount,, uint256 ticketPayout) = lotteryEngineV1.getTicketInfo(tokenId);

        assertEq(ticketWinCount, expectedWinCount);
        assertEq(ticketPayout, expectedTicketPayOut);
    }

    function testLEVGetTicketInfoReturnsIsWinnerFalse(uint256 _gameType, uint256 _tier) public createNewRound {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 1);

        uint16 round = 1;
        uint8 lowerWinner = 27;
        uint8 upperWinner = 72;

        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 33;
        numbers[1] = 18;

        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);

        uint256 tierFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);
        uint256 gameFee = tierFee * numbers.length;

        if (gameType == DataTypesLib.GameType.Upper) {
            gameFee = gameFee * 2;
        }

        vm.prank(USER);
        uint256 tokenId = lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, numbers, PUG_URI);

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(lowerWinner, upperWinner);
        vm.stopPrank();

        uint256 expectedTicketPayOut = 0;
        uint8 expectedWinCount = 0;

        (,,,,,, uint256 ticketWinCount,, uint256 ticketPayout) = lotteryEngineV1.getTicketInfo(tokenId);

        assertEq(expectedWinCount, ticketWinCount);
        assertEq(ticketPayout, expectedTicketPayOut);
    }

    function testLEV1Version() public {
        assertEq(lotteryEngineV1.version(), 1);
    }
}
