TRUST HIERARCHY
═══════════════

Level 0 (Absolute Trust - Hardcoded)
├── ORIGIN_MEMBER_ID (0xdF4fA7B59e...)  ← Bypasses income caps
├── GEN_W1 through GEN_W7               ← Receive origin withdrawals
└── address(0xdead)                     ← LP token burn destination

Level 1 (High Trust - Admin)
├── DAOMultisigController
│   ├── Token: enable/disable buying, whitelist, set pairs
│   ├── System: ROI rates, withdrawal limits, DEX config
│   └── Can update itself (single-step transfer!)
└── Owner (Deployer)
    └── Token ownership (Ownable)

Level 2 (Medium Trust - System)
├── systemContract (set by DAO)
│   └── Can mint unlimited tokens
└── liquidityPair (set by DAO)
    └── Whitelisted, buy restrictions bypass

Level 3 (Low Trust - Users)
├── Investors (invest USDT)
└── Referrers (MLM upline chain)

Level 4 (External - Untrusted)
├── UniswapV2 Router (approved max allowance)
├── UniswapV2 Pair (price oracle source)
└── USDT contract

Critical Trust Violation

⚠️  TRUST ASSUMPTION FLAWS:

1. DAOMultisigController is a SINGLE ADDRESS
   - Named "DAO" but no multisig enforcement on-chain
   - One key compromise = total protocol control

2. ORIGIN_MEMBER_ID has UNLIMITED income (no 6x cap)
   - Can drain minted tokens indefinitely
   - GEN_W1-W7 wallets are hardcoded and unverifiable

3. systemContract can mint UNLIMITED tokens
   - No mint cap enforced
   - Hyperinflation vector if compromised

4. Max DEX approval granted at construction
   - usdt.approve(router, type(uint256).max)
   - projectToken.approve(router, type(uint256).max)

Admin Privilege Analysis

FUNCTION                          │DAO │Owner│System│Impact
──────────────────────────────────┼────┼─────┼──────┼──────────
enableBuying()                    │ ✓  │     │      │HIGH
disableBuying()                   │ ✓  │     │      │HIGH  
setSystemContract()               │ ✓  │     │      │CRITICAL
setLiquidityPair()                │ ✓  │     │      │HIGH
setWhitelist()                    │ ✓  │     │      │HIGH
updateDAOMultisigController()     │ ✓  │     │      │CRITICAL
rescueTokens() [Token]            │ ✓  │     │      │MEDIUM
mint() [Token]                    │    │     │ ✓    │CRITICAL
──────────────────────────────────┼────┼─────┼──────┼──────────
setROI()                          │ ✓  │     │      │HIGH
setWithdrawalHourlyLimit()        │ ✓  │     │      │HIGH
setLevelROI()                     │ ✓  │     │      │HIGH
setSalaryFreshBusiness()          │ ✓  │     │      │MEDIUM
setMaxDownlineDepth()             │ ✓  │     │      │MEDIUM
setLiquiditySlippage()            │ ✓  │     │      │MEDIUM
setTradingPair()                  │ ✓  │     │      │HIGH
setDexRouter()                    │ ✓  │     │      │CRITICAL
setMinInvestment()                │ ✓  │     │      │MEDIUM
updateDAOMultisignController()    │ ✓  │     │      │CRITICAL
rescueAccidentalTokens()          │ ✓  │     │      │HIGH

Critical Admin Attack Scenario

FUNCTION                          │DAO │Owner│System│Impact
──────────────────────────────────┼────┼─────┼──────┼──────────
enableBuying()                    │ ✓  │     │      │HIGH
disableBuying()                   │ ✓  │     │      │HIGH  
setSystemContract()               │ ✓  │     │      │CRITICAL
setLiquidityPair()                │ ✓  │     │      │HIGH
setWhitelist()                    │ ✓  │     │      │HIGH
updateDAOMultisigController()     │ ✓  │     │      │CRITICAL
rescueTokens() [Token]            │ ✓  │     │      │MEDIUM
mint() [Token]                    │    │     │ ✓    │CRITICAL
──────────────────────────────────┼────┼─────┼──────┼──────────
setROI()                          │ ✓  │     │      │HIGH
setWithdrawalHourlyLimit()        │ ✓  │     │      │HIGH
setLevelROI()                     │ ✓  │     │      │HIGH
setSalaryFreshBusiness()          │ ✓  │     │      │MEDIUM
setMaxDownlineDepth()             │ ✓  │     │      │MEDIUM
setLiquiditySlippage()            │ ✓  │     │      │MEDIUM
setTradingPair()                  │ ✓  │     │      │HIGH
setDexRouter()                    │ ✓  │     │      │CRITICAL
setMinInvestment()                │ ✓  │     │      │MEDIUM
updateDAOMultisignController()    │ ✓  │     │      │CRITICAL
rescueAccidentalTokens()          │ ✓  │     │      │HIGH