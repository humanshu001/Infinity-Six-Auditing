# Function Analysis

### Function Name: invest
* **Purpose**: Registers users, accepts USDT, processes referral structures, updates volumes, auto-ranks, swaps and adds liquidity.
* **Complexity**: O(depth + directCount)
* **Storage Reads**: Referrer status, direct counts, user records, slippage.
* **Storage Writes**: Updates referrer direct counts, downline business, fresh business, direct volume, investment structures, pending bonuses.
* **External Calls**: Swap router (`swapExactTokensForTokens`, `addLiquidity`), USDT, projectToken.
* **Gas Risk**: Moderate-high due to loop traversals and DEX interaction.
* **Scalability Risk**: Low, capped by max depth (1000) and max directs (200).
* **Potential DoS Risk**: Low. Hard limits prevent out-of-gas failures.
* **Worst Case User State**: User invests under a sponsor with 200 directs, 100 packages, and 1000 levels deep.
* **Worst Case Protocol State**: Entire referrer network is at maximum depth and maximum directs.

---

### Function Name: withdraw
* **Purpose**: Process all pending direct, level, upline, and salary rewards, updates compounding principal, and mints/transfers project tokens.
* **Complexity**: O(packages.length)
* **Storage Reads**: User investments, upline investments, pending rewards.
* **Storage Writes**: Compounds active investments, updates rwpWithdrawn, resets rewards.
* **External Calls**: Token minting and transfers.
* **Gas Risk**: Moderate due to iteration over user's investment packages.
* **Scalability Risk**: Low, packages are capped at 100.
* **Potential DoS Risk**: Low. Bounded package sizes prevent DoS.
* **Worst Case User State**: 100 active packages, max rewards.
* **Worst Case Protocol State**: High user count with maximum packages.

---

### Function Name: claimRank
* **Purpose**: Manual rank promotion validation, snapshotting direct legs and resetting fresh business.
* **Complexity**: O(directCount)
* **Storage Reads**: Directs list, fresh business records.
* **Storage Writes**: Leg snapshots, rank upgrades, fresh business resets.
* **External Calls**: None.
* **Gas Risk**: Low-moderate.
* **Scalability Risk**: Low, capped by 200 directs.
* **Potential DoS Risk**: Low.
* **Worst Case User State**: User has 200 directs.
* **Worst Case Protocol State**: All users have 200 directs.

---

### Function Name: _realizeUplineIncome
* **Purpose**: Calculates and updates pending stream rewards from 3 levels of upline.
* **Complexity**: O(packages.length)
* **Storage Reads**: Upline user mappings, upline investments.
* **Storage Writes**: Pending income, seen trackers.
* **External Calls**: None.
* **Gas Risk**: Low.
* **Scalability Risk**: Low, reads 3 levels up.
* **Potential DoS Risk**: Low.
* **Worst Case User State**: 3 active uplines with 100 packages each.
* **Worst Case Protocol State**: All uplines have maximum active packages.

---

# Gas Benchmark & Scalability Results

* **Depth 10**: 923,962 gas
* **Depth 50**: 1,746,976 gas
* **Depth 100**: 1,802,077 gas
* **Depth 500**: 2,242,880 gas
* **Depth 1000**: 2,792,756 gas
* **100 Referrals (Sponsor)**: 1,250,649 gas
* **500 Referrals (Tree)**: 455,510 gas
* **Worst Case Withdrawal**: 3,799,493 gas
* **Griefing (100 Directs)**: 1,259,172 gas

---

# Audit Findings & Recommendations

### Finding 1: Unused Loop in Direct Bonus Summation
* **Severity**: Low
* **Likelihood**: High
* **Impact**: Low
* **Affected Function**: `invest()`
* **Root Cause**: Iterative traversal of `pendingDirectBonuses` to compute projected lifetime earnings when processing direct bonus allocation.
* **Gas Complexity**: O(n) where n is the number of pending bonuses.
* **Attack Scenario**: Attacker makes numerous tiny investments to inflate the `pendingDirectBonuses` array, increasing the gas cost of subsequent investments.
* **Foundry Test Name**: `test_GasGriefing_AttackerDirects`
* **Recommended Fix**: Maintain a running `totalPendingDirectBonuses` state variable per user to replace the loop with an O(1) state read.

### Finding 2: Linear Referral Tree Depth Traversal
* **Severity**: Low
* **Likelihood**: Low
* **Impact**: Low
* **Affected Function**: `_updateDownlineBusiness()`
* **Root Cause**: Linear recursion loop up to `maxDownlineDepth` levels to update business metrics.
* **Gas Complexity**: O(depth)
* **Attack Scenario**: Creating deep sybil referrer chains to increase investment costs of downline users.
* **Foundry Test Name**: `test_Gas_Depth1000`
* **Recommended Fix**: Restrict `maxDownlineDepth` configuration to a lower default threshold (e.g. 100-200) to keep transaction gas bounds tighter.
