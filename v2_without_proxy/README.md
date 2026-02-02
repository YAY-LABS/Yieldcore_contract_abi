# YieldCore RWA Protocol

A decentralized Real World Asset (RWA) investment protocol built on Ethereum, enabling fixed-term vaults with monthly interest payments and ERC-4626 compliant shares.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Interface                            │
└─────────────────────────────────────────────────────────────────┘
                               │
        ┌──────────────────────┴──────────────────────┐
        ▼                                             ▼
┌───────────────┐                            ┌───────────────────┐
│  VaultFactory │                            │   PoolManager     │
│  (Creates     │◄───────────────────────────┤   (Capital Ops)   │
│   Vaults)     │                            │                   │
└───────┬───────┘                            └─────────┬─────────┘
        │                                             │
        │                                             │
        ▼                                             ▼
┌───────────────┐    ┌───────────────────┐   ┌───────────────────┐
│  VaultBeacon  │    │  VaultRegistry    │   │   LoanRegistry    │
│  (Upgrades)   │    │  (Metadata)       │   │   (External Inv.  │
└───────┬───────┘    └───────────────────┘   │    Metadata)      │
        │                                    └───────────────────┘
        ▼
┌───────────────────────────────────────────────────────────────┐
│                        RWAVaultV1                              │
│  (ERC-4626 Fixed-Term Vault with Monthly Interest)            │
│                                                                │
│  Phase: Collecting ──► Active ──► Matured                      │
│         (Deposit)    (Interest)  (Withdraw)                    │
└───────────────────────────────────────────────────────────────┘
```

## Core Components

### Vault Layer

- **RWAVault**: ERC-4626 fixed-term vault with Phase-based lifecycle
  - **Collecting Phase**: Users deposit USDC during collection period
  - **Active Phase**: Monthly interest claims available
  - **Matured Phase**: Principal + remaining interest withdrawal

### Core Layer

- **PoolManager**: Orchestrates capital deployment and return from external investments
- **LoanRegistry**: Tracks external investment metadata (KRW conversion, RWA purchases)
- **VaultRegistry**: Stores vault metadata and tracks TVL

### Factory Layer

- **VaultFactory**: Deploys new RWA vaults

## Key Features

### For Depositors

- Deposit USDC during collection phase to earn fixed APY
- ERC-4626 compliant shares for DeFi composability
- **Monthly interest claims** during active phase
  - `claimInterest()`: Claim all available months at once
  - `claimSingleMonth()`: Claim one month at a time
- **Principal withdrawal at maturity** with automatic remaining interest claim
- **Whitelist support** for permissioned vaults
- **Per-user deposit caps** (min/max) for fair distribution
- **Secondary market ready**: Per-second share value calculation

### For Protocol

- Role-based access control (Admin, Curator, Operator)
- Upgradeable via UUPS proxy pattern
- Pausable for emergency situations
- Protocol fee on interest income (currently disabled)

### For Risk Management

- Phase-based vault lifecycle prevents early withdrawal
- Configurable collection periods and term durations
- Fixed APY with guaranteed interest rate

## Vault Lifecycle

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│   COLLECTING   │────►│     ACTIVE     │────►│    MATURED     │
│                │     │                │     │                │
│ • Deposits OK  │     │ • No deposits  │     │ • No deposits  │
│ • No withdraw  │     │ • No withdraw  │     │ • Withdraw OK  │
│ • No interest  │     │ • Claim monthly│     │ • Claim final  │
│                │     │   interest     │     │   interest     │
└────────────────┘     └────────────────┘     └────────────────┘
     │                        │                      │
     │ collectionEndTime      │ maturityTime         │
     └────────────────────────┴──────────────────────┘
```

## Roles

| Role                 | Permissions                                   |
| -------------------- | --------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Full protocol administration                  |
| `CURATOR_ROLE`       | Manage external investments, create loans     |
| `OPERATOR_ROLE`      | Record repayments                             |
| `POOL_MANAGER_ROLE`  | Internal cross-contract calls                 |
| `PAUSER_ROLE`        | Pause/unpause contracts                       |

## Installation

```bash
# Clone repository
git clone <repository-url>
cd yieldcore_RWA_contracts/v1

# Install dependencies
forge install

# Build
forge build

# Test
forge test
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/vault/RWAVaultV1.t.sol

# Run security tests (attack scenarios)
forge test --match-path test/security/*.sol -vvv

# Run with gas report
forge test --gas-report

# Run coverage
forge coverage
```

### Security Tests

Security tests in `test/security/` cover adversarial scenarios:
- Reentrancy attacks
- Share manipulation / ERC4626 inflation attacks
- Interest calculation exploits
- Access control bypass attempts
- Flash loan / front-running attacks
- Edge cases (zero division, overflow, etc.)

## Deployment

### Environment Variables

Create a `.env` file:

```bash
PRIVATE_KEY=<deployer-private-key>
ADMIN_ADDRESS=<admin-address>
TREASURY_ADDRESS=<treasury-address>
ASSET_ADDRESS=<usdc-address>
```

