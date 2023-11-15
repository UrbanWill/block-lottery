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
        address proxyAddress = deployLotteryEngine.deployLotteryEngine();
        uint256 expectedValue = 1;
        assertEq(expectedValue, LotteryEngineV1(proxyAddress).version());
    }

    function testDeploymentIsV1() public {
        address proxyAddress = deployLotteryEngine.deployLotteryEngine();
        uint256 expectedValue = 7;
        vm.expectRevert();
        LotteryEngineV2(proxyAddress).setValue(expectedValue);
    }

    function testUpgradeWorks() public {
        address proxyAddress = deployLotteryEngine.deployLotteryEngine();
        LotteryEngineV2 LEV2 = new LotteryEngineV2();
        address proxy = upgradeLotteryEngine.upgradeLotteryEngine(proxyAddress, address(LEV2));

        uint256 expectedValue = 2;
        assertEq(expectedValue, LotteryEngineV2(proxy).version());

        LotteryEngineV2(proxy).setValue(expectedValue);
        assertEq(expectedValue, LotteryEngineV2(proxy).getValue());
    }
}
