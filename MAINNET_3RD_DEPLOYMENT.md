# YieldCore RWA Protocol - 3rd Deal Deployment

> Deployed: 2026-03-20

## Vault Info

| Property | Value |
|----------|-------|
| **Name** | yieldcore-3rd-deal |
| **Symbol** | ycdeal3 |
| **Address** | `0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a` |
| **Etherscan** | [View](https://etherscan.io/address/0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a) |
| **Fixed APY** | 18% (1800 bps) |
| **Min Deposit** | 100 USDC |
| **Max Capacity** | 440,000 USDC |
| **Term Duration** | 30 days |

## Timeline (KST)

| Phase | Date/Time | Unix Timestamp |
|-------|-----------|----------------|
| Collection Start | 2026-03-20 00:00:00 | 1773932400 |
| Collection End | 2026-03-23 10:00:00 | 1774227600 |
| Interest Start | 2026-03-23 10:00:00 | 1774227600 |
| Withdrawal Start | 2026-04-29 00:00:00 | 1777388400 |

## Interest Schedule

| Period | End Date (KST) | Payment Date (KST) | Unix (End) | Unix (Payment) |
|--------|----------------|---------------------|------------|----------------|
| 1 | 2026-04-22 00:00:00 | 2026-04-25 00:00:00 | 1776783600 | 1777042800 |

## Core Contracts (shared with 2nd deal)

| Contract | Address |
|----------|---------|
| **VaultFactory** | `0x475984eb4672eb45BDf8750848B91FB113fdD8de` |
| **PoolManager** | `0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8` |
| **VaultRegistry** | `0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2` |
| **LoanRegistry** | `0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De` |
| **Admin (Safe)** | `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE` |
| **USDC** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |

## Quick Reference

```javascript
const VAULT_3RD_DEAL = '0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a';
```

## Safe Transaction

- **Safe TX Hash**: `0x0d69e10fcebedfeab1b2abc6f2081f29ce7d405bb09e7e21f150c28ddb0007cc`
- **Nonce**: 29
- **Safe Queue**: [View](https://app.safe.global/transactions/queue?safe=eth:0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE)
