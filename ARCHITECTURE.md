# Yieldcore RWA Vault - Architecture Guide

> **Contract Version**: v2_without_proxy
> **Standard**: ERC-4626 Tokenized Vault
> **Last Updated**: 2026-02-02

---

## ⚠️ CRITICAL: Share Token Warning

> **YOUR SHARE TOKENS = YOUR MONEY**
>
> The Yieldcore vault follows the ERC-4626 standard. When you deposit USDC, you receive **share tokens** (e.g., `ycRWA-SV1`).
>
> **These share tokens represent your:**
> - Principal (deposited USDC)
> - Accrued interest
> - Withdrawal rights
>
> **If you lose, transfer, or burn your shares, you PERMANENTLY lose access to your funds.**

### Do NOT:

| Action | Consequence |
|--------|-------------|
| ❌ Transfer shares to another wallet | You lose ownership of your deposit |
| ❌ Send shares to a wrong address | Funds are unrecoverable |
| ❌ Approve unlimited allowance to untrusted contracts | They can steal your shares |
| ❌ Interact with unknown contracts that request share approval | Potential scam |

### Safe Practices:

| Action | Why |
|--------|-----|
| ✅ Keep shares in your wallet | Maintain ownership |
| ✅ Verify contract addresses before approval | Prevent theft |
| ✅ Only approve exact amounts needed | Limit exposure |
| ✅ Check your share balance regularly | Detect unauthorized transfers |

### Check Your Shares:

```solidity
// Your share balance
uint256 myShares = vault.balanceOf(myWallet);

// What your shares are worth (including interest)
(, uint256 grossValue, , uint256 netValue, ) = vault.getShareInfo(myWallet);
```

---

## Contract Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Yieldcore RWA Protocol                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    creates    ┌──────────────────────────┐   │
│  │ VaultFactory │──────────────>│ RWAVault (ERC-4626)      │   │
│  └──────────────┘               │                          │   │
│                                 │ • Deposit/Withdraw       │   │
│  ┌──────────────┐    tracks     │ • Monthly Interest       │   │
│  │VaultRegistry │<──────────────│ • Phase Management       │   │
│  └──────────────┘               │ • Whitelist/Allocation   │   │
│                                 └──────────────────────────┘   │
│                                           │                     │
│  ┌──────────────┐    manages funds        │                     │
│  │ PoolManager  │<────────────────────────┘                     │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │LoanRegistry  │  (tracks deployed loans)                      │
│  └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Core Contracts

| Contract | Purpose |
|----------|---------|
| **RWAVault** | Main vault contract. Handles deposits, withdrawals, interest claims. ERC-4626 compliant. |
| **VaultFactory** | Creates new vault instances with configured parameters. |
| **VaultRegistry** | Tracks all deployed vaults. Query interface for discovery. |
| **PoolManager** | Manages fund deployment to real-world assets. Admin controlled. |
| **LoanRegistry** | Records loan deployments and repayments. |

---

## Vault Lifecycle (4 Phases)

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Collecting  │───>│   Active    │───>│   Matured   │    │  Defaulted  │
│   (0)       │    │    (1)      │    │    (2)      │    │    (3)      │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     │                   │                  │                   │
     ▼                   ▼                  ▼                   ▼
 • Deposits         • No deposits      • No deposits      • Loan failed
 • No withdrawals   • No withdrawals   • Full withdrawal  • Partial recovery
 • No interest      • Interest accrues • Interest claim   • Pro-rata distribution
