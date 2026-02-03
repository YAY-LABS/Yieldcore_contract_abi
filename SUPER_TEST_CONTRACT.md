# YieldCore RWA Test Vault - Sepolia

**Network:** Sepolia (Chain ID: 11155111)
**Deployed:** 2026-02-03

---

## Contract Information

| Item | Value |
|------|-------|
| **Vault Address** | `0x947857d81e2B3a18E9219aFbBF27118B679b37ef` |
| **Etherscan** | [View Contract](https://sepolia.etherscan.io/address/0x947857d81e2B3a18E9219aFbBF27118B679b37ef) |
| **Asset (MockUSDC)** | `0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7` |
| **VaultFactory** | `0xd47Fc65B0bd112E0fe4deFBFeb26a5dd910ecF32` |
| **VaultRegistry** | `0x384AaF500820EDf7F9965e1C621C0CA1BE95a9C0` |
| **PoolManager** | `0xC0E1759038f01fB0E097DB5377b0b5BA8742A41D` |
| **LoanRegistry** | `0x5829717A6BB63Ae1C45E98A77b07Bb25bb33DF49` |

---

## Vault Configuration

| Setting | Value |
|---------|-------|
| Name | YieldCore Whitelist Test |
| Symbol | ycWL |
| APY | 15% |
| Min Deposit | 1,000 USDC |
| Max Per User | 100,000 USDC |
| Max Capacity | 1,000,000 USDC |

---

## Whitelisted Addresses

| Address |
|---------|
| `0x0aeEadFba133b7d4C85cd154fA8e953093Ac1189` |
| `0x1c5a21FF819F8B00970aF05c7f0D10F8DBb4704D` |

---

## Timeline (February 3, 2026 KST)

| Time (KST) | Event | Description |
|------------|-------|-------------|
| 1:00 PM | **Collection Start** | Deposits become available for whitelisted addresses |
| 3:00 PM | Open Deposit | Whitelist disabled, anyone can deposit |
| 4:00 PM | Collection End | Deposits closed |
| 5:00 PM | Interest Start | Interest accrual begins |
| 6:00 PM | Round 1 End | First interest period ends |
| 6:30 PM | Round 1 Payment | First interest claimable |
| 7:00 PM | Round 2 End | Second interest period ends |
| 7:30 PM | Round 2 Payment | Second interest claimable |
| 8:00 PM | Round 3 End (Maturity) | Final interest period ends |
| 8:30 PM | Withdrawal Start | Principal + final interest withdrawable |

---

## How to Test

### 1. Get Test USDC (MockUSDC)

MockUSDC contract: `0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7`

You need to mint MockUSDC to your wallet. Contact admin for minting or use the mint function if you have permission.

### 2. Approve USDC
Before depositing, approve the vault to spend your USDC:
```
Contract: 0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7
Function: approve(address spender, uint256 amount)
- spender: 0x947857d81e2B3a18E9219aFbBF27118B679b37ef (vault address)
- amount: Amount in USDC (6 decimals). e.g., 1000000000 = 1,000 USDC
```

### 3. Deposit (after 1:00 PM KST)
```
Contract: 0x947857d81e2B3a18E9219aFbBF27118B679b37ef
Function: deposit(uint256 assets, address receiver)
- assets: Amount in USDC (6 decimals). e.g., 1000000000 = 1,000 USDC
- receiver: Your wallet address
```

### 4. Claim Interest (after each payment time)
```
Function: claimInterest()
- Claims all available interest up to current period
```

### 5. Withdraw (after 8:30 PM)
```
Function: redeem(uint256 shares, address receiver, address owner)
- shares: Your share balance (check balanceOf)
- receiver: Where to receive USDC
- owner: Your wallet address
```

---

## Important Notes

- **Deposits are NOT available until 1:00 PM KST on Feb 3**
- Whitelist period: 1:00 PM ~ 3:00 PM KST (only whitelisted addresses)
- Open deposit period: 3:00 PM ~ 4:00 PM KST (anyone can deposit)
- Minimum deposit is 1,000 USDC
- Maximum deposit per user is 100,000 USDC
- Interest is paid in 3 rounds (1 hour each)
- Each interest payment is available 30 minutes after the round ends
- Principal withdrawal is available 30 minutes after maturity (8:30 PM)

---

## Contract Interfaces

### Read Functions
- `collectionStartTime()` - When deposits become available
- `collectionEndTime()` - When deposits close
- `balanceOf(address)` - Check your share balance
- `convertToAssets(uint256 shares)` - Convert shares to USDC value
- `getClaimableInterest(address)` - Check claimable interest
- `currentPhase()` - Check vault phase (0=Collecting, 1=Active, 2=Matured)
- `isWhitelisted(address)` - Check if address is whitelisted
- `whitelistEnabled()` - Check if whitelist is active

### Write Functions
- `deposit(uint256 assets, address receiver)` - Deposit USDC
- `claimInterest()` - Claim accrued interest
- `redeem(uint256 shares, address receiver, address owner)` - Withdraw all

---

## Admin Actions Required

| Time | Action |
|------|--------|
| 3:00 PM | `setWhitelistEnabled(false)` - Open deposits to everyone |
| 4:00 PM+ | `activateVault()` - Transition to Active phase |
| 8:00 PM+ | `matureVault()` - Transition to Matured phase |
