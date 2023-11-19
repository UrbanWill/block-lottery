// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DataTypesLib {
    enum GameDigits {
        Two,
        Three // To be implemented in V2
    }

    enum TwoDigitGameType {
        Lower, // Two digits game will default to lower game type
        Upper
    }

    enum GameStatus {
        Closed,
        Paused,
        Cancelled,
        Open,
        Claimable
    }

    struct RoundStatus {
        GameStatus status;
        bool hasWinners;
        TwoDigitGameStats lowerGameStats;
        TwoDigitGameStats reverseGameStats;
    }

    struct GameEntryFees {
        uint256 One;
        uint256 Two;
        uint256 Three;
    }

    struct TwoDigitGameStats {
        uint256 totalTicketsSold;
        mapping(uint8 ticketNumber => uint256 ticketCount) ticketCountPerNumber;
    }
    // add more stats per GameEntryFees
}