### Deploy Protocol

```bash
# Deploy to testnet
forge script script/Deploy.s.sol:DeployYieldCoreRWA \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# Deploy to mainnet (add --slow for safety)
forge script script/Deploy.s.sol:DeployYieldCoreRWA \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify \
  --slow
```

### Create a Vault

```bash
export VAULT_FACTORY_ADDRESS=<deployed-factory-address>
export VAULT_NAME="YieldCore RWA Vault"
export VAULT_SYMBOL="ycRWA"
export COLLECTION_DURATION=604800  # 7 days in seconds
export TERM_DURATION=15552000  # 180 days in seconds
export FIXED_APY=1500  # 15%
export MIN_DEPOSIT=100000000  # 100 USDC
export MAX_CAPACITY=10000000000000  # 10M USDC

forge script script/Deploy.s.sol:CreateVault \
  --rpc-url $RPC_URL \
  --broadcast
```

## Protocol Parameters

### Constants (`RWAConstants.sol`)

| Parameter           | Value      | Description                 |
| ------------------- | ---------- | --------------------------- |
| `BASIS_POINTS`      | 10,000     | Basis points denominator    |
| `MIN_INTEREST_RATE` | 500 (5%)   | Minimum loan interest rate  |
| `MAX_INTEREST_RATE` | 5000 (50%) | Maximum loan interest rate  |
| `MIN_LOAN_TERM`     | 30 days    | Minimum loan duration       |
| `MAX_LOAN_TERM`     | 365 days   | Maximum loan duration       |
| `MAX_LTV`           | 8000 (80%) | Maximum loan-to-value ratio |
| `MAX_PROTOCOL_FEE`  | 2000 (20%) | Maximum protocol fee        |
| `MAX_TARGET_APY`    | 5000 (50%) | Maximum target/fixed APY    |

### Vault Parameters

| Parameter            | Description                              |
| -------------------- | ---------------------------------------- |
| `collectionEndTime`  | When deposit collection phase ends       |
| `interestStartTime`  | When interest starts accruing            |
| `termDuration`       | Duration of the investment term          |
| `fixedAPY`           | Fixed annual percentage yield (in bps)   |
| `minDeposit`         | Minimum deposit amount                   |
| `maxCapacity`        | Maximum vault capacity                   |
| `whitelistEnabled`   | Enable/disable whitelist for deposits    |
| `minDepositPerUser`  | Minimum deposit per user (0 = no limit)  |
| `maxDepositPerUser`  | Maximum deposit per user (0 = no limit)  |

## Investment Lifecycle

1. **Collection Phase**
   - Users deposit USDC to RWA vault, receive shares
   - Deposits accepted until `collectionEndTime`

2. **Activation**
   - Admin activates vault after collection ends

3. **Capital Deployment**
   - PoolManager deploys capital to external investments
   - Funds converted to KRW for RWA purchases
   - LoanRegistry tracks investment metadata

4. **Active Phase**
   - Users claim monthly interest (fixedAPY / 12 per month)
   - Interest deposited to vault by operator

5. **Capital Return**
   - External investments mature, capital returned
   - PoolManager returns capital to vault

6. **Maturity**
   - Admin matures vault after `maturityTime`
   - Users redeem shares for principal + remaining interest

## Interest Calculation

### Monthly Interest (for claims)

```
monthlyInterest = principal * fixedAPY / 12 / 10000
```

Example for 120,000 USDC at 15% APY:
- Monthly interest = 120,000 * 1500 / 12 / 10000 = 1,500 USDC
- 6-month total = 9,000 USDC

### Share Value (for secondary market)

Share value is calculated **per-second** for precise secondary market pricing:

```
accruedInterest = totalPrincipal * fixedAPY * elapsedSeconds / (365 days) / 10000
totalAssets = totalPrincipal + accruedInterest - totalInterestPaid
sharePrice = totalAssets / totalSupply
```

See [INTEREST_CLAIMING.md](docs/INTEREST_CLAIMING.md) for detailed documentation.

## Security Considerations

- All contracts use OpenZeppelin's battle-tested libraries
- Non-upgradeable contracts for simplicity and security
- ReentrancyGuard on all external functions
- Access control on all privileged operations
- Pausable for emergency response
- Phase-based restrictions prevent unauthorized withdrawals
- No external oracles (off-chain underwriting)
- **ERC4626 inflation attack mitigation** via `totalPrincipal` tracking
- **Balance checks** before interest claims to prevent over-withdrawal
- **Division by zero protection** in share calculations
- **Security tests** covering attack scenarios (see `test/security/`)

## Contract Addresses

### Testnet (Sepolia)

| Contract        | Address |
| --------------- | ------- |
| VaultFactory    | TBD     |
| PoolManager     | TBD     |
| LoanRegistry    | TBD     |
| VaultRegistry   | TBD     |

### Mainnet

| Contract        | Address |
| --------------- | ------- |
| VaultFactory    | TBD     |
| PoolManager     | TBD     |
| LoanRegistry    | TBD     |
| VaultRegistry   | TBD     |

## License

MIT
