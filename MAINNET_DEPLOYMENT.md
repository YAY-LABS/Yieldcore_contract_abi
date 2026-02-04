# YieldCore RWA Protocol - Ethereum Mainnet Deployment

> Deployed: 2026-02-04

## Core Contracts

| Contract | Address | Etherscan |
|----------|---------|-----------|
| **LoanRegistry** | `0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De` | [View](https://etherscan.io/address/0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De) |
| **VaultRegistry** | `0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2` | [View](https://etherscan.io/address/0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2) |
| **PoolManager** | `0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8` | [View](https://etherscan.io/address/0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8) |
| **VaultFactory** | `0x475984eb4672eb45BDf8750848B91FB113fdD8de` | [View](https://etherscan.io/address/0x475984eb4672eb45BDf8750848B91FB113fdD8de) |
| **RWAVault (impl)** | `0x317aA10528Ff675eF4C358ea6a5B7B5494325733` | [View](https://etherscan.io/address/0x317aA10528Ff675eF4C358ea6a5B7B5494325733) |

## External Dependencies

| Contract | Address | Description |
|----------|---------|-------------|
| **USDC** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | Circle USDC (6 decimals) |

## Admin & Treasury

| Role | Address |
|------|---------|
| **Admin (Safe)** | `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE` |
| **Treasury** | `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE` |
| **Protocol Fee** | 0% (0 bps) |

## Deployed Vaults

### yieldcore-2nd-deal (ycdeal2)

| Property | Value |
|----------|-------|
| **Address** | `0x98FFBD67fb84506c630a77b901ACeA78CC917470` |
| **Etherscan** | [View](https://etherscan.io/address/0x98FFBD67fb84506c630a77b901ACeA78CC917470) |
| **Symbol** | ycdeal2 |
| **Fixed APY** | 15% |
| **Min Deposit** | 100 USDC |
| **Max Capacity** | 1,000,000 USDC |

#### Timeline (KST)

| Phase | Date/Time |
|-------|-----------|
| Collection Start | 2026-02-04 15:00:00 |
| Collection End | 2026-02-07 23:59:59 |
| Interest Start | 2026-02-09 00:00:00 |
| Term Duration | 88 days 23h 59m 59s |
| Withdrawal Start | 2026-05-18 00:00:00 |

#### Interest Schedule

| Period | End Date | Payment Date |
|--------|----------|--------------|
| 1 | 2026-03-08 23:59:59 | 2026-03-12 00:00:00 |
| 2 | 2026-04-08 23:59:59 | 2026-04-13 00:00:00 |
| 3 | 2026-05-08 23:59:59 | 2026-05-13 00:00:00 |

## Role Configuration

### Admin Roles (0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE)

| Contract | Roles |
|----------|-------|
| LoanRegistry | DEFAULT_ADMIN, OPERATOR |
| VaultRegistry | DEFAULT_ADMIN |
| PoolManager | DEFAULT_ADMIN, OPERATOR, CURATOR |
| VaultFactory | DEFAULT_ADMIN, OPERATOR |

### Deployer Roles (0x81868cc83622b722a0C9fd423f6c66b4dDD800E9)

| Contract | Roles |
|----------|-------|
| All Contracts | PAUSER_ROLE only |

## Safe Multisig

- **Safe Address**: `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE`
- **Safe App**: https://app.safe.global/home?safe=eth:0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE

## Quick Reference

```javascript
// Mainnet Contract Addresses
const CONTRACTS = {
  USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  LOAN_REGISTRY: '0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De',
  VAULT_REGISTRY: '0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2',
  POOL_MANAGER: '0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8',
  VAULT_FACTORY: '0x475984eb4672eb45BDf8750848B91FB113fdD8de',
};

// Vaults
const VAULTS = {
  'yieldcore-2nd-deal': '0x98FFBD67fb84506c630a77b901ACeA78CC917470',
};
```

## Verification

All contracts are verified on Etherscan. Source code available at:
- Repository: `yieldcore_RWA_contracts/v2_without_proxy`
- Compiler: Solidity 0.8.24
- EVM Version: Cancun
- Optimizations: Enabled
