# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type
This is a Foundry-based Solidity smart contract project for Ethereum development.

## Essential Commands

### Build & Compilation
- `forge build` - Compile all contracts
- `forge build --sizes` - Compile with size information

### Testing
- `forge test` - Run all tests
- `forge test -vvv` - Run tests with verbose output (shows detailed traces)
- `forge test --match-test testName` - Run specific test by name
- `forge test --match-contract ContractName` - Run tests for specific contract
- `forge test --gas-report` - Run tests with gas usage report

### Code Quality
- `forge fmt` - Format Solidity code
- `forge fmt --check` - Check if code is formatted correctly (used in CI)

### Development Tools
- `forge snapshot` - Create gas snapshots for benchmarking
- `anvil` - Start local Ethereum test node

### Deployment
- `forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>` - Deploy contracts

## Project Architecture

### Directory Structure
- `src/` - Smart contract source files
- `test/` - Test files (naming convention: `ContractName.t.sol`)
- `script/` - Deployment and interaction scripts (naming convention: `ContractName.s.sol`)
- `lib/` - Dependencies managed by Foundry (forge-std is the standard library)

### Testing Conventions
- Tests inherit from `forge-std/Test.sol`
- Test functions prefixed with `test` for standard tests
- Test functions prefixed with `testFuzz` for fuzz tests
- `setUp()` function runs before each test

### CI/CD
The project uses GitHub Actions with the `FOUNDRY_PROFILE=ci` environment variable. CI runs:
1. Code formatting check
2. Build with size reporting
3. Test execution with verbose output