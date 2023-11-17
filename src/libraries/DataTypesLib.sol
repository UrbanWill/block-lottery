// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DataTypesLib {
    enum GameDigits {
        Two,
        Three // To be implemented in V2
    }

    enum TwoDigitGameType {
        Lower, // Two digits game will default to lower game type
        Reverse,
        Upper,
        UpperReverse
    }

    struct GameEntryFees {
        uint256 One;
        uint256 Two;
        uint256 Three;
    }
}
