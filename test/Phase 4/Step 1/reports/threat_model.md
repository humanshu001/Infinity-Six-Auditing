Attack Surface Map

EXTERNAL ATTACK SURFACES
═════════════════════════

[A] Token Contract Surfaces
    ├── A1: _update() hook - transfer restrictions
    ├── A2: mint() - only systemContract
    ├── A3: enableBuying() - time-locked, DAO only
    ├── A4: setWhitelist() - DAO only
    └── A5: rescueTokens() - DAO only

[B] System Contract Surfaces  
    ├── B1: invest() - public, main entry point
    ├── B2: withdraw() - public, token minting
    ├── B3: claimRank() - public, rank system
    ├── B4: getSpotPrice() - public view, oracle
    └── B5: Admin setters - DAO gated

[C] DEX Integration Surfaces
    ├── C1: swapExactTokensForTokens() - slippage
    ├── C2: addLiquidity() - price manipulation
    ├── C3: getReserves() - spot price oracle
    └── C4: quote() - price calculation

[D] MLM/Referral Surfaces
    ├── D1: Referral chain manipulation
    ├── D2: Level income calculation loops
    ├── D3: Upline stream traversal
    └── D4: Rank qualification checks

[E] Governance Surfaces
    ├── E1: DAOMultisigController single point
    ├── E2: updateDAOMultisignController()
    ├── E3: setDexRouter() - max approvals
    └── E4: rescueAccidentalTokens()


Spoofing Threats

THREAT-S1: DAO Controller Impersonation
├── Attack: Single EOA poses as "multisig DAO"
├── Vector: DAOMultisigController is just address
├── Impact: CRITICAL - full protocol takeover
├── Likelihood: HIGH (no on-chain multisig enforcement)
└── Mitigation: Enforce Gnosis Safe or on-chain multisig

THREAT-S2: Referrer Spoofing
├── Attack: Use inactive/fake referrer addresses
├── Vector: invest() checks totalDeposits == 0
├── Impact: MEDIUM - bypass referral validation
├── Likelihood: LOW (genesis deposit mitigates)
└── Mitigation: Current check is adequate

THREAT-S3: Contract Call Bypassing
├── Attack: Use tx.origin == msg.sender bypass
├── Vector: Flash loan contracts calling invest()
├── Impact: HIGH - bot/contract manipulation
├── Likelihood: MEDIUM (AA wallets bypass this)
└── Mitigation: tx.origin check is fragile with EIP-4337

Tampering Threats

THREAT-T1: Spot Price Oracle Manipulation
├── Attack: Flash loan to move UniswapV2 reserves
├── Vector: getSpotPrice() uses instantaneous reserves
├── Impact: CRITICAL - manipulate token withdrawal value
├── Code Path: withdraw() → _executeWithdrawTransfer() 
│             → getSpotPrice() → pair.getReserves()
├── Scenario:
│   1. Attacker flash loans large USDT
│   2. Dumps USDT into pair → token price crashes
│   3. User withdraws → gets massive token amount
│   4. Attacker reverses trade → tokens worthless
├── Likelihood: HIGH
└── Mitigation: Use TWAP oracle, not spot price

THREAT-T2: Compounding Math Manipulation  
├── Attack: Manipulate block.timestamp for compound gains
├── Vector: _updateCompounding uses block.timestamp
├── Impact: MEDIUM - small timestamp manipulation by miners
├── Likelihood: LOW (post-merge, ~12s slots)
└── Mitigation: Acceptable risk with 1-day granularity

THREAT-T3: Level Income Base Manipulation
├── Attack: Invest/cap cycle to inflate levelRewardBase
├── Vector: _updateUplineStream adds without decay check
├── Impact: HIGH - extract excess level income
├── Likelihood: MEDIUM
└── Mitigation: Add invariant checks on levelRewardBase

THREAT-T4: DEX Router Replacement Attack
├── Attack: DAO sets malicious dexRouter
├── Vector: setDexRouter() grants max approval to new router
├── Impact: CRITICAL - drain all USDT and tokens
├── Likelihood: MEDIUM (requires DAO compromise)
└── Mitigation: Timelock on router changes, limit approvals

Repudiation Threats

THREAT-R1: Rank Claim Without Qualification
├── Attack: _tryAutoRank() called during invest/withdraw
├── Vector: Auto-rank triggers without user consent
├── Impact: LOW - resets freshBusiness unexpectedly  
├── Likelihood: HIGH (by design, but exploitable)
└── Mitigation: Emit detailed events (partial: RankClaimed exists)

