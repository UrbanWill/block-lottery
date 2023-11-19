// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";

contract LotteryEngineV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using DataTypesLib for DataTypesLib.GameEntryFees;
    using DataTypesLib for DataTypesLib.GameDigits;
    using DataTypesLib for DataTypesLib.RoundStatus;

    ///////////////////////
    // State Variables   //
    ///////////////////////

    uint16 s_roundCounter = 0;
    uint256 s_totalTicketsSold = 0;
    mapping(uint16 round => DataTypesLib.RoundStatus roundStats) private s_roundStats;

    mapping(DataTypesLib.GameDigits => DataTypesLib.GameEntryFees) private s_gameEntryFees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    ////////////////////////////////////////
    // Modifiers                          //
    ////////////////////////////////////////

    modifier canOpenRound() {
        require(
            s_roundStats[s_roundCounter].status != DataTypesLib.GameStatus.Open
                && s_roundStats[s_roundCounter].status != DataTypesLib.GameStatus.Paused,
            "Round is not closed"
        );
        _;
    }

    ////////////////////////////////////////
    // Functions                          //
    ////////////////////////////////////////

    function initialize(address initialOwner, DataTypesLib.GameEntryFees calldata twoDigitGameFees)
        public
        initializer
    {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        s_gameEntryFees[DataTypesLib.GameDigits.Two] = twoDigitGameFees;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Creates a new round with open status
     */
    function createRound() public onlyOwner canOpenRound {
        s_roundCounter++;
        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Open;
    }

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

    function getCurrentRound() public view returns (uint16) {
        return s_roundCounter;
    }

    function getRoundStatus(uint16 round) public view returns (DataTypesLib.GameStatus) {
        return s_roundStats[round].status;
    }

    function version() public pure returns (uint8) {
        return 1;
    }
}
