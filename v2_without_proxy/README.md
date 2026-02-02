# YieldCore RWA Protocol (v2)

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
│  (EIP-1167    │◄───────────────────────────┤   (Capital Ops)   │
│   Clones)     │                            │                   │
└───────┬───────┘                            └─────────┬─────────┘
        │                                             │
        │                                             │
        ▼                                             ▼
┌───────────────┐    ┌───────────────────┐   ┌───────────────────┐
│ RWAVault      │    │  VaultRegistry    │   │   LoanRegistry    │
│ Implementation│    │  (Metadata)       │   │   (External Inv.  │
└───────┬───────┘    └───────────────────┘   │    Metadata)      │
        │                                    └───────────────────┘
        ▼
┌───────────────────────────────────────────────────────────────┐
│                        RWAVault (Clone)                        │
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
  - Uses EIP-1167 minimal proxy (clone) pattern for gas-efficient deployment

### Core Layer

- **PoolManager**: Orchestrates capital deployment and return with timelock security
  - Capital deployment requires announcement + delay (1h ~ 7d)
  - Centralized control for all vault operations
- **LoanRegistry**: Tracks external investment metadata (KRW conversion, RWA purchases)
- **VaultRegistry**: Stores vault metadata and tracks TVL

### Factory Layer

- **VaultFactory**: Deploys new RWA vaults using EIP-1167 clone pattern
  - ~90% gas savings compared to full contract deployment
  - Each vault is a minimal proxy pointing to implementation

## Key Features

### For Depositors

- Deposit USDC during collection phase to earn fixed APY
- ERC-4626 compliant shares for DeFi composability
- **Collection start time control**: Deposits only allowed after `collectionStartTime`
- **Monthly interest claims** during active phase
  - `claimInterest()`: Claim all available months at once
  - `claimSingleMonth()`: Claim one month at a time
- **Principal withdrawal at maturity** with automatic remaining interest claim
- **Whitelist support** for permissioned vaults
- **Per-user deposit caps** (min/max) for fair distribution
- **Secondary market ready**: Per-second share value calculation

### For Protocol

- Role-based access control (Admin, Curator, Operator, Pauser)
- **Non-upgradeable** contracts (clone pattern, not proxy)
- Pausable for emergency situations
- Protocol fee on interest income (configurable)
- **Capital deployment timelock** for security (1h minimum delay)

### For Risk Management

- Phase-based vault lifecycle prevents early withdrawal
- Configurable collection periods and term durations
- Fixed APY with guaranteed interest rate
- **Asset recovery functions** for stuck funds:
  - `recoverAssetDust()`: Recover USDC dust after all shares burned
  - `recoverETH()`: Recover accidentally sent ETH
  - `recoverERC20()`: Recover non-USDC tokens

## Vault Lifecycle

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│   COLLECTING   │────►│     ACTIVE     │────►│    MATURED     │
│                │     │                │     │                │
│ • Deposits OK  │     │ • No deposits  │     │ • No deposits  │
│   (after start)│     │ • No withdraw  │     │ • Withdraw OK  │
│ • No withdraw  │     │ • Claim monthly│     │ • Claim final  │
│ • No interest  │     │   interest     │     │   interest     │
└────────────────┘     └────────────────┘     └────────────────┘
     │                        │                      │
     │ activateVault()        │ matureVault()        │
     │ (after collectionEnd)  │ (after maturity)     │
     └────────────────────────┴──────────────────────┘
```

## Roles

| Role                 | Permissions                                        |
| -------------------- | -------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Full protocol administration, vault lifecycle      |
| `CURATOR_ROLE`       | Capital deployment (announce/execute/cancel)       |
| `OPERATOR_ROLE`      | Return capital, deposit interest, record repayment |
| `PAUSER_ROLE`        | Pause/unpause contracts                            |

## Installation

```bash
# Clone repository
git clone <repository-url>
cd yieldcore_RWA_contracts/v2_without_proxy

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
forge test --match-path test/unit/vault/RWAVault.t.sol

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
SEPOLIA_RPC_URL=<rpc-url>
```

### Deploy Protocol

```bash
# Deploy to testnet
forge script script/Deploy.s.sol:DeployYieldCoreRWA \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Create a Vault

