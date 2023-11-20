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
        mapping(GameEntryTier => StatsPerGameTier) statsPerGameTier;
        uint8 winnerNumber;
    }

    struct StatsPerGameTier {
        uint256 tierTicketCount;
        mapping(uint8 => uint256) ticketCountPerNumber;
        uint8 winnerCount;
        uint8 winnersClaimedCount;
    }

    enum GameEntryTier {
        One,
        Two,
        Three
    }

    struct FeePerTier {
        mapping(GameEntryTier => uint256 fee) feePerTier;
    }
}
