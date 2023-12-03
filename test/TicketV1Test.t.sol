// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {UpgradeLotteryEngine} from "../script/UpgradeLotteryEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";

contract TicketV1Test is StdCheats, Test {
    DeployLotteryEngine public deployLotteryEngine;
    TicketV1 public ticketV1;

    address engineProxyAddress; // MinterRole
    address ticketProxyAddress;

    address USER = address(0x1);

    uint16 constant ROUND = 1;
    DataTypesLib.GameDigits constant GAME_DIGITS = DataTypesLib.GameDigits.Two;
    DataTypesLib.GameEntryTier constant GAME_ENTRY_TIER = DataTypesLib.GameEntryTier.One;
    DataTypesLib.GameType constant GAME_TYPE = DataTypesLib.GameType.Lower;
    uint8 constant NUMBER = 1;
    uint8[] numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9];
    string constant URI = "test";

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        (engineProxyAddress, ticketProxyAddress,,,) = deployLotteryEngine.run();
        ticketV1 = TicketV1(ticketProxyAddress);
    }

    ////////////////////////////////////////
    // safeMint Tests                     //
    ////////////////////////////////////////

    function testTicketV1SafeMintRevertsNotMinterRole() public {
        vm.expectRevert();
        ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, numbers, URI);
    }

    function testTicketV1SafeMintWorks() public {
        vm.prank(engineProxyAddress);
        ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, numbers, URI);
        assertEq(ticketV1.ownerOf(0), USER);
    }

    function testTicketV1SafeMintSetTokenDataCorrectly() public {
        vm.prank(engineProxyAddress);
        uint256 tokenIdOne = ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, numbers, URI);

        (
            bool claimed,
            uint16 round,
            DataTypesLib.GameDigits gameDigits,
            DataTypesLib.GameType gameType,
            DataTypesLib.GameEntryTier entryTier,
            uint8[] memory ticketnumbers
        ) = ticketV1.getTokenInfo(tokenIdOne);
        string memory ticketIdOneUri = ticketV1.tokenURI(tokenIdOne);

        assertEq(claimed, false);
        assertEq(round, ROUND);
        assertEq(uint256(gameDigits), uint256(GAME_DIGITS));
        assertEq(uint256(gameType), uint256(GAME_TYPE));
        assertEq(uint256(entryTier), uint256(GAME_ENTRY_TIER));
        assertEq(abi.encodePacked(ticketnumbers), abi.encodePacked(numbers));
        assertEq(ticketIdOneUri, URI);

        string memory secondUri = "test2";
        uint8[] memory lowerNumbersTwo = new uint8[](1);
        lowerNumbersTwo[0] = 33;

        vm.prank(engineProxyAddress);
        uint256 tokenIdTwo =
            ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, lowerNumbersTwo, secondUri);

        (,,,,, uint8[] memory ticketLowerNumbersTwo) = ticketV1.getTokenInfo(tokenIdTwo);
        string memory ticketIdTwoUri = ticketV1.tokenURI(tokenIdTwo);

        assertEq(ticketIdTwoUri, secondUri);
        assertEq(abi.encodePacked(ticketLowerNumbersTwo), abi.encodePacked(lowerNumbersTwo));
    }

    ////////////////////////////////////////
    // setTicketClaimed Tests             //
    ////////////////////////////////////////

    function testTicketV1SetTicketClaimedRevertsNotMinterRole() public {
        vm.prank(engineProxyAddress);
        uint256 tokenId = ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, numbers, URI);

        vm.expectRevert();
        ticketV1.setTicketClaimed(tokenId);
    }

    function testTicketV1SetTicketClaimedWorks() public {
        vm.prank(engineProxyAddress);
        uint256 tokenId = ticketV1.safeMint(USER, ROUND, GAME_DIGITS, GAME_TYPE, GAME_ENTRY_TIER, numbers, URI);

        vm.prank(engineProxyAddress);
        ticketV1.setTicketClaimed(tokenId);
        (bool claimed,,,,) = ticketV1.tokenInfo(tokenId);
        assertEq(claimed, true);
    }
}