```bash
export VAULT_FACTORY_ADDRESS=<deployed-factory-address>

forge script script/CreateWhitelistVault.s.sol:CreateWhitelistVault \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast
```

## Protocol Parameters

### Constants (`RWAConstants.sol`)

| Parameter              | Value      | Description                     |
| ---------------------- | ---------- | ------------------------------- |
| `BASIS_POINTS`         | 10,000     | Basis points denominator        |
| `MIN_INTEREST_RATE`    | 100 (1%)   | Minimum loan interest rate      |
| `MAX_INTEREST_RATE`    | 5000 (50%) | Maximum loan interest rate      |
| `MIN_LOAN_TERM`        | 30 days    | Minimum loan duration           |
| `MAX_LOAN_TERM`        | 365 days   | Maximum loan duration           |
| `MAX_LTV`              | 8000 (80%) | Maximum loan-to-value ratio     |
| `MAX_PROTOCOL_FEE`     | 1000 (10%) | Maximum protocol fee            |
| `MAX_TARGET_APY`       | 5000 (50%) | Maximum target/fixed APY        |
| `MIN_DEPLOYMENT_DELAY` | 1 hour     | Minimum capital deployment delay|
| `MAX_DEPLOYMENT_DELAY` | 7 days     | Maximum capital deployment delay|

### Vault Parameters

| Parameter             | Description                                    |
| --------------------- | ---------------------------------------------- |
| `collectionStartTime` | When deposits become allowed (0 = immediate)   |
| `collectionEndTime`   | When deposit collection phase ends             |
| `interestStartTime`   | When interest starts accruing                  |
| `termDuration`        | Duration of the investment term (informational)|
| `fixedAPY`            | Fixed annual percentage yield (in bps)         |
| `minDeposit`          | Minimum deposit amount                         |
| `maxCapacity`         | Maximum vault capacity                         |
| `whitelistEnabled`    | Enable/disable whitelist for deposits          |
| `minDepositPerUser`   | Minimum deposit per user (0 = no limit)        |
| `maxDepositPerUser`   | Maximum deposit per user (0 = no limit)        |
| `withdrawalStartTime` | When principal withdrawal is allowed           |
| `deploymentDelay`     | Timelock delay for capital deployment          |

## Capital Deployment (Timelock)

Capital deployment uses a timelock mechanism for security:

```
1. Curator calls announceDeployCapital(vault, amount, recipient)
   └── Records pending deployment with executeTime = now + delay

2. Wait for deploymentDelay (default: 1 hour)

3. Curator calls executeDeployCapital(vault)
   └── Transfers funds to recipient

(Optional) Curator calls cancelDeployCapital(vault) to cancel
```

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
- **Non-upgradeable** contracts (EIP-1167 clone pattern)
- ReentrancyGuard on all external functions
- Access control on all privileged operations
- Pausable for emergency response
- Phase-based restrictions prevent unauthorized withdrawals
- No external oracles (off-chain underwriting)
- **ERC4626 inflation attack mitigation** via `totalPrincipal` tracking
- **Balance checks** before interest claims to prevent over-withdrawal
- **Division by zero protection** in share calculations
- **Capital deployment timelock** prevents unauthorized fund movement
- **Security tests** covering attack scenarios (see `test/security/`)

## Contract Addresses

### Testnet (Sepolia)

| Contract           | Address                                      |
| ------------------ | -------------------------------------------- |
| VaultFactory       | `0xd47Fc65B0bd112E0fe4deFBFeb26a5dd910ecF32` |
| PoolManager        | `0xDf83371FCBbBE09CE7BE80c0625932340265d90E` |
| LoanRegistry       | `0x58d013c92f31B074df22BCD1fA3f4BB52bF967ca` |
| VaultRegistry      | `0x3c22abA4D225E09103DC9eFFC4Bf3e2Cd802d301` |
| RWAVault (Impl)    | `0x409a9F2431Baa91b2Ac9666d435056A84fa334Cb` |
| USDC (Circle Test) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |

### Mainnet

| Contract        | Address |
| --------------- | ------- |
| VaultFactory    | TBD     |
| PoolManager     | TBD     |
| LoanRegistry    | TBD     |
| VaultRegistry   | TBD     |

## License

MIT
