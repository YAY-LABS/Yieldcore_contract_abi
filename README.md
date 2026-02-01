# Yieldcore RWA Vault - Integration Guide

> **Version**: v2_without_proxy
> **Network**: Sepolia Testnet (Chain ID: 11155111)
> **Last Updated**: 2026-02-02

---

## Test Vault (Sepolia)

| Contract | Address |
|----------|---------|
| **SuperVault (Test)** | `0x90facD5C5b8b73567aCF49d6337805E762297c04` |
| USDC (Mock) | `0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7` |
| VaultRegistry | `0x384AaF500820EDf7F9965e1C621C0CA1BE95a9C0` |

> **Note**: This is a test vault on Sepolia. USDC is a mock token for testing purposes.

---

## Get Test USDC (Faucet)

The Mock USDC contract allows **anyone to mint** tokens for testing. No faucet approval needed!

### Using Foundry (cast)

```bash
# Mint 10,000 USDC to your address
cast send 0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7 \
  "mint(address,uint256)" \
  0xYourAddress \
  10000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check your balance
cast call 0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7 \
  "balanceOf(address)" \
  0xYourAddress \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

### Using ethers.js

```typescript
const USDC_ADDRESS = '0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7';

// MockERC20 has a public mint function
const mockUsdcAbi = [
  'function mint(address to, uint256 amount) external',
  'function balanceOf(address) view returns (uint256)'
];

const usdc = new ethers.Contract(USDC_ADDRESS, mockUsdcAbi, signer);

// Mint 10,000 USDC (6 decimals)
const amount = ethers.parseUnits('10000', 6);
await usdc.mint(signer.address, amount);

// Check balance
const balance = await usdc.balanceOf(signer.address);
console.log('Balance:', ethers.formatUnits(balance, 6), 'USDC');
```

### Using web3.py

```python
USDC_ADDRESS = '0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7'

