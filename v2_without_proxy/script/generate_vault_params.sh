#!/bin/bash
# Vault Parameter Generator
# Usage: ./generate_vault_params.sh [name] [symbol]
#
# Edit the CONFIGURATION section below to customize timing

set -e

# ============ CONFIGURATION (in minutes from now) ============
COLLECTION_START=10      # 예치 시작
COLLECTION_END=20        # 예치 마감
INTEREST_START=30        # 이자 계산 시작

# Interest periods (comma-separated, minutes from now)
PERIOD_ENDS="60,90"      # 이자 기간 종료 시점들
PAYMENT_DATES="70,100"   # 이자 수령 가능 시점들

WITHDRAWAL_START=100     # 원금 수령 시작

# Vault settings
FIXED_APY=1000           # APY in basis points (1000 = 10%)
MIN_DEPOSIT=100000000    # 100 USDC (6 decimals)
MAX_CAPACITY=100000000000 # 100,000 USDC (6 decimals)
# ============ END CONFIGURATION ============

NAME=${1:-"Yaylabs Test Vault"}
SYMBOL=${2:-"YTV"}

NOW=$(date +%s)
NOW_KST=$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')

# Calculate timestamps
COLLECTION_START_TS=$((NOW + COLLECTION_START * 60))
COLLECTION_END_TS=$((NOW + COLLECTION_END * 60))
INTEREST_START_TS=$((NOW + INTEREST_START * 60))
WITHDRAWAL_START_TS=$((NOW + WITHDRAWAL_START * 60))
TERM_DURATION=$((WITHDRAWAL_START_TS - INTEREST_START_TS))

# Parse period ends
IFS=',' read -ra PERIOD_ARR <<< "$PERIOD_ENDS"
PERIOD_END_DATES=""
for i in "${PERIOD_ARR[@]}"; do
    TS=$((NOW + i * 60))
    if [ -z "$PERIOD_END_DATES" ]; then
        PERIOD_END_DATES="$TS"
    else
        PERIOD_END_DATES="$PERIOD_END_DATES,$TS"
    fi
done

# Parse payment dates
IFS=',' read -ra PAYMENT_ARR <<< "$PAYMENT_DATES"
PAYMENT_DATES_TS=""
for i in "${PAYMENT_ARR[@]}"; do
    TS=$((NOW + i * 60))
    if [ -z "$PAYMENT_DATES_TS" ]; then
        PAYMENT_DATES_TS="$TS"
    else
        PAYMENT_DATES_TS="$PAYMENT_DATES_TS,$TS"
    fi
done

echo "=============================================="
echo "       VAULT PARAMETERS - $NOW_KST"
echo "=============================================="
echo ""
echo "=== Timeline (KST) ==="
echo "$(TZ=Asia/Seoul date -r $COLLECTION_START_TS '+%H:%M:%S') - 예치 시작"
echo "$(TZ=Asia/Seoul date -r $COLLECTION_END_TS '+%H:%M:%S') - 예치 마감"
echo "$(TZ=Asia/Seoul date -r $INTEREST_START_TS '+%H:%M:%S') - 이자 계산 시작"

IFS=',' read -ra PERIOD_ARR <<< "$PERIOD_ENDS"
for i in "${!PERIOD_ARR[@]}"; do
    TS=$((NOW + PERIOD_ARR[i] * 60))
    echo "$(TZ=Asia/Seoul date -r $TS '+%H:%M:%S') - $((i+1))차 이자기간 종료"
done

IFS=',' read -ra PAYMENT_ARR <<< "$PAYMENT_DATES"
for i in "${!PAYMENT_ARR[@]}"; do
    TS=$((NOW + PAYMENT_ARR[i] * 60))
    if [ $i -eq $((${#PAYMENT_ARR[@]}-1)) ]; then
        echo "$(TZ=Asia/Seoul date -r $TS '+%H:%M:%S') - $((i+1))차 이자 + 원금 수령"
    else
        echo "$(TZ=Asia/Seoul date -r $TS '+%H:%M:%S') - $((i+1))차 이자 수령"
    fi
done

echo ""
echo "=== Safe Transaction Builder Format ==="
echo ""
echo "name: $NAME"
echo "symbol: $SYMBOL"
echo "collectionStartTime: $COLLECTION_START_TS"
echo "collectionEndTime: $COLLECTION_END_TS"
echo "interestStartTime: $INTEREST_START_TS"
echo "termDuration: $TERM_DURATION"
echo "fixedAPY: $FIXED_APY"
echo "minDeposit: $MIN_DEPOSIT"
echo "maxCapacity: $MAX_CAPACITY"
echo "interestPeriodEndDates: [$PERIOD_END_DATES]"
echo "interestPaymentDates: [$PAYMENT_DATES_TS]"
echo "withdrawalStartTime: $WITHDRAWAL_START_TS"
echo ""
echo "=== Safe Tuple Format (복사해서 붙여넣기) ==="
echo ""
echo "[\"$NAME\",\"$SYMBOL\",$COLLECTION_START_TS,$COLLECTION_END_TS,$INTEREST_START_TS,$TERM_DURATION,$FIXED_APY,$MIN_DEPOSIT,$MAX_CAPACITY,[$PERIOD_END_DATES],[$PAYMENT_DATES_TS],$WITHDRAWAL_START_TS]"
echo ""
echo "=== JSON Format ==="
echo ""
cat << JSONEOF
{
  "name": "$NAME",
  "symbol": "$SYMBOL",
  "collectionStartTime": $COLLECTION_START_TS,
  "collectionEndTime": $COLLECTION_END_TS,
  "interestStartTime": $INTEREST_START_TS,
  "termDuration": $TERM_DURATION,
  "fixedAPY": $FIXED_APY,
  "minDeposit": $MIN_DEPOSIT,
  "maxCapacity": $MAX_CAPACITY,
  "interestPeriodEndDates": [$PERIOD_END_DATES],
  "interestPaymentDates": [$PAYMENT_DATES_TS],
  "withdrawalStartTime": $WITHDRAWAL_START_TS
}
JSONEOF
echo ""
echo "=== Settings ==="
echo "APY: $((FIXED_APY / 100))% ($FIXED_APY bps)"
echo "Min Deposit: $((MIN_DEPOSIT / 1000000)) USDC"
echo "Max Capacity: $((MAX_CAPACITY / 1000000)) USDC"
echo "Term Duration: $((TERM_DURATION / 60)) minutes"