THREAT-R2: Direct Bonus Timing Manipulation
├── Attack: Unlock timing for pendingDirectBonuses
├── Vector: 12-hour unlock, block.timestamp manipulable
├── Impact: LOW - minor timing advantage
├── Likelihood: LOW
└── Mitigation: Acceptable with validator trust

Information Disclosure Threats

THREAT-I1: MLM Structure Enumeration
├── Attack: Read userDirects[] and referrer chains
├── Vector: All mappings are public
├── Impact: LOW - privacy concern only
├── Likelihood: HIGH (blockchain is public)
└── Mitigation: By design, acceptable

THREAT-I2: Pending Withdrawal Preview
├── Attack: MEV bots front-run large withdrawals
├── Vector: WithdrawCache calculated, visible in mempool
├── Impact: MEDIUM - sandwich attack on token swap
├── Likelihood: HIGH (no private mempool)
└── Mitigation: Add minTokensOut parameter (partially done)

Denial of Service Threats

THREAT-D1: Investment Array Gas DoS
├── Attack: Max out 100 investments, make withdraw fail
├── Vector: userInvestments[msg.sender].length >= 100 allowed
│          withdraw() loops all investments twice
├── Impact: HIGH - permanent fund lockup
├── Gas Cost: ~100 iterations × 2 = 200 SSTORE reads minimum
├── Likelihood: MEDIUM (user self-inflicted or griefed)
└── Mitigation: Limit array size further, add pagination

THREAT-D2: Upline Chain Traversal DoS
├── Attack: Create 1000-deep referral chain
├── Vector: _updateDownlineBusiness loops maxDownlineDepth
│          _updateUplineStream loops 40 levels
├── Impact: HIGH - OOG in invest/withdraw for deep chains
├── Likelihood: MEDIUM
└── Gas Analysis:
    maxDownlineDepth = 1000 iterations → ~2M+ gas
└── Mitigation: Reduce maxDownlineDepth, add gas checks

THREAT-D3: Direct Array DoS in Rank Check
├── Attack: MAX_DIRECTS = 200, claimRank loops all directs
├── Vector: _checkRankQualification loops userDirects[]
│          Called in claimRank → _tryAutoRank → invest/withdraw
├── Impact: MEDIUM - increased gas cost
├── Likelihood: HIGH (normal usage hits this)
└── Mitigation: Optimize rank check with cached values

THREAT-D4: Withdrawal Cooldown Griefing
├── Attack: Force lastBlockNumber update to block withdraw
├── Vector: lastBlockNumber updated in _executeWithdrawTransfer
│          block.number check in withdraw()
├── Impact: LOW - one block delay only
├── Likelihood: LOW
└── Mitigation: Adequate protection

THREAT-D5: Liquidity Pool Drain Lock
├── Attack: If pool reserves hit 0, all invest() fails
├── Vector: _swapTokenFromPancakev2 reverts on empty pool
├── Impact: HIGH - protocol halts
├── Likelihood: MEDIUM (token price collapse scenario)
└── Mitigation: Fallback mechanism needed

Priviledge Threats

THREAT-E1: Unlimited Token Minting
├── Attack: Compromised systemContract mints infinite tokens
├── Vector: mint() has no cap check
├── Impact: CRITICAL - total inflation, price collapse
├── Code: function mint(address to, uint256 amount) external onlySystem
├── Likelihood: MEDIUM (systemContract is trusted)
└── Mitigation: Add supply cap, mint rate limiting

THREAT-E2: DAO Self-Privilege Escalation  
├── Attack: DAO updates itself to attacker address
├── Vector: updateDAOMultisignController() single-step
├── Impact: CRITICAL - permanent protocol takeover
├── Code: DAOMultisigController = _multisigController; (instant)
├── Likelihood: MEDIUM (social engineering / key theft)
└── Mitigation: Two-step transfer with timelock

THREAT-E3: ORIGIN_MEMBER_ID Infinite Drain
├── Attack: ORIGIN_MEMBER_ID withdraws without 6x cap
├── Vector: All income checks: if (_user == ORIGIN_MEMBER_ID || ...)
│          _executeWithdrawTransfer: special distribution to GEN_W1-7
├── Impact: HIGH - continuous token minting to fixed addresses
├── Likelihood: HIGH (by design, but centralization risk)
└── Mitigation: Document as intentional, add transparency

THREAT-E4: Whitelisted Address Bypass
├── Attack: Whitelisted address bypasses all transfer checks
├── Vector: isWhitelisted[from] skips all anti-bot checks
│          liquidityPair is whitelisted (can buy before enabled)
├── Impact: MEDIUM - privileged trading
├── Likelihood: MEDIUM
└── Mitigation: Document whitelist members, limit whitelist size