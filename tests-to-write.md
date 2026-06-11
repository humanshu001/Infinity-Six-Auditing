# 1. Access Control Attacks

### Scenarios

* Non-DAO calls DAO functions
* Non-system calls mint()
* Old DAO calls after DAO update
* DAO updates itself repeatedly
* DAO sets itself to malicious contract
* DAO sets system contract to malicious contract
* DAO renounces control unexpectedly
* Zero-address admin assignments
* Whitelisted account abuses privileges
* Previously whitelisted account remains privileged after removal

---

# 2. Minting Attacks

### Scenarios

* Mint maximum uint256
* Mint repeatedly
* Mint through reward path
* Mint through withdrawal path
* Mint through compound path
* Mint before launch
* Mint after cap reached
* Mint to zero address
* Mint to dead address
* Mint during cooldown
* Mint after DAO changes system contract

---

# 3. Supply Manipulation Attacks

### Scenarios

* Burn then mint
* Mint then burn
* Burn from reward wallet
* Burn during withdrawal
* Burn while calculating ROI
* Supply cap bypass
* Supply accounting mismatch

---

# 4. Withdrawal Attacks

### Scenarios

* Withdraw twice same block
* Withdraw twice after cooldown
* Withdraw after cap reached
* Withdraw immediately after deposit
* Withdraw after compound
* Withdraw after referral reward
* Withdraw from inactive account
* Withdraw with zero rewards
* Withdraw with manipulated timestamps
* Withdraw at boundary values

---

# 5. Deposit Attacks

### Scenarios

* Deposit below minimum
* Deposit above maximum
* Deposit exactly minimum
* Deposit exactly maximum
* Deposit multiple times rapidly
* Deposit with invalid sponsor
* Deposit with self sponsor
* Deposit after withdrawal
* Deposit after max income reached
* Deposit from smart contract
* Deposit via proxy

---

# 6. Referral Attacks

### Scenarios

* Self referral
* Circular referral
* Referral loop
* Referral chain 1000 levels
* Referral chain with inactive users
* Referral chain with dead addresses
* Referral chain with duplicates
* Sponsor replacement
* Sponsor race condition
* Multiple sponsor registration

---

# 7. Team Volume Attacks

### Scenarios

* Double count deposits
* Double count withdrawals
* Count inactive users
* Count self volume
* Count circular volume
* Sybil volume farm
* Volume inflation through tiny deposits
* Volume inflation through compounding

---

# 8. ROI Attacks

### Scenarios

* Warp 1 hour
* Warp 1 day
* Warp 1 year
* Warp 10 years
* Compound repeatedly
* Compound then withdraw
* Withdraw then compound
* ROI cap bypass
* ROI rounding errors
* ROI overflow

---

# 9. Booster Attacks

### Scenarios

* Booster activated repeatedly
* Booster after expiration
* Booster before eligibility
* Booster stacking
* Booster overflow
* Booster double counting

---

# 10. Salary Reward Attacks

### Scenarios

* Salary claimed twice
* Salary claimed before qualification
* Salary after downgrade
* Salary after sponsor change
* Salary after max cap reached

---

# 11. Upline Income Attacks

### Scenarios

* Fake uplines
* Deep uplines
* Duplicate uplines
* Upline income double counted
* Upline threshold bypass

---

# 12. Cooldown Attacks

### Scenarios

* Withdraw at 3599 seconds
* Withdraw at 3600 seconds
* Withdraw at 3601 seconds
* Multiple wallets rotating cooldown
* Cooldown reset manipulation

You expect reverts, but verify.

---

# 13. Same Block Protection Attacks

### Scenarios

* Deposit twice same block
* Withdraw twice same block
* Deposit + withdraw same block
* Compound + withdraw same block
* Transfer twice same block
* Multi-wallet same block
* Bundle transaction testing

---

# 14. tx.origin Attacks

Even though tx.origin blocks contracts:

### Scenarios

* Call through proxy
* Call through multicall
* Call through Gnosis Safe
* Call through delegatecall
* Call through minimal proxy
* Call through CREATE2 contract

Verify all fail.

---

# 15. Oracle Attacks

Do NOT skip.

Even if buying is disabled.

### Scenarios

* Manipulate pair reserves
* Manipulate getSpotPrice()
* Drain liquidity
* Add liquidity
* Remove liquidity
* Extreme reserve imbalance
* Zero reserve state
* One-sided liquidity

Goal:

Determine whether spot price affects rewards.

---

# 16. Liquidity Attacks

### Scenarios

* Pair removed
* Pair changed
* Router changed
* Liquidity near zero
* Liquidity extremely high
* Pair contract malicious

---

# 17. Reentrancy Attacks

Even if tx.origin exists.

### Scenarios

* Reentrant withdraw
* Reentrant reward claim
* Reentrant compound
* Reentrant mint
* Reentrant referral distribution

Use malicious ERC20s.

---

# 18. DoS Attacks

Huge category.

### Scenario Group A

Downline depth:

* 10 levels
* 100 levels
* 500 levels
* 1000 levels

### Scenario Group B

Direct referrals:

* 10 directs
* 50 directs
* 100 directs
* 200 directs

### Scenario Group C

Users:

* 100 users
* 1,000 users
* 10,000 users
* 100,000 users

Measure gas.

---

# 19. Storage Bloat Attacks

### Scenarios

* Massive referrals
* Massive deposits
* Massive withdrawals
* Massive compounds
* Massive team volume records

Look for functions becoming unusable.

---

# 20. Arithmetic Attacks

### Scenarios

* Max uint256 deposits
* Max uint256 rewards
* Max uint256 team volume
* Overflow attempts
* Underflow attempts
* Precision loss
* Division by zero

---

# 21. Economic Attacks

### Scenarios

* Sybil network
* Referral farming
* Reward farming
* Deposit splitting
* Withdrawal splitting
* Multi-wallet farming
* ROI farming

These often find real exploits.

---

# 22. Invariant Breaking Attacks

Create Foundry invariants:

### Invariants

* User never withdraws > max income
* Total rewards accounted correctly
* Supply never exceeds cap
* Team volume never negative
* Referral rewards never exceed allocation
* Salary rewards never exceed allocation
* Contract balances always sufficient

---

# 23. Governance Attacks

### Scenarios

* DAO compromised
* System contract compromised
* DAO replaced
* DAO points to malicious system
* Whitelist abuse
* Emergency parameter abuse
* Governance lockout