// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";

contract LotteryEngineV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////
    // State Variables                    //
    ////////////////////////////////////////

    uint16 s_roundCounter = 0;
    uint256 public s_totalTicketsSold = 0;
    mapping(DataTypesLib.GameDigits => DataTypesLib.FeePerTier) private s_gameEntryFees;

    mapping(uint16 round => DataTypesLib.RoundStatus roundStats) public s_roundStats;

    ////////////////////////////////////////
    // Events                             //
    ////////////////////////////////////////

    event TicketBought(
        uint16 indexed round, DataTypesLib.GameEntryTier indexed tier, uint8 indexed number, address player
    );

    ////////////////////////////////////////
    // Errors                             //
    ////////////////////////////////////////

    error LotteryEngine__CurrentRoundOngoing();
    error LotteryEngine__RoundMustBeOpen();
    ////////////////////////////////////////
    // Modifiers                          //
    ////////////////////////////////////////

    modifier canOpenRound() {
        if (
            s_roundStats[s_roundCounter].status == DataTypesLib.GameStatus.Open
                || s_roundStats[s_roundCounter].status == DataTypesLib.GameStatus.Paused
        ) {
            revert LotteryEngine__CurrentRoundOngoing();
        }
        _;
    }

    modifier roundMustBeOpen(uint16 round) {
        if (s_roundStats[round].status != DataTypesLib.GameStatus.Open) {
            revert LotteryEngine__RoundMustBeOpen();
        }
        _;
    }

    ////////////////////////////////////////
    // Functions                          //
    ////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, uint256[3] memory _twoDigitGameFees) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.One] = _twoDigitGameFees[0];
        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.Two] = _twoDigitGameFees[1];
        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.Three] = _twoDigitGameFees[2];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Creates a new round with open status
     */
    function createRound() public onlyOwner canOpenRound {
        s_roundCounter++;
        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Open;
    }

    /**
     * @notice Buy a ticket for a given round
     * @param round Round number
     * @param tier Tier price of the game
     * @param number Number to bet on
     */
    function buyTicket(uint16 round, DataTypesLib.GameEntryTier tier, uint8 number) public roundMustBeOpen(round) {
        // require(msg.value == s_gameEntryFees[DataTypesLib.GameDigits.Two].One, "Incorrect entry fee");

        s_totalTicketsSold++;
        s_roundStats[round].statsPerGameTier[tier].tierTicketCount++;
        s_roundStats[round].statsPerGameTier[tier].ticketCountPerNumber[number]++;

        emit TicketBought(round, tier, number, msg.sender);
    }

    ////////////////////////////////////////
    // Public & External View Functions   //
    ////////////////////////////////////////

    function getCurrentRound() public view returns (uint16) {
        return s_roundCounter;
    }

    function getRoundStatus(uint16 round) public view returns (DataTypesLib.GameStatus) {
        return s_roundStats[round].status;
    }

    /**
     * @param round Round number
     * @param tier Tier price of the game
     * @return Total number of tickets sold for a given tier in that round
     */
    function getTierTicketCountSoldPerRound(uint16 round, DataTypesLib.GameEntryTier tier)
        public
        view
        returns (uint256)
    {
        return s_roundStats[round].statsPerGameTier[tier].tierTicketCount;
    }

    function getTierNumberSoldCountPerRound(uint16 round, DataTypesLib.GameEntryTier tier, uint8 number)
        public
        view
        returns (uint256)
    {
        return s_roundStats[round].statsPerGameTier[tier].ticketCountPerNumber[number];
    }

    /**
     * @param gameDigit Digits of the game, currently only 2 digits is supported
     * @param gameEntryTier Tier of the game, maps to the entry fee
     */
    function getGameFee(DataTypesLib.GameDigits gameDigit, DataTypesLib.GameEntryTier gameEntryTier)
        public
        view
        returns (uint256)
    {
        return s_gameEntryFees[gameDigit].feePerTier[gameEntryTier];
    }

    function version() public pure returns (uint8) {
        return 1;
    }
}
