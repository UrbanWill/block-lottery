// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DataTypesLib} from "./libraries/DataTypesLib.sol";

contract TicketV1 is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 private _nextTokenId;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    mapping(uint256 tokenId => TokenInfo) public tokenInfo;

    struct TokenInfo {
        bool claimed;
        uint16 round;
        DataTypesLib.GameDigits gameDigits;
        DataTypesLib.GameType gameType;
        DataTypesLib.GameEntryTier tier;
        uint8[] lowerNumbers;
        uint8[] upperNumbers;
    }

    ////////////////////////////////////////
    // Functions                          //
    ////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address minter, address upgrader) public initializer {
        __ERC721_init("Ticket", "TCK");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
    }

    ////////////////////////////////////////
    // External Functions                 //
    ////////////////////////////////////////

    function safeMint(
        address to,
        uint16 round,
        DataTypesLib.GameDigits gameDigits,
        DataTypesLib.GameType gameType,
        DataTypesLib.GameEntryTier tier,
        uint8[] calldata lowerNumbers,
        uint8[] calldata upperNumbers,
        string memory uri
    ) public onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _setTokenInfo(
            tokenId,
            TokenInfo({
                claimed: false,
                round: round,
                gameDigits: gameDigits,
                gameType: gameType,
                tier: tier,
                lowerNumbers: lowerNumbers,
                upperNumbers: upperNumbers
            })
        );

        return tokenId;
    }

    function setTicketClaimed(uint256 tokenId) public onlyRole(MINTER_ROLE) {
        tokenInfo[tokenId].claimed = true;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////
    // Private & Internal View Functions  //
    ////////////////////////////////////////

    function _setTokenInfo(uint256 tokenId, TokenInfo memory info) internal {
        tokenInfo[tokenId] = info;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }
    ////////////////////////////////////////
    // Public & External View Functions   //
    ////////////////////////////////////////

    /**
     *
     * @param tokenId Id of the token to get info for
     */
    function getTokenInfo(uint256 tokenId)
        public
        view
        returns (
            bool claimed,
            uint16 round,
            DataTypesLib.GameDigits gameDigits,
            DataTypesLib.GameType gameType,
            DataTypesLib.GameEntryTier tier,
            uint8[] memory lowerNumbers,
            uint8[] memory upperNumbers
        )
    {
        TokenInfo memory info = tokenInfo[tokenId];
        return
            (info.claimed, info.round, info.gameDigits, info.gameType, info.tier, info.lowerNumbers, info.upperNumbers);
    }

    function version() public pure returns (uint8) {
        return 1;
    }
}
