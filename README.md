## Block Lottery

- [Lottery Engine Proxy](https://mumbai.polygonscan.com/address/0x7a8A6cF34a185e6e134108E941b14d011c8FD054)
- [Lottery Engine](https://mumbai.polygonscan.com/address/0x806acffbc71b34c49ceef95de8d6dec2ff827711)
- [Ticket NFT Proxy](https://mumbai.polygonscan.com/address/0x47b88faecc6e732e82aed68e0a029271844319ec)
- [Ticket NFT](https://mumbai.polygonscan.com/address/0x0b59eb0e94a999f917cc179762756fe37f4e1481)

## About

A Lottery application built for EVM compatible chains. Utilizing smart contracts to create a transparent and secure lottery experience.

- [Block Lottery](#block-lottery)
- [About](#about)
- [Key features](#key-features)
- [How it works](#how-it-works)
- [Technical overview](#technical-overview)
- [Security](#security)
- [Usage](#usage)
  - [Start a local node](#start-a-local-node)
  - [Deploy](#deploy)
  - [Deploy - Other Network](#deploy---other-network)
  - [Testing](#testing)
- [Deployment to a testnet or mainnet](#deployment-to-a-testnet-or-mainnet)
- [Estimate gas](#estimate-gas)
- [Formatting](#formatting)

### Key features

1. NFT-Based Lottery Tickets: Each lottery ticket is represented as an NFT, providing undeniable proof of ownership and participation in the lottery draw. These tickets contain the selected numbers and relevant game information.

2. Dynamic Number Selection: Players can choose their preferred numbers within a defined range, giving them control over their lottery experience.

3. USD-Pegged Ticket Pricing: The value of each lottery ticket is pegged to a fixed USD amount. Payments are made in the blockchain's native currency, with the USD value derived from a reliable oracle service.

4. Transparent and Fair Draws: The lottery draws are posted with complete transparency. Smart contracts govern the posting of the draw process according to official Thai government results, ensuring fairness and randomness.

5. Scalable and Upgradeable Architecture: Utilizing OpenZeppelin's upgradeable contract patterns, our application is designed for future enhancements and scalability.

6. Robust Security Measures: The application incorporates ReentrancyGuard for additional security, mitigating potential risks associated with smart contract interactions.

### How it works

- Ticket Purchase: Players buy tickets by selecting their numbers and paying the equivalent USD value in the native blockchain currency. The contract interacts with an oracle to determine the current exchange rate.

- Lottery Draw: At the end of each lottery round, the winning numbers are posted and announced. Players holding NFT tickets with matching numbers can claim their winnings.

- Claiming Winnings: Winnings are distributed in the the equivalent USD value in the native blockchain currency multiplied by the payout factor, and the NFT ticket status is updated to reflect the claim. The contract interacts with an oracle to determine the current exchange rate.

## Technical overview

- Contracts: The system consists of two primary contracts - `LotteryEngineV1` and `TicketV1`.

  - `LotteryEngineV1` handles the core lottery logic, including ticket sales, round management, and result declaration.
  - `TicketV1` is an ERC721-compliant contract for minting and managing lottery ticket NFTs.

- Upgradability: Both contracts are upgradeable, ensuring the system can adapt to changing needs and incorporate improvements over time.
- Access Control: The system uses role-based access control to manage different operational aspects securely.
- Oracle Integration: Chainlink's oracle service is used to fetch real-time USD exchange rates, ensuring accurate pricing of tickets.

### Security

**Ensuring the Integrity and Trust of the LotteryNFT System**
Security is a paramount concern in the LotteryNFT application, particularly in the management of funds and the execution of lottery rounds. The smart contract architecture is designed to ensure the utmost integrity and security in every aspect of the game, from tracking winnings to managing withdrawals.

####Tracking of Winnings
Transparent Record of Winnings: The `LotteryEngineV1` contract tracks all winnings, whether pending or claimed. This information is stored securely on the blockchain, providing transparency and trust in the payout process.

Claiming Winnings: Winners can claim their prizes in a secure manner. The contract verifies the ownership of the winning ticket NFT and ensures that winnings are only paid out once, updating the ticket's status to 'claimed' to prevent double claims.

####Secure Withdrawal Process
Owner-Only Withdrawal: Withdrawals from the contract balance are strictly restricted to the contract owner, ensuring that only authorized personnel can access the funds.

**No Active Game Requirement**: Withdrawals by the contract owner are only permissible when there is no active game ongoing. This measure is in place to ensure that the prize pool is fully funded and available for winners at all times.

**Limitation on Withdrawal Amount**: The amount that can be withdrawn by the owner is capped at a value less than the total unclaimed winnings (contract debt). This safeguard ensures that the contract always has sufficient funds to pay out all pending winnings, maintaining the integrity of the lottery system and protecting the interests of the participants.

## Usage

## Start a local node

```
make anvil
```

## Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```
make deploy
```

## Deploy - Other Network

[See below](#deployment-to-a-testnet-or-mainnet)

### Testing

```shell
$ forge test
```

```shell
$ forge coverage --ir-minimum
```

# Deployment to a testnet or mainnet

1. Setup environment variables

You'll want to set your `SEPOLIA_RPC_URL` and `PRIVATE_KEY` as environment variables. You can add them to a `.env` file, similar to what you see in `.env.example`.

- `PRIVATE_KEY`: The private key of your account (like from [metamask](https://metamask.io/)). **NOTE:** FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
  - You can [learn how to export it here](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-Export-an-Account-Private-Key).
- `SEPOLIA_RPC_URL`: This is url of the sepolia testnet node you're working with. You can get setup with one for free from [Alchemy](https://alchemy.com/?a=673c802981)

Optionally, add your `ETHERSCAN_API_KEY` if you want to verify your contract on [Etherscan](https://etherscan.io/).

After adding environment variables run:

```
source .env
```

1. Get testnet ETH

Head over to [Sepolia faucet](https://sepoliafaucet.com/) and get some testnet ETH. You should see the ETH show up in your metamask.

2. Deploy

```
make deploy ARGS="--network sepolia"
```

## Estimate gas

You can estimate how much gas things cost by running:

```
forge snapshot
```

And you'll see an output file called `.gas-snapshot`

# Formatting

To run code formatting:

```
forge fmt
```
