# NIKO-SUN Solar Token

🇺🇸 English | [🇪🇸 Español](README.es.md)

---

## 🌐 Deployed Contract

| Network | Address |
|---------|---------|
| **Syscoin Testnet** | [`0xFcE8D6510898854508C8f8d494e5595eD0a40184`](https://tanenbaum.io/address/0xFcE8D6510898854508C8f8d494e5595eD0a40184) |

---

## Overview

**SolarTokenV3Optimized** is an ERC-1155 smart contract designed for tokenizing solar energy projects. It enables the creation of investment projects, token minting, revenue distribution, and transparent tracking of energy production.

## Features

### 🔋 Project Management
- **Create Projects**: Anyone can create solar energy investment projects with customizable parameters
- **Project Metadata**: Each project includes name, total supply, price per token, and minimum purchase requirements
- **Project Status Control**: Creators can activate/deactivate their projects
- **Ownership Transfer**: Project ownership can be transferred to another address

### 💰 Token Economics
- **ERC-1155 Multi-Token**: Each project has its own token ID
- **Flexible Pricing**: Configurable price per token in Wei
- **Minimum Purchase**: Enforced minimum token purchase per transaction
- **Automatic Refunds**: Excess payments are automatically refunded

### 📊 Revenue Distribution
- **Deposit Revenue**: Project creators can deposit revenue from energy production
- **Fair Distribution**: Revenue is distributed proportionally based on token holdings
- **Claim Rewards**: Investors can claim accumulated rewards at any time
- **Batch Claims**: Claim rewards from multiple projects in a single transaction

### ⚡ Energy Tracking
- **Energy Updates**: Track total energy produced in kWh
- **Transparent Metrics**: On-chain visibility of energy generation data

### 🔒 Security Features
- **Ownable**: Admin functions restricted to contract owner
- **Pausable**: Emergency pause functionality
- **ReentrancyGuard**: Protection against reentrancy attacks
- **Custom Errors**: Gas-efficient error handling

## Contract Architecture

```
SolarTokenV3Optimized
├── ERC1155 (Multi-token standard)
├── Ownable (Admin control)
├── Pausable (Emergency stop)
└── ReentrancyGuard (Security)
```

## Main Functions

| Function | Description |
|----------|-------------|
| `createProject()` | Create a new solar project |
| `mint()` | Purchase tokens from a project |
| `depositRevenue()` | Deposit revenue for distribution |
| `claimRevenue()` | Claim accumulated rewards |
| `claimMultipleOptimized()` | Claim from multiple projects |
| `withdrawSales()` | Withdraw sales proceeds (creator only) |

---

## 🛠️ Development

### Built with Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

### Documentation

https://book.getfoundry.sh/

### Usage

#### Build

```shell
forge build
```

#### Test

```shell
forge test
```

#### Format

```shell
forge fmt
```

#### Gas Snapshots

```shell
forge snapshot
```

#### Deploy

```shell
forge script script/DeploySolarToken.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

#### Cast

```shell
cast <subcommand>
```

#### Help

```shell
forge --help
anvil --help
cast --help
```

---

## 📄 License

MIT
