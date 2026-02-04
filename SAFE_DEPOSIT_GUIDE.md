# Safe Wallet에서 YieldCore Vault 예치하기

> Safe 웹사이트(app.safe.global)에서 RWA Vault에 예치하는 단계별 가이드

## 사전 조건

- Safe Wallet 주소가 Whitelist에 등록되어 있어야 함
- Safe Wallet 주소에 Cap이 할당되어 있어야 함 (allocateCap)
- Safe에 충분한 USDC가 있어야 함
- Collection 기간 내여야 함

## Contract Addresses (Mainnet)

```
Vault: 0x98FFBD67fb84506c630a77b901ACeA78CC917470
USDC:  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

---

## Step 1: Safe 앱 접속

1. https://app.safe.global 접속
2. 본인의 Safe Wallet 연결
3. 좌측 메뉴에서 **"Apps"** 클릭
4. **"Transaction Builder"** 검색 후 실행

---

## Step 2: USDC Approve 트랜잭션 추가

Vault가 USDC를 사용할 수 있도록 승인하는 트랜잭션입니다.

### 2-1. 새 트랜잭션 추가

Transaction Builder에서:

1. **"Add new transaction"** 클릭

### 2-2. Contract 정보 입력

| 필드 | 입력값 |
|------|--------|
| **Enter Address or ENS Name** | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |

→ Enter 누르면 USDC 컨트랙트가 자동으로 인식됩니다.

### 2-3. Method 선택

1. **"Contract Method Selector"** 드롭다운 클릭
2. **`approve`** 선택

### 2-4. Parameters 입력

| Parameter | 입력값 | 설명 |
|-----------|--------|------|
| **spender (address)** | `0x98FFBD67fb84506c630a77b901ACeA78CC917470` | Vault 주소 |
| **amount (uint256)** | `500000000000` | 500,000 USDC (6 decimals) |

> **USDC 금액 변환표**
> | 금액 | 입력값 |
> |------|--------|
> | 100,000 USDC | `100000000000` |
> | 200,000 USDC | `200000000000` |
> | 500,000 USDC | `500000000000` |
> | 1,000,000 USDC | `1000000000000` |

### 2-5. 트랜잭션 추가

**"Add transaction"** 버튼 클릭

---

## Step 3: Deposit 트랜잭션 추가

실제로 USDC를 Vault에 예치하는 트랜잭션입니다.

### 3-1. 새 트랜잭션 추가

**"Add new transaction"** 클릭

### 3-2. Contract 정보 입력

| 필드 | 입력값 |
|------|--------|
| **Enter Address or ENS Name** | `0x98FFBD67fb84506c630a77b901ACeA78CC917470` |

→ Vault 컨트랙트가 인식되지 않으면 ABI를 직접 입력해야 합니다.

### 3-3. ABI 입력 (컨트랙트가 인식되지 않는 경우)

**"Use custom ABI"** 또는 **"Enter ABI"** 클릭 후 아래 내용 붙여넣기:

```json
[{"inputs":[{"name":"assets","type":"uint256"},{"name":"receiver","type":"address"}],"name":"deposit","outputs":[{"name":"shares","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}]
```

### 3-4. Method 선택

**`deposit`** 선택

### 3-5. Parameters 입력

| Parameter | 입력값 | 설명 |
|-----------|--------|------|
| **assets (uint256)** | `500000000000` | 예치할 USDC 금액 (6 decimals) |
| **receiver (address)** | `0x당신의SafeWallet주소` | Share를 받을 주소 (본인 Safe 주소) |

> **주의**: `receiver`에는 반드시 본인의 Safe Wallet 주소를 입력하세요!

### 3-6. 트랜잭션 추가

**"Add transaction"** 버튼 클릭

---

## Step 4: Batch 실행

이제 Transaction Builder에 2개의 트랜잭션이 추가되어 있습니다:
1. USDC Approve
2. Vault Deposit

### 4-1. 트랜잭션 확인

```
Transaction 1: approve(spender, amount)
  - To: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
  - spender: 0x98FFBD67fb84506c630a77b901ACeA78CC917470
  - amount: 500000000000

Transaction 2: deposit(assets, receiver)
  - To: 0x98FFBD67fb84506c630a77b901ACeA78CC917470 (Vault)
  - assets: 500000000000
  - receiver: [Your Safe Address]
```

### 4-2. 실행

1. **"Create Batch"** 버튼 클릭
2. 트랜잭션 내용 검토
3. **"Send Batch"** 클릭
4. 연결된 지갑으로 서명
5. 다른 Safe 소유자들의 서명 대기 (multisig인 경우)
6. 필요한 서명 수 충족 시 **"Execute"**

---

## Step 5: 예치 확인

### Etherscan에서 확인

1. https://etherscan.io/address/0x98FFBD67fb84506c630a77b901ACeA78CC917470 접속
2. **"Read Contract"** 탭 클릭
3. **`balanceOf`** 함수 실행
   - `account`: 본인 Safe 주소 입력
   - Share 잔액 확인 (예: 500000000000 = 500,000 shares)

### 예치 정보 확인

**`getDepositInfo`** 함수 실행:
- `user`: 본인 Safe 주소 입력
- 결과:
  - `shares`: 보유 share 수량
  - `principal`: 원금
  - `lastClaimMonth`: 마지막 이자 청구 월
  - `depositTime`: 예치 시간

---

## 자주 발생하는 에러

| 에러 메시지 | 원인 | 해결 방법 |
|------------|------|----------|
| `NotWhitelisted` | Whitelist에 등록 안 됨 | Admin에게 whitelist 추가 요청 |
| `ExceedsAllocatedCap` | 할당된 cap 초과 | 할당된 금액 내에서 예치 |
| `CollectionNotStarted` | Collection 기간 전 | Collection 시작 후 예치 |
| `CollectionEnded` | Collection 기간 종료 | Collection 기간 내 예치 필요 |
| `DepositTooSmall` | 최소 금액 미만 | 최소 100 USDC 이상 예치 |
| `ERC20: insufficient allowance` | Approve 안 됨 | Step 2 Approve 먼저 실행 |
| `ERC20: transfer amount exceeds balance` | USDC 잔액 부족 | Safe에 USDC 충전 필요 |

---

## 요약

```
1. Safe App → Transaction Builder 실행

2. Approve 트랜잭션 추가
   - To: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
   - Method: approve
   - spender: 0x98FFBD67fb84506c630a77b901ACeA78CC917470 (Vault)
   - amount: 예치할 금액 (6 decimals)

3. Deposit 트랜잭션 추가
   - To: 0x98FFBD67fb84506c630a77b901ACeA78CC917470 (Vault)
   - Method: deposit
   - assets: 예치할 금액 (6 decimals)
   - receiver: 본인 Safe 주소

4. Create Batch → Send Batch → 서명 → Execute
```

---

## 관련 링크

- **Safe App**: https://app.safe.global
- **Vault Contract**: https://etherscan.io/address/0x98FFBD67fb84506c630a77b901ACeA78CC917470
- **USDC Contract**: https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