```

### Phase Details

#### Phase 0: Collecting
- **Duration**: `collectionStartTime` → `collectionEndTime`
- **Deposits**: ✅ Allowed (subject to whitelist/caps)
- **Withdrawals**: ❌ Not allowed
- **Interest**: ❌ Not accruing yet

```solidity
// Check if deposits are open
uint256 start = vault.collectionStartTime();  // 0 = immediate
uint256 end = vault.collectionEndTime();
bool canDeposit = (start == 0 || block.timestamp >= start) && block.timestamp < end;
```

#### Phase 1: Active
- **Duration**: After admin activates → `maturityTime`
- **Deposits**: ❌ Collection ended
- **Withdrawals**: ❌ Funds deployed
- **Interest**: ✅ Accrues monthly, claimable

```solidity
// Claim monthly interest
uint256 pending = vault.getPendingInterest(myWallet);
if (pending > 0) {
    vault.claimInterest();  // Claims all available months
}
```

#### Phase 2: Matured
- **Trigger**: `block.timestamp >= maturityTime`
- **Deposits**: ❌ Closed
- **Withdrawals**: ✅ Full principal + remaining interest
- **Interest**: ✅ All remaining interest claimable

```solidity
// Withdraw everything
uint256 shares = vault.balanceOf(myWallet);
vault.redeem(shares, myWallet, myWallet);
```

#### Phase 3: Defaulted
- **Trigger**: Admin declares default (loan not repaid)
- **Recovery**: Pro-rata distribution of recovered funds
- **Interest**: Stops accruing

---

## ERC-4626 Token Model

### How Shares Work

```
Deposit Flow:
┌──────────┐    1000 USDC    ┌──────────┐
│   User   │ ───────────────>│  Vault   │
│          │                 │          │
│          │<─────────────── │          │
└──────────┘   1000 shares   └──────────┘
              (1:1 initially)

Interest Accrual:
┌──────────┐                 ┌──────────┐
│   User   │   1000 shares   │  Vault   │
│          │ ═══════════════>│          │
│          │                 │ totalAssets increases
│          │   Value grows   │ (interest added)
└──────────┘   over time     └──────────┘

Redemption:
┌──────────┐   1000 shares   ┌──────────┐
│   User   │ ───────────────>│  Vault   │
│          │                 │          │
│          │<─────────────── │          │
└──────────┘  1000 + interest└──────────┘
              (USDC returned)
```

### Share Value Calculation

```solidity
// Gross value = Principal + Accrued Interest
// Net value = Gross value - Already Claimed Interest

(uint256 shares,
 uint256 grossValue,      // Total value (principal + all interest)
 uint256 claimedInterest, // Interest already withdrawn
 uint256 netValue,        // Actual redeemable value
 uint256 lastClaimMonth
) = vault.getShareInfo(userAddress);
```

**Important**: When you claim interest, it reduces your `netValue` but shares remain the same.

```
Example:
- Deposit: 1,000 USDC
- After 6 months: grossValue = 1,090 USDC (9% interest)
- Claim 90 USDC interest
- Now: grossValue = 1,090, claimedInterest = 90, netValue = 1,000
- At maturity, redeem shares → receive 1,000 USDC (principal only)
```

---

## Interest System

### Monthly Interest Calculation

```
Monthly Interest = Principal × (APY / 12 / 10000)

Example:
- Principal: 10,000 USDC
- APY: 1800 (18% in basis points)
- Monthly: 10,000 × (1800 / 12 / 10000) = 150 USDC
```

### Interest Payment Schedule

```solidity
// Get all payment dates
uint256[] memory dates = vault.getInterestPaymentDates();

// Check claimable months
uint256 months = vault.getClaimableMonths(myWallet);

// Check pending interest amount
uint256 pending = vault.getPendingInterest(myWallet);
```

### Claiming Options

```solidity
// Option 1: Claim all available months at once
vault.claimInterest();