mock_usdc_abi = [
    {
        "inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "uint256"}],
        "name": "mint",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]

usdc = w3.eth.contract(address=USDC_ADDRESS, abi=mock_usdc_abi)

# Mint 10,000 USDC
amount = 10000 * 10**6  # 6 decimals
tx = usdc.functions.mint(your_address, amount).build_transaction({
    'from': your_address,
    'nonce': w3.eth.get_transaction_count(your_address),
    'gas': 100000,
})
signed = w3.eth.account.sign_transaction(tx, private_key)
tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
```

> **Tip**: USDC uses 6 decimals. 1 USDC = 1,000,000 (1e6)

---

## Quick Start: How to Deposit

### Step 1: Check Vault Status

Before depositing, verify the vault is in **Collecting** phase and collection has started:

```solidity
// Check current phase (0 = Collecting, 1 = Active, 2 = Matured, 3 = Defaulted)
uint8 phase = vault.currentPhase();
require(phase == 0, "Vault not collecting");

// Check if collection has started (0 = immediate deposit allowed)
uint256 collectionStart = vault.collectionStartTime();
require(collectionStart == 0 || block.timestamp >= collectionStart, "Collection not started");

// Check if collection hasn't ended
uint256 collectionEnd = vault.collectionEndTime();
require(block.timestamp < collectionEnd, "Collection ended");
```

### Step 2: Check Your Eligibility

```solidity
// Check whitelist (if enabled)
bool whitelistEnabled = vault.whitelistEnabled();
if (whitelistEnabled) {
    require(vault.isWhitelisted(msg.sender), "Not whitelisted");
}

// Check how much you can deposit
uint256 maxDeposit = vault.maxDeposit(msg.sender);
```

### Step 3: Approve USDC

```solidity
// Approve vault to spend your USDC
IERC20(usdcAddress).approve(vaultAddress, depositAmount);
```

### Step 4: Deposit

```solidity
// Deposit USDC and receive vault shares
// assets: amount of USDC (6 decimals, e.g., 1000 USDC = 1000000000)
// receiver: address to receive the shares (usually msg.sender)
uint256 shares = vault.deposit(assets, receiver);
```

---

## Vault Phases

| Phase | Value | Description |
|-------|-------|-------------|
| Collecting | 0 | Accepting deposits. Collection period active. |
| Active | 1 | Funds deployed. Monthly interest accrues. |
| Matured | 2 | Term ended. Principal + interest withdrawable. |
| Defaulted | 3 | Loan defaulted. Partial recovery possible. |

---

## Key Read Functions

### Vault Configuration

```solidity
// Basic info
string name()                    // Vault name (e.g., "SuperVault Q1 2026")
string symbol()                  // Vault symbol (e.g., "ycRWA-SV1")
address asset()                  // Underlying asset (USDC address)

// Timing
uint256 collectionStartTime()    // When deposits open (0 = immediate)
uint256 collectionEndTime()      // When collection ends
uint256 maturityTime()           // When term ends
uint256 termDuration()           // Duration in seconds

// Capacity & Limits
uint256 maxCapacity()            // Maximum total deposits
uint256 totalAssets()            // Current total deposits
uint256 minDeposit()             // Minimum deposit amount
uint256 fixedAPY()               // APY in basis points (1800 = 18%)
```

### User Position

```solidity
// Get your position
(uint256 shares, uint256 principal, uint256 lastClaimMonth, uint256 depositTime)
    = vault.getDepositInfo(userAddress);

// Get detailed share info (hybrid system)
(uint256 shares, uint256 grossValue, uint256 claimedInterest, uint256 netValue, uint256 lastClaimMonth)
    = vault.getShareInfo(userAddress);

// Get pending interest to claim
uint256 pendingInterest = vault.getPendingInterest(userAddress);

// Get how many months of interest are claimable
uint256 claimableMonths = vault.getClaimableMonths(userAddress);
```

### Bulk Status Check

```solidity
// Get vault status in one call
(uint8 phase, uint256 totalAssets, uint256 totalDeployed, uint256 availableBalance, uint256 totalInterestPaid)
    = vault.getVaultStatus();

// Get vault config in one call
(uint256 collectionEndTime, uint256 interestStartTime, uint256 maturityTime, uint256 termDuration,
 uint256 fixedAPY, uint256 minDeposit, uint256 maxCapacity)
    = vault.getVaultConfig();
```

---

## Write Functions

### Deposit (Collecting Phase Only)

```solidity
// Standard ERC-4626 deposit
// Returns: shares minted to receiver
function deposit(uint256 assets, address receiver) external returns (uint256 shares);

// Example: Deposit 1000 USDC
uint256 shares = vault.deposit(1000 * 1e6, msg.sender);
```

### Claim Interest (Active/Matured Phase)

```solidity
// Claim all available monthly interest
function claimInterest() external returns (uint256 claimed);

// Claim single month's interest
function claimSingleMonth() external;
```

### Withdraw (Matured Phase Only)

```solidity
// Withdraw by specifying asset amount
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

// Withdraw by specifying share amount (redeem)
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
```

---

## Events

```solidity
event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
event InterestClaimed(address indexed user, uint256 amount, uint256 month);
event PhaseChanged(uint8 oldPhase, uint8 newPhase);
```

---

## Code Examples

### JavaScript/TypeScript (ethers.js v6)

```typescript
import { ethers } from 'ethers';
import vaultAbi from './RWAVault.json';
import erc20Abi from './ERC20.json';

const provider = new ethers.JsonRpcProvider('https://ethereum-sepolia-rpc.publicnode.com');
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

const VAULT_ADDRESS = '0x90facD5C5b8b73567aCF49d6337805E762297c04';
const USDC_ADDRESS = '0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7';

const vault = new ethers.Contract(VAULT_ADDRESS, vaultAbi, signer);
const usdc = new ethers.Contract(USDC_ADDRESS, erc20Abi, signer);

// Check vault status
const phase = await vault.currentPhase();
console.log('Phase:', phase); // 0 = Collecting

// Deposit 100 USDC
const amount = ethers.parseUnits('100', 6); // USDC has 6 decimals

// Step 1: Approve
await usdc.approve(VAULT_ADDRESS, amount);

// Step 2: Deposit
const tx = await vault.deposit(amount, signer.address);
await tx.wait();
console.log('Deposited!', tx.hash);
```

### Python (web3.py)

```python
from web3 import Web3
import json

w3 = Web3(Web3.HTTPProvider('https://ethereum-sepolia-rpc.publicnode.com'))

VAULT_ADDRESS = '0x90facD5C5b8b73567aCF49d6337805E762297c04'
USDC_ADDRESS = '0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7'

with open('RWAVault.json') as f:
    vault_abi = json.load(f)
with open('ERC20.json') as f:
    erc20_abi = json.load(f)

vault = w3.eth.contract(address=VAULT_ADDRESS, abi=vault_abi)
usdc = w3.eth.contract(address=USDC_ADDRESS, abi=erc20_abi)

# Check vault status
phase = vault.functions.currentPhase().call()
print(f'Phase: {phase}')  # 0 = Collecting

# Get max deposit
max_deposit = vault.functions.maxDeposit(your_address).call()
print(f'Max deposit: {max_deposit / 1e6} USDC')
```

### Foundry (cast)

```bash
# Check vault phase
cast call 0x90facD5C5b8b73567aCF49d6337805E762297c04 "currentPhase()" --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check collection start time
cast call 0x90facD5C5b8b73567aCF49d6337805E762297c04 "collectionStartTime()" --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Check max deposit for address
cast call 0x90facD5C5b8b73567aCF49d6337805E762297c04 "maxDeposit(address)" 0xYourAddress --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Approve USDC (requires private key)
cast send 0xe505B02c8CdA0D01DD34a7F701C1268093B7bCf7 "approve(address,uint256)" 0x90facD5C5b8b73567aCF49d6337805E762297c04 1000000000 --private-key $PRIVATE_KEY --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Deposit 1000 USDC
cast send 0x90facD5C5b8b73567aCF49d6337805E762297c04 "deposit(uint256,address)" 1000000000 0xYourAddress --private-key $PRIVATE_KEY --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

### Solidity (Contract-to-Contract Integration)

If you're calling the Yieldcore vault from your own smart contract:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldcoreVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function currentPhase() external view returns (uint8);
    function maxDeposit(address receiver) external view returns (uint256);
}

