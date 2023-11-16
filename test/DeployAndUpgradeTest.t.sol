// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployLotteryEngine} from "../script/DeployLotteryEngine.s.sol";
import {UpgradeLotteryEngine} from "../script/UpgradeLotteryEngine.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LotteryEngineV1} from "../src/LotteryEngineV1.sol";
import {LotteryEngineV2} from "../src/LotteryEngineV2.sol";

contract DeployAndUpgradeTest is StdCheats, Test {
    DeployLotteryEngine public deployLotteryEngine;
    UpgradeLotteryEngine public upgradeLotteryEngine;
    address public OWNER = address(1);

    function setUp() public {
        deployLotteryEngine = new DeployLotteryEngine();
        upgradeLotteryEngine = new UpgradeLotteryEngine();
    }

    function testLotteryEngineV1Works() public {
        (address engineProxyAddress,) = deployLotteryEngine.deployLotteryEngine();
        uint256 expectedValue = 1;
        assertEq(expectedValue, LotteryEngineV1(engineProxyAddress).version());
    }

    function testTicketV1Works() public {
        (, address ticketProxyAddress) = deployLotteryEngine.deployLotteryEngine();
        uint256 expectedValue = 1;
        assertEq(expectedValue, LotteryEngineV1(ticketProxyAddress).version());
    }

    function testDeploymentIsV1() public {
        (address engineProxyAddress,) = deployLotteryEngine.deployLotteryEngine();
        uint256 expectedValue = 7;
        vm.expectRevert();
        LotteryEngineV2(engineProxyAddress).setValue(expectedValue);
    }

    function testEngineUpgradeWorks() public {
        (address engineProxyAddress,) = deployLotteryEngine.deployLotteryEngine();
        LotteryEngineV2 LEV2 = new LotteryEngineV2();
        address engineProxy = upgradeLotteryEngine.upgradeLotteryEngine(engineProxyAddress, address(LEV2));

        uint256 expectedValue = 2;
        assertEq(expectedValue, LotteryEngineV2(engineProxy).version());

        LotteryEngineV2(engineProxy).setValue(expectedValue);
        assertEq(expectedValue, LotteryEngineV2(engineProxy).getValue());
    }
}
