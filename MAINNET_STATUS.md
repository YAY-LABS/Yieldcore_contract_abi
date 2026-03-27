# YieldCore RWA Protocol - Mainnet Deployment Status

> Last Updated: 2026-03-27

## Core Contracts (Shared)

| Contract | Address | Etherscan |
|----------|---------|-----------|
| **VaultFactory** | `0x475984eb4672eb45BDf8750848B91FB113fdD8de` | [View](https://etherscan.io/address/0x475984eb4672eb45BDf8750848B91FB113fdD8de) |
| **PoolManager** | `0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8` | [View](https://etherscan.io/address/0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8) |
| **VaultRegistry** | `0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2` | [View](https://etherscan.io/address/0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2) |
| **LoanRegistry** | `0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De` | [View](https://etherscan.io/address/0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De) |
| **RWAVault (impl)** | `0x317aA10528Ff675eF4C358ea6a5B7B5494325733` | [View](https://etherscan.io/address/0x317aA10528Ff675eF4C358ea6a5B7B5494325733) |
| **USDC** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | [View](https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) |

## Admin

| Role | Address |
|------|---------|
| **Admin (Safe)** | `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE` |
| **Treasury** | `0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE` |
| **Deployer (Pauser)** | `0x81868cc83622b722a0C9fd423f6c66b4dDD800E9` |
| **Safe App** | [Open](https://app.safe.global/home?safe=eth:0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE) |

---

## Vault Overview

| # | Name | Symbol | Address | APY | Capacity | Term | Status |
|---|------|--------|---------|-----|----------|------|--------|
| 2 | yieldcore-2nd-deal | ycdeal2 | [`0x98FF...7470`](https://etherscan.io/address/0x98FFBD67fb84506c630a77b901ACeA78CC917470) | 15% | 1,000,000 USDC | 88d | Active |
| 3 | yieldcore-3rd-deal | ycdeal3 | [`0xB9C7...F88a`](https://etherscan.io/address/0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a) | 18% | 440,000 USDC | 30d | Active |

---

## Vault #2: yieldcore-2nd-deal (ycdeal2)

| Property | Value |
|----------|-------|
| **Address** | `0x98FFBD67fb84506c630a77b901ACeA78CC917470` |
| **Deployed** | 2026-02-04 |
| **Fixed APY** | 15% (1500 bps) |
| **Min Deposit** | 100 USDC |
| **Max Capacity** | 1,000,000 USDC |

### Timeline (KST)

| Phase | Date/Time |
|-------|-----------|
| Collection Start | 2026-02-04 15:00:00 |
| Collection End | 2026-02-07 23:59:59 |
| Interest Start | 2026-02-09 00:00:00 |
| Term Duration | 88 days 23h 59m 59s |
| Withdrawal Start | 2026-05-18 00:00:00 |

### Interest Schedule

| Period | End Date (KST) | Payment Date (KST) |
|--------|----------------|---------------------|
| 1 | 2026-03-08 23:59:59 | 2026-03-12 00:00:00 |
| 2 | 2026-04-08 23:59:59 | 2026-04-13 00:00:00 |
| 3 | 2026-05-08 23:59:59 | 2026-05-13 00:00:00 |

---

## Vault #3: yieldcore-3rd-deal (ycdeal3)

| Property | Value |
|----------|-------|
| **Address** | `0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a` |
| **Deployed** | 2026-03-20 |
| **Fixed APY** | 18% (1800 bps) |
| **Min Deposit** | 100 USDC |
| **Max Capacity** | 440,000 USDC |
| **Safe TX Hash** | `0x0d69e10fcebedfeab1b2abc6f2081f29ce7d405bb09e7e21f150c28ddb0007cc` |

### Timeline (KST)

| Phase | Date/Time | Unix Timestamp |
|-------|-----------|----------------|
| Collection Start | 2026-03-20 00:00:00 | 1773932400 |
| Collection End | 2026-03-23 10:00:00 | 1774227600 |
| Interest Start | 2026-03-23 10:00:00 | 1774227600 |
| Withdrawal Start | 2026-04-29 00:00:00 | 1777388400 |

### Interest Schedule

| Period | End Date (KST) | Payment Date (KST) | Unix (End) | Unix (Payment) |
|--------|----------------|---------------------|------------|----------------|
| 1 | 2026-04-22 00:00:00 | 2026-04-25 00:00:00 | 1776783600 | 1777042800 |

---

## Quick Reference

```javascript
// Core Contracts
const CONTRACTS = {
  USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  LOAN_REGISTRY: '0xb08c6C256d9570B77c0026C65Bd36Ebe8116e7De',
  VAULT_REGISTRY: '0x7599eB7ea803a50cD0aECa8E152e0Ae5A980d4B2',
  POOL_MANAGER: '0xa3C1fD73704Bf97983c60FfB3790C82489a5D7B8',
  VAULT_FACTORY: '0x475984eb4672eb45BDf8750848B91FB113fdD8de',
  VAULT_IMPL: '0x317aA10528Ff675eF4C358ea6a5B7B5494325733',
  ADMIN_SAFE: '0x8AfeBF3781AC142e846Ef7b52EAb85a607eD58BE',
};

// Vaults
const VAULTS = {
  'ycdeal2': '0x98FFBD67fb84506c630a77b901ACeA78CC917470',
  'ycdeal3': '0xB9C7C84A1Aa0dD40b5B38Aae815AD0CDD2E5F88a',
};
```

---

## Adding a New Vault

When deploying a new vault, copy the template below:

1. Add a row to the **Vault Overview** table
2. Copy the section below and fill in the values
3. Add the address to the **Quick Reference** JS object
4. Update the `Last Updated` date

```markdown
---

## Vault #N: [vault-name] ([symbol])

| Property | Value |
|----------|-------|
| **Address** | `0x...` |
| **Deployed** | YYYY-MM-DD |
| **Fixed APY** | X% (X00 bps) |
| **Min Deposit** | 100 USDC |
| **Max Capacity** | X USDC |
| **Safe TX Hash** | `0x...` |

### Timeline (KST)

| Phase | Date/Time | Unix Timestamp |
|-------|-----------|----------------|
| Collection Start | YYYY-MM-DD HH:MM:SS | |
| Collection End | YYYY-MM-DD HH:MM:SS | |
| Interest Start | YYYY-MM-DD HH:MM:SS | |
| Withdrawal Start | YYYY-MM-DD HH:MM:SS | |

### Interest Schedule

| Period | End Date (KST) | Payment Date (KST) | Unix (End) | Unix (Payment) |
|--------|----------------|---------------------|------------|----------------|
| 1 | | | | |
```

---

## Verification

- Source: `yieldcore_RWA_contracts/v2_without_proxy`
- Compiler: Solidity 0.8.24
- EVM: Cancun
- Optimizer: Enabled
- All contracts verified on Etherscan
