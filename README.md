# Chainviti

Chainviti is a multi-tenant invitation-based membership protocol with NFT minting capabilities. It allows for the creation of applications, invitation flows, and membership management using ERC721 tokens.

## Features

- Create separate apps with isolated membership and invitation systems
- Invitation-based membership model with per-app configurable invite limits
- NFT-based membership credentials
- Flexible administration with multi-admin support
- Configurable token transferability (per app)
- Individual token locking mechanism
- Custom metadata URIs per app

## Installation

This project uses [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

```bash
# Clone the repository
git clone https://github.com/yourusername/chainviti.git
cd chainviti

# Install dependencies
forge install
```

## Usage

### Compile the contract

```bash
forge build
```

### Run tests

```bash
forge test
```

### Deploy

```bash
forge create --rpc-url <your_rpc_url> \
  --constructor-args \
  --private-key <your_private_key> \
  src/Chainviti.sol:Chainviti
```

## Contract Architecture

Chainviti uses the ERC721 standard for NFT tokens and implements several OpenZeppelin extensions:

- `ERC721Upgradeable`: Base NFT functionality
- `ERC721EnumerableUpgradeable`: Enumeration of NFTs
- `OwnableUpgradeable`: Basic access control
- `UUPSUpgradeable`: Upgradeable contract pattern

## Basic Operations

### Creating an App

```solidity
// Creates a new app with specified initial invites and invites per new user
function createApp(bytes32 appId, uint256 initialInvites, uint256 invitesPerNewUser) external;
```

### Sending Invitations

```solidity
// Sends an invitation to a new user
function invite(bytes32 appId, address newUserAddress) external;
```

### Accepting Invitations

```solidity
// Accepts an invitation, mints an NFT for the user
function acceptInvite(bytes32 appId) external;
```

### Checking Access

```solidity
// Checks if a user has access to an app
function hasAccess(bytes32 appId, address user) public view returns (bool);
```

## License

This project is licensed under the MIT License.