// Option 2: Claim one month at a time
vault.claimSingleMonth();
```

### ⚠️ IMPORTANT: Direct Wallet Call Required

**Claim functions use `msg.sender` - NOT a receiver parameter!**

```solidity
function claimInterest() external {
    DepositInfo storage info = _depositInfos[msg.sender];  // ← Looks up msg.sender
    // ...
    IERC20(asset()).safeTransfer(msg.sender, interestAmount);  // ← Sends to msg.sender
}
```

| ❌ Does NOT Work | ✅ Works |
|------------------|----------|
| Contract calls `claimInterest()` for user | User calls `claimInterest()` directly from wallet |
| Bot/relayer calls on behalf of user | User signs and submits transaction themselves |

**Why?**
- Security: Prevents contracts from stealing user interest
- Simplicity: No approval/delegation mechanism needed
- The `deposit()` function has `receiver` parameter for flexibility
- But `claim/withdraw` are intentionally restricted to direct calls

---

## Access Control

### Deposit Restrictions

```
┌─────────────────────────────────────────────────────────────┐
│                    Can User Deposit?                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Is vault in Collecting phase?                           │
│     └─ NO → ❌ Reject                                        │
│                                                              │
│  2. Has collection started?                                  │
│     └─ collectionStartTime > now → ❌ Reject                │
│                                                              │
│  3. Has collection ended?                                    │
│     └─ collectionEndTime <= now → ❌ Reject                  │
│                                                              │
│  4. Does user have allocation?                               │
│     └─ YES → ✅ Bypass whitelist, check allocation cap      │
│     └─ NO → Continue to step 5                               │
│                                                              │
│  5. Is whitelist enabled?                                    │
│     └─ YES → Is user whitelisted?                           │
│              └─ NO → ❌ Reject                               │
│                                                              │
│  6. Check capacity limits                                    │
│     └─ Vault capacity, per-user min/max                     │
│                                                              │
│  7. ✅ Deposit allowed                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Whitelist vs Allocation

| Feature | Whitelist | Allocated Cap |
|---------|-----------|---------------|
| Purpose | General access control | VIP/reserved capacity |
| Capacity | Shares public pool | Dedicated allocation |
| Min/Max limits | Applied | Bypassed |
| Admin function | `setWhitelist()` | `setAllocation()` |

---

## Contract Addresses (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| **SuperVault (Test)** | `0x90facD5C5b8b73567aCF49d6337805E762297c04` |
| USDC (Mock) | `0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7` |
| VaultFactory | `0xd47Fc65B0bd112E0fe4deFBFeb26a5dd910ecF32` |
| VaultRegistry | `0x384AaF500820EDf7F9965e1C621C0CA1BE95a9C0` |
| PoolManager | `0xC0E1759038f01fB0E097DB5377b0b5BA8742A41D` |

---

## Security Considerations

### For Users

1. **Protect your shares** - They represent your entire deposit
2. **Verify addresses** - Double-check before any transaction
3. **Understand phases** - Know when you can deposit/withdraw
4. **Monitor interest** - Claim regularly or let it accumulate

### For Integrators

1. **Use `receiver` parameter** - Direct shares to user's wallet
2. **Handle reverts** - Check `maxDeposit()` before attempting
3. **Whitelist awareness** - User (receiver) must be whitelisted, not your contract
4. **Phase checks** - Verify vault is in correct phase before transactions

---

## Quick Reference

### View Functions

```solidity
// Vault info
vault.currentPhase()           // 0-3
vault.totalAssets()            // Total USDC in vault
vault.maxCapacity()            // Max deposit limit
vault.fixedAPY()               // APY in basis points

// Timing
vault.collectionStartTime()    // When deposits open
vault.collectionEndTime()      // When deposits close
vault.maturityTime()           // When term ends

// User info
vault.balanceOf(user)          // Share balance
vault.getShareInfo(user)       // Detailed position
vault.getPendingInterest(user) // Claimable interest
vault.maxDeposit(user)         // How much can deposit
```

### Write Functions

```solidity
// Depositing
vault.deposit(amount, receiver)  // Deposit USDC, get shares

// Interest
vault.claimInterest()            // Claim all available
vault.claimSingleMonth()         // Claim one month

// Withdrawing (Matured phase only)
vault.withdraw(assets, receiver, owner)  // By USDC amount
vault.redeem(shares, receiver, owner)    // By share amount
```

---

## Related Documents

- [README.md](./README.md) - Quick start and code examples
- [RWAVault.json](./RWAVault.json) - Full ABI
- [RWAVault.minimal.json](./RWAVault.minimal.json) - Essential functions only
