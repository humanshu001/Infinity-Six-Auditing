USER INVESTS 100 USDT
        │
        ▼
┌───────────────────────────────────────┐
│           USDT ALLOCATION             │
│                                       │
│  60 USDT ──► Swap to i6 Token         │
│              └──► i6 received         │
│                   └──► Burned! 🔥     │
│                                       │
│  40 USDT ──► Add Liquidity            │
│              ├── 40 USDT to pool      │
│              └── Matching i6 tokens   │
│                  (bought from pool)   │
│                  └──► LP to 0xdead    │
└───────────────────────────────────────┘

USER WITHDRAWS (USDT value X)
        │
        ▼
┌───────────────────────────────────────┐
│        TOKEN MINTING MATH             │
│                                       │
│  spotPrice = reserves(USDT)/reserves(i6)
│  tokensToMint = X / spotPrice         │
│  txnFee = 5% of tokensToMint          │
│  userReceives = 95% of tokensToMint   │
│                                       │
│  NOTE: txnFee tokens are MINTED       │
│  but not burned or distributed!       │
│  → Lost/stuck in contract? ⚠️         │
└───────────────────────────────────────┘

Token Risk Assessment

TOKENOMICS THREATS:

1. INFLATIONARY PRESSURE
   ├── Every withdrawal mints new tokens
   ├── No hard supply cap
   ├── 6x multiplier means 6x original investment
   │   minted as tokens over time
   └── Mitigation: 60% burn on invest partially offsets

2. DEATH SPIRAL RISK
   ├── Token price falls → more tokens minted per withdrawal
   ├── More tokens = more sell pressure
   ├── Pool reserves depleted → getSpotPrice() reverts
   └── Protocol halts completely

3. LIQUIDITY LOCKED PERMANENTLY
   ├── LP tokens sent to 0xdead (burned)
   ├── Cannot rebalance or rescue liquidity
   └── Good for trust, bad for flexibility

4. TRANSACTION FEE LEAK
   ├── 5% txnFee minted but stays in contract
   ├── Cannot be withdrawn (rescueAccidentalTokens blocks it)
   └── Accumulates as dead tokens in contract