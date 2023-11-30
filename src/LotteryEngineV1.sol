// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TicketV1} from "./TicketV1.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {Test, console} from "forge-std/Test.sol";

contract LotteryEngineV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////
    // Types                              //
    ////////////////////////////////////////

    using OracleLib for AggregatorV3Interface;
    ////////////////////////////////////////
    // State Variables                    //
    ////////////////////////////////////////

    uint16 private constant CLAIMABLE_DELAY = 1 hours;
    uint16 s_roundCounter = 0;
    uint8 private s_payoutFactor;
    uint8 private constant MIN_NUMBER = 1;
    uint8 private constant MAX_TWO_DIGIT_GAME_NUMBER = 99;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    address public s_ticketAddress;
    address private s_priceFeed;

    mapping(DataTypesLib.GameDigits => DataTypesLib.FeePerTier) private s_gameEntryFees;
    mapping(uint16 round => DataTypesLib.RoundStatus roundStats) public s_roundStats;

    ////////////////////////////////////////
    // Events                             //
    ////////////////////////////////////////

    event RoundCreated(uint16 indexed round, uint256 timestamp);
    event RoundPaused(uint16 indexed round, uint256 timestamp);
    event RoundUnpaused(uint16 indexed round, uint256 timestamp);
    event RoundResultsPosted(
        uint16 indexed round, uint8 indexed lowerWinner, uint8 indexed upperWinner, uint256 timestamp
    );
    event RoundResultsAmended(
        uint16 indexed round, uint8 indexed lowerWinner, uint16 indexed upperWinner, uint256 timestamp
    );
    event RoundClosed(uint16 indexed round, uint16 winners, uint16 claimed, uint256 timestamp);
    event TicketBought(
        uint16 indexed round,
        DataTypesLib.GameDigits digits,
        DataTypesLib.GameType indexed gameType,
        DataTypesLib.GameEntryTier indexed tier,
        uint8 number,
        address player
    );
    event TicketClaimed(
        uint16 indexed round,
        DataTypesLib.GameDigits digits,
        DataTypesLib.GameType indexed gameType,
        DataTypesLib.GameEntryTier indexed tier,
        uint8 number,
        uint256 tokenId,
        uint256 winnings,
        address player
    );
    event EntryFeeChanged(
        DataTypesLib.GameDigits indexed digits, DataTypesLib.GameEntryTier indexed tier, uint256 indexed fee
    );
    event PayoutFactorChanged(uint8 indexed payoutFactor, uint256 timestamp);

    ////////////////////////////////////////
    // Errors                             //
    ////////////////////////////////////////

    error LotteryEngine__CurrentRoundOngoing();
    error LotteryEngine__RoundMustBeOpen();
    error LotteryEngine__IncorrectTierFee();
    error LotteryEngine__NumberOutOfRange();
    error LotteryEngine__RoundAlreadyPaused();
    error LotteryEngine__RoundMustBePaused();
    error LotteryEngine__RoundMustBeClaimable();
    error LotteryEngine__RoundResultAmendMustBeWithinTime();
    error LotteryEngine__OnlyTicketOwnerCanClaimWinnings();
    error LotteryEngine__TicketAlreadyClaimed();
    error LotteryEngine__AmountMustBeLessThanTotalUnclaimedWinnings();
    error LotteryEngine__InputCannotBeZero();

    ////////////////////////////////////////
    // Modifiers                          //
    ////////////////////////////////////////

    modifier roundMustBeDone() {
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

    function initialize(
        address initialOwner,
        address _ticketAddress,
        address priceFeedAddress,
        uint256[3] memory _twoDigitGameFees
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        s_ticketAddress = _ticketAddress;
        s_priceFeed = priceFeedAddress;
        s_payoutFactor = 25; // TODO: Move this to a config file

        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.One] = _twoDigitGameFees[0];
        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.Two] = _twoDigitGameFees[1];
        s_gameEntryFees[DataTypesLib.GameDigits.Two].feePerTier[DataTypesLib.GameEntryTier.Three] = _twoDigitGameFees[2];
    }

    ////////////////////////////////////////
    // External Functions                 //
    ////////////////////////////////////////

    /**
     * @notice Creates a new round with open status
     */
    function createRound() public onlyOwner roundMustBeDone {
        s_roundCounter++;
        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Open;

        emit RoundCreated(s_roundCounter, block.timestamp);
    }

    /**
     * @dev Pauses the current round
     * @notice Pause the ticket sales for the current round on the day of the draw
     * @notice This function will eventually be refactored to be called by a Chainlink automator
     */
    function pauseRound() public onlyOwner roundMustBeOpen(s_roundCounter) {
        if (s_roundStats[s_roundCounter].status == DataTypesLib.GameStatus.Paused) {
            revert LotteryEngine__RoundAlreadyPaused();
        }

        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Paused;

        emit RoundPaused(s_roundCounter, block.timestamp);
    }

    /**
     * @dev Unpauses the current round
     * @notice Unpause the ticket sales for the current round
     */
    function unpauseRound() public onlyOwner {
        if (s_roundStats[s_roundCounter].status != DataTypesLib.GameStatus.Paused) {
            revert LotteryEngine__RoundMustBePaused();
        }
        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Open;

        emit RoundUnpaused(s_roundCounter, block.timestamp);
    }

    /**
     * @notice Post the results of the round
     * @notice This function is called by a human and therefore subject to human error,
     * this is the reason for the 1 hour delay before the round is claimable, to fix possible human errors
     * @param lowerWinner Winning lower number for the round
     * @dev This function will eventually be refactored to inlcude the 3 digits game
     */
    function postRoundResults(uint8 lowerWinner, uint8 upperWinner) public onlyOwner {
        if (s_roundStats[s_roundCounter].status != DataTypesLib.GameStatus.Paused) {
            revert LotteryEngine__RoundMustBePaused();
        }
        s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Claimable;
        s_roundStats[s_roundCounter].lowerWinner = lowerWinner;
        s_roundStats[s_roundCounter].upperWinner = upperWinner;
        s_roundStats[s_roundCounter].clamableAt = block.timestamp + CLAIMABLE_DELAY;

        emit RoundResultsPosted(s_roundCounter, lowerWinner, upperWinner, block.timestamp);
        _closeRound(s_roundCounter);
    }
    /**
     * @notice Amend the results of the round. Will only work within the CLAIMABLE_DELAY time.
     * @notice This function is called by a human and therefore subject to human error,
     * this is the reason for the 1 hour delay before the round is claimable, to fix possible human errors
     * @param lowerWinner Winning lower number for the round
     * @param upperWinner Winning upper number for the round
     */

    function amendRoundResults(uint8 lowerWinner, uint8 upperWinner) public onlyOwner {
        if (s_roundStats[s_roundCounter].clamableAt < block.timestamp) {
            revert LotteryEngine__RoundResultAmendMustBeWithinTime();
        }

        s_roundStats[s_roundCounter].lowerWinner = lowerWinner;
        s_roundStats[s_roundCounter].upperWinner = upperWinner;
        s_roundStats[s_roundCounter].clamableAt = block.timestamp + CLAIMABLE_DELAY;

        emit RoundResultsAmended(s_roundCounter, lowerWinner, upperWinner, block.timestamp);

        uint256 roundWinnersCount = getTotalWinnersCountPerRound(s_roundCounter);

        if (roundWinnersCount > 0) {
            s_roundStats[s_roundCounter].status = DataTypesLib.GameStatus.Claimable;
        }
    }

    /**
     *
     * @param gameDigits Digits of the game, currently only 2 digits is supported
     * @param gameEntryTier Tier of the game, maps to the entry fee
     * @param fee USD fee of the game tier in WEI
     */
    function setGameEntryFee(DataTypesLib.GameDigits gameDigits, DataTypesLib.GameEntryTier gameEntryTier, uint256 fee)
        public
        onlyOwner
        roundMustBeDone
    {
        if (fee == 0) {
            revert LotteryEngine__InputCannotBeZero();
        }
        s_gameEntryFees[gameDigits].feePerTier[gameEntryTier] = fee;

        emit EntryFeeChanged(gameDigits, gameEntryTier, fee);
    }

    function setGamePayoutFactor(uint8 payoutFactor) public onlyOwner roundMustBeDone {
        if (payoutFactor == 0) {
            revert LotteryEngine__InputCannotBeZero();
        }
        s_payoutFactor = payoutFactor;

        emit PayoutFactorChanged(payoutFactor, block.timestamp);
    }

    /**
     * @notice Withdraws from the contract balance.
     * @notice Cannot be used to withdraw user's unclaimed winnings.
     * Cannot be withdraw if there is a game in progress as the winnings cannot be calculated.
     * @param to Address to send the funds to
     * @param amount Amount to withdraw
     */
    function withdraw(address to, uint256 amount) public onlyOwner roundMustBeDone {
        uint256 totalUnclaimedWinnings = getTotalUnclaimedWinnings();
        uint256 availableBalanceAfterWithdaw = address(this).balance - amount;

        if (availableBalanceAfterWithdaw < totalUnclaimedWinnings) {
            revert LotteryEngine__AmountMustBeLessThanTotalUnclaimedWinnings();
        }

        payable(to).transfer(amount);
    }

    /**
     * @notice Buy a two digits ticket for a given round, mints a new ticket NFT
     * @dev TODO: Refactor this function to be more gas efficient
     * @param round Round number
     * @param gameType Type of the game
     * @param tier Tier price of the game
     * @param number Number to bet on
     * @param tokenUri URI of the token to be minted
     * @return tokenId of the minted ticket
     */
    function buyTwoDigitsTicket(
        uint16 round, // This can be removed, the data is s_roundCounter
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier,
        uint8 number,
        string memory tokenUri
    ) external payable roundMustBeOpen(round) returns (uint256) {
        if (number < MIN_NUMBER || number > MAX_TWO_DIGIT_GAME_NUMBER) {
            revert LotteryEngine__NumberOutOfRange();
        }

        uint256 gameTokenAmountFee = calculateTwoDigitsTicketFee(DataTypesLib.GameDigits.Two, gameType, tier);
        if (msg.value != gameTokenAmountFee) {
            revert LotteryEngine__IncorrectTierFee();
        }
        // Handle storage updates for the ticket count
        _incrementTicketCount(round, gameType, tier, number);

        // Mint the ticket.
        uint256 tokenId = _mintTicket(round, DataTypesLib.GameDigits.Two, gameType, tier, number, tokenUri);
        emit TicketBought(round, DataTypesLib.GameDigits.Two, gameType, tier, number, msg.sender);

        return tokenId;
    }

    /**
     * @notice Claim winnings for a given ticket
     * @param tokenId Token ID of the ticket to claim winnings for
     */
    function claimWinnings(uint256 tokenId) external {
        (
            bool claimed,
            uint16 round,
            DataTypesLib.GameDigits digits,
            DataTypesLib.GameType gameType,
            DataTypesLib.GameEntryTier tier,
            uint8 number
        ) = TicketV1(s_ticketAddress).tokenInfo(tokenId);
        DataTypesLib.RoundStatus storage roundStats = s_roundStats[round];

        if (roundStats.status != DataTypesLib.GameStatus.Claimable || roundStats.clamableAt > block.timestamp) {
            revert LotteryEngine__RoundMustBeClaimable();
        }
        if (msg.sender != TicketV1(s_ticketAddress).ownerOf(tokenId)) {
            revert LotteryEngine__OnlyTicketOwnerCanClaimWinnings();
        }

        if (claimed) {
            revert LotteryEngine__TicketAlreadyClaimed();
        }

        // TODO: Move is winner check to its own function
        bool isWinner = false;

        if (gameType == DataTypesLib.GameType.Reverse) {
            if (number == reverseTwoDigitUint8(roundStats.lowerWinner)) {
                isWinner = true;
            }
        } else if (gameType == DataTypesLib.GameType.Upper) {
            if (number == roundStats.upperWinner) {
                isWinner = true;
            }
        } else if (gameType == DataTypesLib.GameType.UpperReverse) {
            if (number == reverseTwoDigitUint8(roundStats.upperWinner)) {
                isWinner = true;
            }
        }
        // Every game is a lower game by default
        if (number == roundStats.lowerWinner) {
            isWinner = true;
        }

        if (isWinner) {
            roundStats.twoDigitStatsPerTier[tier].winnersClaimedCount++;
            _closeRound(round);

            TicketV1(s_ticketAddress).setTicketClaimed(tokenId);
            uint256 winnings = getGameTokenAmountFee(digits, tier) * getPayoutFactor();
            payable(msg.sender).transfer(winnings);

            emit TicketClaimed(round, digits, gameType, tier, number, tokenId, winnings, msg.sender);
        }
    }

    ////////////////////////////////////////
    // Private & Internal View Functions  //
    ////////////////////////////////////////

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @param round Round number
     * @param gameDigits Digits of the game, currently only 2 digits is supported
     * @param tier Tier price of the game
     * @param number Number to bet on
     * @param tokenUri URI of the token to be minted
     */

    function _mintTicket(
        uint16 round,
        DataTypesLib.GameDigits gameDigits,
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier,
        uint8 number,
        string memory tokenUri
    ) internal returns (uint256) {
        uint256 tokenId =
            TicketV1(s_ticketAddress).safeMint(msg.sender, round, gameDigits, gameType, tier, number, tokenUri);

        return tokenId;
    }

    /**
     * @param gameType Type of the game
     * @return Number of tickets to be sold for a given game type
     */
    function _getTicketSaleCount(DataTypesLib.GameType gameType) internal pure returns (uint8) {
        if (gameType == DataTypesLib.GameType.UpperReverse) {
            return 4;
        } else if (gameType == DataTypesLib.GameType.Reverse || gameType == DataTypesLib.GameType.Upper) {
            return 2;
        }
        return 1;
    }

    /**
     * @notice Increments the ticket count for a given number
     * @dev Helper function to handle incrementing storage of the ticket count for a given number
     * @param round Round number
     * @param gameType Type of the game
     * @param tier Tier price of the game
     * @param number Number chose by the player to increment count
     */
    function _incrementTicketCount(
        uint16 round,
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier,
        uint8 number
    ) internal {
        // Calculate the ticket count to be incremented.
        uint8 ticketSaleCount = _getTicketSaleCount(gameType);

        // Increment the storage values once instead of multiple times.
        DataTypesLib.TwoDigitStatsPerTier storage tierStats = s_roundStats[round].twoDigitStatsPerTier[tier];
        tierStats.tierTicketCount += ticketSaleCount;
        uint8 reversedNumber;
        if (gameType == DataTypesLib.GameType.Reverse || gameType == DataTypesLib.GameType.UpperReverse) {
            reversedNumber = reverseTwoDigitUint8(number);
            tierStats.ticketCountPerLowerNumber[reversedNumber]++;
        }

        if (gameType == DataTypesLib.GameType.Upper || gameType == DataTypesLib.GameType.UpperReverse) {
            tierStats.ticketCountPerUpperNumber[number]++;
        }

        if (gameType == DataTypesLib.GameType.UpperReverse) {
            tierStats.ticketCountPerUpperNumber[reversedNumber]++;
        }

        // Every game type will increment the lower number count
        tierStats.ticketCountPerLowerNumber[number]++;
    }

    /**
     * @notice Closes a round. A round will be closed when all winners have claimed their winnings
     * or N days have passed since the round was claimable.
     * @param round Round number
     */
    function _closeRound(uint16 round) internal {
        uint16 roundWinnersCount = getTotalWinnersCountPerRound(round);
        uint16 roundWinnersClaimedCount = getTotalWinnersClaimedPerRound(round);

        if (roundWinnersCount == roundWinnersClaimedCount) {
            s_roundStats[round].status = DataTypesLib.GameStatus.Closed;

            emit RoundClosed(round, roundWinnersCount, roundWinnersCount, block.timestamp);
        }
    }

    ////////////////////////////////////////
    // Public & External View Functions   //
    ////////////////////////////////////////

    /**
     * @param usdAmountInWei USD amount in WEIi
     * @return Token amount in WEI for a given USD amount
     */
    function getTokenAmountFromUsd(uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @param amount in WEI
     * @return USD value in WEI
     */
    function getUsdValueFromToken(uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed);
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // ((price * 1e8) * (amount * 1e18 amount already in wei)) / 1e18
    }

    function getCurrentRound() public view returns (uint16) {
        return s_roundCounter;
    }

    function getRoundInfo(uint16 round)
        public
        view
        returns (
            DataTypesLib.GameStatus status,
            uint8 lowerWinner,
            uint8 upperWinner,
            uint16 threeDigitsWinner,
            uint256 claimableAt
        )
    {
        DataTypesLib.RoundStatus storage roundStats = s_roundStats[round];
        return (
            roundStats.status,
            roundStats.lowerWinner,
            roundStats.upperWinner,
            roundStats.threeDigitsWinner,
            roundStats.clamableAt
        );
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
        return s_roundStats[round].twoDigitStatsPerTier[tier].tierTicketCount;
    }

    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @param tier Tier price of the game
     * @return Number of winners that have claimed their winnings for a given tier in that round
     */
    function getTierWinnersClaimedPerRound(uint16 round, DataTypesLib.GameEntryTier tier)
        public
        view
        returns (uint16)
    {
        return s_roundStats[round].twoDigitStatsPerTier[tier].winnersClaimedCount;
    }

    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @return Total number of winners that have claimed their winnings in that round
     */
    function getTotalWinnersClaimedPerRound(uint16 round) public view returns (uint16) {
        return s_roundStats[round].twoDigitStatsPerTier[DataTypesLib.GameEntryTier.One].winnersClaimedCount
            + s_roundStats[round].twoDigitStatsPerTier[DataTypesLib.GameEntryTier.Two].winnersClaimedCount
            + s_roundStats[round].twoDigitStatsPerTier[DataTypesLib.GameEntryTier.Three].winnersClaimedCount;
    }

    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @param tier Tier price of the game
     * @return Total unlcaimed winnings value for a given tier a round
     */
    function getUnclaimedWinningsPerTierAndRound(uint16 round, DataTypesLib.GameEntryTier tier)
        public
        view
        returns (uint256)
    {
        uint16 tierWinnerCount = getTierWinnerCountPerRound(round, tier);
        uint16 winnersClaimedCount = getTierWinnersClaimedPerRound(round, tier);

        uint16 unclaimedWinnersCount = tierWinnerCount - winnersClaimedCount;

        if (unclaimedWinnersCount == 0) {
            return 0;
        }

        console.log("PayoutFactor Contract: ", getPayoutFactor());

        return unclaimedWinnersCount * getGameTokenAmountFee(DataTypesLib.GameDigits.Two, tier) * getPayoutFactor();
    }

    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @return Total unlcaimed winnings value for a given round
     */
    function getTotalUnclaimedWinningsPerRound(uint16 round) public view returns (uint256) {
        uint256 tierOneUnclaimedWinnings = getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.One);
        uint256 tierTwoUnclaimedWinnings = getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.Two);
        uint256 tierThreeUnclaimedWinnings =
            getUnclaimedWinningsPerTierAndRound(round, DataTypesLib.GameEntryTier.Three);

        return tierOneUnclaimedWinnings + tierTwoUnclaimedWinnings + tierThreeUnclaimedWinnings;
    }

    /**
     * @return Total unlcaimed winnings value for all rounds
     */
    function getTotalUnclaimedWinnings() public view returns (uint256) {
        uint256 totalUnclaimedWinnings = 0;
        for (uint16 i = 1; i <= s_roundCounter; i++) {
            if (s_roundStats[i].status == DataTypesLib.GameStatus.Claimable) {
                totalUnclaimedWinnings += getTotalUnclaimedWinningsPerRound(i);
            }
        }
        return totalUnclaimedWinnings;
    }

    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @param tier Tier price of the game
     * @return Number of Upper and Lower winners for a given tier in that round
     */
    function getTierWinnerCountPerRound(uint16 round, DataTypesLib.GameEntryTier tier) public view returns (uint16) {
        uint8 lowerWinner = s_roundStats[round].lowerWinner;
        uint8 upperWinner = s_roundStats[round].upperWinner;

        uint16 lowerWinnerCount = s_roundStats[round].twoDigitStatsPerTier[tier].ticketCountPerLowerNumber[lowerWinner];
        uint16 upperWinnerCount = s_roundStats[round].twoDigitStatsPerTier[tier].ticketCountPerUpperNumber[upperWinner];

        return lowerWinnerCount + upperWinnerCount;
    }
    /**
     * @notice Only used for two digits games
     * @param round Round number
     * @return Total winners for a given round
     */

    function getTotalWinnersCountPerRound(uint16 round) public view roundMustBeDone returns (uint16) {
        uint16 totalWinnersCount = getTierWinnerCountPerRound(round, DataTypesLib.GameEntryTier.One)
            + getTierWinnerCountPerRound(round, DataTypesLib.GameEntryTier.Two)
            + getTierWinnerCountPerRound(round, DataTypesLib.GameEntryTier.Three);

        return totalWinnersCount;
    }

    /**
     * @notice Get the number of tickets sold for a given number in a given tier, round and type
     * @dev This function will be used to prevent users from aping into a single number
     * @param round Round number
     * @param gameType  Game type
     * @param tier Tier price of the game
     * @param number Number that was bet on
     */
    function getTwoDigitsNumberCountPerType(
        uint16 round,
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier,
        uint8 number
    ) public view returns (uint256) {
        if (gameType == DataTypesLib.GameType.Lower || gameType == DataTypesLib.GameType.Reverse) {
            return s_roundStats[round].twoDigitStatsPerTier[tier].ticketCountPerLowerNumber[number];
        }
        return s_roundStats[round].twoDigitStatsPerTier[tier].ticketCountPerUpperNumber[number];
    }

    /**
     * @param gameDigits Digits of the game, currently only 2 digits is supported
     * @param gameEntryTier Tier of the game, maps to the entry fee
     */
    function getGameFee(DataTypesLib.GameDigits gameDigits, DataTypesLib.GameEntryTier gameEntryTier)
        public
        view
        returns (uint256)
    {
        return s_gameEntryFees[gameDigits].feePerTier[gameEntryTier];
    }

    /**
     * @param gameDigits Digits of the game, currently only 2 digits is supported
     * @param gameEntryTier Tier of the game, maps to the entry fee
     * @return Token amount in wei for a given USD Entry tier fee amount
     */
    function getGameTokenAmountFee(DataTypesLib.GameDigits gameDigits, DataTypesLib.GameEntryTier gameEntryTier)
        public
        view
        returns (uint256)
    {
        uint256 fee = getGameFee(gameDigits, gameEntryTier);
        return getTokenAmountFromUsd(fee);
    }

    /**
     * @return Payout factor for the game
     */
    function getPayoutFactor() public view returns (uint8) {
        return s_payoutFactor;
    }

    /**
     * @param gameDigits Digit of the game, currently only 2 digits is supported
     * @param gameType Type of the game
     * @param tier Game tier price
     */
    function calculateTwoDigitsTicketFee(
        DataTypesLib.GameDigits gameDigits,
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier
    ) public view returns (uint256) {
        uint256 gameTokenAmountFee = getGameTokenAmountFee(gameDigits, tier);

        if (gameType == DataTypesLib.GameType.Reverse || gameType == DataTypesLib.GameType.Upper) {
            return gameTokenAmountFee * 2;
        } else if (gameType == DataTypesLib.GameType.UpperReverse) {
            return gameTokenAmountFee * 4;
        }
        // Handles Lower case
        return gameTokenAmountFee;
    }

    /**
     * @notice Reverses a two digit number
     * @dev Two digits uint8 numbers are expected. This will move moved off chain on a future version
     * @param number Two digit Number to reverse
     */
    function reverseTwoDigitUint8(uint8 number) public pure returns (uint8) {
        if (number < MIN_NUMBER || number > MAX_TWO_DIGIT_GAME_NUMBER) {
            revert LotteryEngine__NumberOutOfRange();
        }

        uint8 tens = number / 10;
        uint8 ones = number % 10;

        return ones * 10 + tens;
    }

    function version() public pure returns (uint8) {
        return 1;
    }
}
