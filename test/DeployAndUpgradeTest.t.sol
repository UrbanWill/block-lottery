// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {UpgradeLotteryEngine} from "../script/UpgradeLotteryEngine.s.sol";
import {UpgradeTicket} from "../script/UpgradeTicket.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {LotteryEngineV2} from "../src/LotteryEngineV2.sol";
import {TicketV1} from "../src/TicketV1.sol";
import {TicketV2} from "../src/TicketV2.sol";
import {DataTypesLib} from "../src/libraries/DataTypesLib.sol";

contract DeployAndUpgradeTest is StdCheats, Test {
    DeployLotteryEngine public deployLotteryEngine;
    UpgradeLotteryEngine public upgradeLotteryEngine;
    UpgradeTicket public upgradeTicket;

    address engineProxyAddress;
    address ticketProxyAddress;
    address owner;
    address USER = address(0x1);
    uint256[3] twoDigitGameFees;

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        upgradeLotteryEngine = new UpgradeLotteryEngine();
        upgradeTicket = new UpgradeTicket();
        (engineProxyAddress, ticketProxyAddress, owner, twoDigitGameFees) = deployLotteryEngine.run();
    }

    ///////////////////////
    // Deploy Tests      //
    ///////////////////////

    function testLotteryEngineV1Works() public {
        uint256 expectedValue = 1;
        assertEq(expectedValue, LotteryEngineV1(engineProxyAddress).version());
    }

    function testEngineDeploymentIsV1() public {
        uint256 expectedValue = 7;
        vm.expectRevert();
        LotteryEngineV2(engineProxyAddress).setValue(expectedValue);
    }

    function testTicketV1Works() public {
        uint256 expectedValue = 1;
        assertEq(expectedValue, TicketV1(ticketProxyAddress).version());
    }

    function testTicketDeploymentIsV1() public {
        TicketV1 ticketV1 = TicketV1(ticketProxyAddress);
        uint16 round = 1;
        DataTypesLib.GameDigits gameDigits = DataTypesLib.GameDigits.Two;
        DataTypesLib.GameEntryTier entryTier = DataTypesLib.GameEntryTier.One;
        uint8 number = 1;
        string memory uri = "test";

        vm.prank(engineProxyAddress);
        ticketV1.safeMint(USER, round, gameDigits, entryTier, number, uri);
        vm.expectRevert();
        TicketV2(ticketProxyAddress).updateTokenInfo(0, true);
    }

    ///////////////////////
    // Upgrade Tests     //
    ///////////////////////

    function testEngineUpgradeWorks() public {
        LotteryEngineV2 newLotteryEngineVersion = new LotteryEngineV2();
        LotteryEngineV2 lotteryEngineV2 = LotteryEngineV2(engineProxyAddress);
        upgradeLotteryEngine.upgradeLotteryEngine(engineProxyAddress, address(newLotteryEngineVersion));

        uint256 expectedValue = 2;
        assertEq(expectedValue, lotteryEngineV2.version());

        lotteryEngineV2.setValue(expectedValue);
        assertEq(expectedValue, lotteryEngineV2.getValue());
    }

    function testTicketUpgradeWorks() public {
        TicketV2 newTicketVersion = new TicketV2();
        TicketV2 ticketV2 = TicketV2(ticketProxyAddress);
        upgradeTicket.upgradeTicket(ticketProxyAddress, address(newTicketVersion));

        uint256 expectedValue = 2;
        assertEq(expectedValue, ticketV2.version());

        uint16 ROUND = 1;
        string memory MOCKED_URI = "test";

        vm.startPrank(engineProxyAddress);
        ticketV2.safeMint(USER, MOCKED_URI, ROUND);
        TicketV2(ticketProxyAddress).updateTokenInfo(0, true);
        vm.stopPrank();

        (bool claimed,,) = ticketV2.tokenInfo(0);
        assertEq(claimed, true);
    }

    ///////////////////////
    // Initializer Test  //
    ///////////////////////

    function testEngineV1OwnerIsSetCorrectly() public {
        address expectedValue = owner;
        assertEq(expectedValue, LotteryEngineV1(engineProxyAddress).owner());
    }

    function testEngineV1TicketAddressIsSetCorrectly() public {
        address expectedValue = ticketProxyAddress;
        assertEq(expectedValue, LotteryEngineV1(engineProxyAddress).s_ticketAddress());
    }
    /**
     * TODO:
     * Abosulutely test access control before shipping to prod
     */

    // function testTicketV1IsAccessControlSetCorrectly() public {
    //     bytes32 minterRole = TicketV1(ticketProxyAddress).MINTER_ROLE();
    //     assertEq(engineProxyAddress, address(uint160(uint256(minterRole))));
    // }

    function testEngineV1GameEntryFeesAreSetCorrectly() public {
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
}
