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

    uint256 ethUsdOraclePrice = 2000;
    uint16 CLAIMABLE_DELAY = 1 hours;

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

    event RoundCreated(uint16 indexed round, uint256 timestamp);
    event RoundPaused(uint16 indexed round, uint256 timestamp);
    event RoundReultsPosted(uint16 indexed round, uint256 timestamp);
    event RoundReultsAmended(uint16 indexed round, uint8 twoDigitsWinnerNumber, uint256 timestamp);
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
        (DataTypesLib.GameStatus status,,,) = lotteryEngineV1.getRoundInfo(1);
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

        (DataTypesLib.GameStatus status,,,) = lotteryEngineV1.getRoundInfo(1);

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
        uint8 twoDigitNumber = 33;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBePaused.selector);
        lotteryEngineV1.postRoundResults(twoDigitNumber);
    }

    function testLEV1PostRoundResultsUpdatesRoundStatusAndEmits(uint8 twoDigitNumber) public createNewRound {
        twoDigitNumber = uint8(bound(twoDigitNumber, 1, 99));
        uint16 round = 1;
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Claimable);
        uint256 expectedClaimableAt = block.timestamp + CLAIMABLE_DELAY;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();

        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundReultsPosted(round, block.timestamp);
        lotteryEngineV1.postRoundResults(twoDigitNumber);
        vm.stopPrank();

        (DataTypesLib.GameStatus status, uint8 twoDigitsWinnerNumber,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(twoDigitsWinnerNumber, twoDigitNumber);
        assertEq(claimableAt, expectedClaimableAt);
    }

    function testLEV1PostRoundResultsUpdatesCorrectRound(uint8 twoDigitWinnerNumber) public createNewRound {
        twoDigitWinnerNumber = uint8(bound(twoDigitWinnerNumber, 1, 99));
        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Claimable);

        // Creates and closes a phony round 1, a bit repetitive but it's the only way to test this.
        // Consider refactoring this in the future in favour of invariant testing.
        uint8 roundOneWinner = 22;

        uint256 expectedRoundOneClaimableAt = block.timestamp + CLAIMABLE_DELAY;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(roundOneWinner);
        vm.stopPrank();

        // Round one assertions:
        (DataTypesLib.GameStatus statusRoundOne, uint8 twoDigitsWinnerNumberRoundOne,, uint256 claimableAtRoundOne) =
            lotteryEngineV1.getRoundInfo(1);
        uint256 roundOneStatus = uint256(statusRoundOne);

        assertEq(roundOneStatus, expectedStatus);
        assertEq(twoDigitsWinnerNumberRoundOne, roundOneWinner);
        assertEq(claimableAtRoundOne, expectedRoundOneClaimableAt);

        // Creates and closes round 2
        vm.warp(100);
        uint16 roundTwo = 2;
        uint256 expectedClaimableAt = block.timestamp + CLAIMABLE_DELAY;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.createRound();
        lotteryEngineV1.pauseRound();

        lotteryEngineV1.postRoundResults(twoDigitWinnerNumber);
        vm.stopPrank();

        // Round two assertions:
        (DataTypesLib.GameStatus status, uint8 twoDigitsWinnerNumber,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(roundTwo);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(twoDigitsWinnerNumber, twoDigitWinnerNumber);
        assertEq(claimableAt, expectedClaimableAt);
    }

    ////////////////////////////////////////
    // amendRoundResults Tests            //
    ////////////////////////////////////////

    function testLEV1AmendRoundResultsRevertsNotOwner() public createNewRound {
        uint8 amendedTwoDigitNumber = 33;

        vm.expectRevert();
        lotteryEngineV1.amendRoundResults(amendedTwoDigitNumber);
    }

    function testLEV1AmendRoundResultsRevertsWhenRoundIsNotClaimable() public createNewRound {
        uint8 amendedTwoDigitNumber = 33;

        vm.prank(LotteryEngineV1(engineProxyAddress).owner());
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundMustBeClaimable.selector);
        lotteryEngineV1.amendRoundResults(amendedTwoDigitNumber);
    }

    function testLEV1AmendResultsRevertWhenNotOnTime() public createNewRound {
        uint8 twoDigitNumber = 99;
        uint8 amendedTwoDigitNumber = 33;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(twoDigitNumber);
        vm.warp(61 minutes);
        vm.expectRevert(LotteryEngineV1.LotteryEngine__RoundResultAmendMustBeWithinTime.selector);
        lotteryEngineV1.amendRoundResults(amendedTwoDigitNumber);
        vm.stopPrank();
    }

    function testLEV1AmendResultsUpdatesStorageAndEmits() public createNewRound {
        uint8 twoDigitNumber = 99;
        uint8 amendedTwoDigitNumber = 33;
        uint16 round = 1;
        uint256 warpTime = 59 minutes;

        uint256 expectedStatus = uint256(DataTypesLib.GameStatus.Claimable);
        uint256 expectedClaimableAt = block.timestamp + warpTime + CLAIMABLE_DELAY - 1;

        vm.startPrank(LotteryEngineV1(engineProxyAddress).owner());
        lotteryEngineV1.pauseRound();
        lotteryEngineV1.postRoundResults(twoDigitNumber);
        vm.warp(59 minutes);
        vm.expectEmit(true, true, false, false, engineProxyAddress);
        emit RoundReultsAmended(round, amendedTwoDigitNumber, block.timestamp);
        lotteryEngineV1.amendRoundResults(amendedTwoDigitNumber);
        vm.stopPrank();

        (DataTypesLib.GameStatus status, uint8 twoDigitsWinnerNumber,, uint256 claimableAt) =
            lotteryEngineV1.getRoundInfo(round);
        uint256 roundStatus = uint256(status);

        assertEq(roundStatus, expectedStatus);
        assertEq(twoDigitsWinnerNumber, amendedTwoDigitNumber);
        assertEq(claimableAt, expectedClaimableAt);
    }

    ////////////////////////////////////////
    // buyTwoDigits Tests                    //
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

    function testLEV1BuyTwoDigitsUpdatesRoundStatsAndEmits(uint256 _gameType, uint256 _tier, uint256 number)
        public
        createNewRound
    {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 2);
        number = bound(number, 1, 99);

        uint16 round = 1;
        uint256 expectedTicketSold = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        vm.prank(USER);
        vm.expectEmit(true, true, true, true, engineProxyAddress);
        emit TicketBought(round, tier, uint8(number), USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);

        assertEq(lotteryEngineV1.getTierTicketCountSoldPerRound(round, tier), expectedTicketSold);
        assertEq(lotteryEngineV1.getTierNumberSoldCountPerRound(round, tier, uint8(number)), expectedTicketSold);

        assertEq(address(engineProxyAddress).balance, gameFee);
    }

    function testLEV1BuyTwoDigitsOnlyUpdatesCorrectRoundStats(uint256 number) public createNewRound {
        number = bound(number, 1, 99);

        uint256 expectedTicketSold = 0;
        uint16 round = 1;
        uint256 gameFee =
            lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, DataTypesLib.GameEntryTier.One);

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(
            round, DataTypesLib.GameType.Reverse, DataTypesLib.GameEntryTier.One, uint8(number), PUG_URI
        );

        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Two), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierTicketCountSoldPerRound(round, DataTypesLib.GameEntryTier.Three), expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.Two, uint8(number)),
            expectedTicketSold
        );
        assertEq(
            lotteryEngineV1.getTierNumberSoldCountPerRound(round, DataTypesLib.GameEntryTier.Three, uint8(number)),
            expectedTicketSold
        );
    }

    function testLEV1BuyTwoDigitsMintsNft(uint256 _gameType, uint256 _tier, uint256 number) public createNewRound {
        _tier = bound(_tier, 0, 2);
        _gameType = bound(_gameType, 0, 2);
        number = bound(number, 1, 99);

        uint16 round = 1;
        DataTypesLib.GameType gameType = DataTypesLib.GameType(_gameType);
        DataTypesLib.GameEntryTier tier = DataTypesLib.GameEntryTier(_tier);
        uint256 gameFee = lotteryEngineV1.getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier);

        vm.prank(USER);
        lotteryEngineV1.buyTwoDigitsTicket{value: gameFee}(round, gameType, tier, uint8(number), PUG_URI);

        assertEq(ticketV1.ownerOf(0), USER);
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
}
