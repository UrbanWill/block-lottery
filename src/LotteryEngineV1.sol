// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";

contract LotteryEngineV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using DataTypesLib for DataTypesLib.GameEntryFees;
    using DataTypesLib for DataTypesLib.GameDigits;

    ///////////////////////
    // State Variables   //
    ///////////////////////

    mapping(DataTypesLib.GameDigits => DataTypesLib.GameEntryFees) private s_gameEntryFees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, DataTypesLib.GameEntryFees calldata twoDigitGameFees)
        public
        initializer
    {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        s_gameEntryFees[DataTypesLib.GameDigits.Two] = twoDigitGameFees;
    }

    function version() public pure returns (uint8) {
        return 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    ////////////////////////////////////////
    // Public & External View Functions   //
    ////////////////////////////////////////

    function getGameEntryFee(DataTypesLib.GameDigits gameDigit)
        public
        view
        returns (DataTypesLib.GameEntryFees memory)
    {
        return s_gameEntryFees[gameDigit];
    }
}
