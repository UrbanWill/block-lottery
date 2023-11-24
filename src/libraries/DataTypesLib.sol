// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DataTypesLib {
    enum GameDigits {
        Two,
        Three // To be implemented in V2
    }

    enum GameType {
        Lower, // Two digits game will default to lower game type
        Upper,
        Reverse, // Lower Reverse
        UpperReverse
    }

    enum GameEntryTier {
        One,
        Two,
        Three
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
        uint8 lowerWinner;
        uint8 upperWinner;
        uint16 threeDigitsWinner;
        uint256 clamableAt;
        mapping(GameEntryTier => TwoDigitStatsPerTier) twoDigitStatsPerTier;
        mapping(GameEntryTier => ThreeDigitStatsPerTier) threeDigitStatsPerTier;
    }

    struct TwoDigitStatsPerTier {
        uint8 winnersClaimedCount;
        uint256 tierTicketCount;
        mapping(uint8 => uint16) ticketCountPerLowerNumber;
        mapping(uint8 => uint16) ticketCountPerUpperNumber;
    }

    struct ThreeDigitStatsPerTier {
        uint8 winnersClaimedCount;
        uint256 tierTicketCount;
        mapping(uint16 => uint16) ticketCountPerNumber;
    }

    struct FeePerTier {
        mapping(GameEntryTier => uint256 fee) feePerTier;
    }
}