contract YieldcoreIntegration {
    IYieldcoreVault public immutable vault;
    IERC20 public immutable usdc;

    constructor(address _vault, address _usdc) {
        vault = IYieldcoreVault(_vault);
        usdc = IERC20(_usdc);
    }

    /// @notice Deposit USDC to Yieldcore vault on behalf of a user
    /// @dev User must approve this contract to spend their USDC first
    /// @param amount Amount of USDC to deposit (6 decimals)
    /// @param user The user who will receive the vault shares
    function depositFor(uint256 amount, address user) external {
        // 1. Transfer USDC from user to this contract
        usdc.transferFrom(msg.sender, address(this), amount);

        // 2. Approve vault to spend USDC
        usdc.approve(address(vault), amount);

        // 3. Deposit to vault with user as receiver
        //    Shares are minted directly to user's wallet!
        vault.deposit(amount, user);
    }

    /// @notice Check if vault is accepting deposits
    function canDeposit() external view returns (bool) {
        return vault.currentPhase() == 0; // 0 = Collecting
    }
}
```

**Important Notes:**

| Aspect | Explanation |
|--------|-------------|
| `msg.sender` in vault | Your contract address (not the original user) |
| `receiver` parameter | Specifies who gets the shares → set to user's wallet |
| After deposit | User owns shares directly, can claim interest & withdraw themselves |

**Flow Diagram:**

```
┌──────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  User Wallet │──1──>│  Your Contract   │──3──>│ Yieldcore Vault │
│              │      │                  │      │                 │
│  (has USDC)  │      │ depositFor()     │      │ deposit(amount, │
│              │      │                  │      │   userWallet)   │
└──────────────┘      └──────────────────┘      └────────┬────────┘
                                                         │
                              4. Shares minted to ───────┘
                                 User Wallet directly
```

**After Deposit - User Can Directly:**

```solidity
// User calls these directly from their wallet (no intermediate contract needed)
vault.claimInterest();                    // Claim monthly interest
vault.withdraw(amount, myWallet, myWallet);  // Withdraw principal (after maturity)
vault.redeem(shares, myWallet, myWallet);    // Redeem all shares
```

---

## Files in This Repository

| File | Description |
|------|-------------|
| `RWAVault.json` | Full Vault ABI (all functions) |
| `RWAVault.minimal.json` | Minimal ABI (deposit functions only) |
| `ERC20.json` | ERC-20 ABI for USDC approval |
| `README.md` | This documentation |

---

## Support

For questions or issues, please contact the Yieldcore team.
