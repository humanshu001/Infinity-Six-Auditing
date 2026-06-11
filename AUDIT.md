# Infinity Six – Security Audit Report

**Scope**

| Contract | File | LoC | Solc |
|----------|------|-----|------|
| `InfinitySixToken` | `i6token.sol` | 159 | `^0.8.34` |
| `InfinitySixSystem` | `i6systemcontract.sol` | 1313 | `^0.8.34` |

**Live BSC mainnet state used as baseline**

| Item | Value |
|------|-------|
| Token | `0xd2e052c7faE5DDeD7A7B2CdDd27B5d75D18A1593` |
| System | `0x51A36b17b5dbD013C632dCb411F71E935392fe5e` |
| DAO multisig | `0x4EA9802681Fb877DE5407974E63F197EE754032f` |
| LP pair (USDT/i6) | `0x13D55200c298Ff1caE3136BE0dd889626DEAC782` |
| Router (Pancake V2) | `0x10ED43C718714eb63d5aA57B78B54704E256024E` |
| Token owner | `address(0)` (renounced) |
| `buyingEnabled` | `false` (policy: forever) |
| `timeUntilBuyUnlock` | `11_049_476s` left of 180d window |
| Total supply | `584,081.5 i6` |
| `MIN_ROI_PERC` | `5` (0.5% daily) |
| `WITHDRAWAL_COOLING_PERIOD` | `3600s` |
| `MAX_INVESTMENT` | `20,000 USDT` |

All fork tests use `BaseFork.t.sol` which pins these live values.

---

## 0. Executive summary

InfinitySix is an MLM-style ROI platform paying out a mintable reward token (`i6`) against USDT deposits. Buying is contractually time-locked for 180 days and project policy is to keep it disabled forever, so `i6` only enters circulation via `withdraw()` (mint at spot price, 5% fee, 60/40 auto-buy+LP-lock+burn on invest).

The codebase already ships an in-tree audit suite (`test/Phase 4/Step 1/tests/01_…23_…`) covering access control, oracle, reentrancy, DoS, arithmetic, etc. Findings below merge that suite's confirmed results with additional issues discovered in this review.

**Headline risk profile**

| # | Finding | Severity |
|---|---------|----------|
| C-1 | Spot-price oracle drives mint amount (no slippage guard on withdraw) | **Critical** |
| C-2 | No `MAX_SUPPLY` cap on token — unbounded mint | **Critical** |
| C-3 | DAO can drain user USDT via `rescueAccidentalTokens` | **Critical** |
| C-4 | Router hot-swap allows full deposit theft if multisig compromised | **Critical** |
| H-1 | `_getMultiplier` fall-through silently drops ROI to 0.5% for values {2,3,4,6,9} | **High** |
| H-2 | Booster rate not applied to packages created **after** boost activation | **High** |
| H-3 | `totalDownlineBusiness` / rank metrics monotonically increase (ghost volume) | **High** |
| H-4 | `enableBuying` reversible — buying-forever-off rests on DAO honesty | **High** |
| H-5 | ORIGIN_MEMBER_ID EOA hardcoded, bypasses 6x cap, single point of failure | **High** |
| M-1 | Same-block receive-cooldown is a griefing vector against withdraw | Medium |
| M-2 | Genesis-split withdraw uses 7 sequential `safeTransfer` (griefable) | Medium |
| M-3 | `_swapTokenFromPancakev2` silently skips `addLiquidity` if surplus insufficient | Medium |
| M-4 | Cap drop / boost rate asymmetry leaks `levelRewardBase` to uplines | Medium |
| M-5 | View `getDirectBonusInfo` over-reports available bonus | Medium |
| M-6 | Permanent booster invariant — no revocation | Medium |
| M-7 | Compounding precision loss in `_rpow` favors house | Medium |
| L-1 | `setROI` range `[2,10]` doesn't match `_getMultiplier` lookup | Low |
| L-2 | `_consumeMaintenanceVolume` writes dead state (`maintenanceBurnedVolume` never read) | Low |
| L-3 | `_realizePendingDirectBonus` updates `pendingBonusStartIndex` inside loop | Low (gas) |
| L-4 | Token `rescueTokens` uses raw `transfer` instead of `SafeERC20` | Low |
| L-5 | No emergency pause / circuit breaker | Low |
| I-1 | Genesis 50k USDT phantom deposit subsidized by future users | Info |
| I-2 | Multisig modeled as single EOA in `DAOMultisigController` | Info |

Severity model: **Critical** = direct loss of user funds or supply integrity. **High** = significant economic damage / accounting integrity. **Medium** = griefing, recoverable, or non-default code path. **Low** = best-practice / gas / DAO hygiene. **Info** = design note, no fix expected.

---

## 1. Threat model

| Actor | Capability | Trust |
|-------|-----------|-------|
| EOA investor | Calls `invest()`, `withdraw()`, `claimRank()` | Untrusted |
| DAO multisig (`0x4EA9…32f`) | Calls every `DAOMultiSignRequired` / `onlyDAO` setter | Trusted (single key in code) |
| `systemContract` (= the system contract address itself) | Mints `i6`, holds USDT, swaps and adds liquidity | Trusted by token |
| ORIGIN_MEMBER_ID (`0xdF4f…1cd1`) | Hardcoded genesis EOA; bypasses 6x cap; uncapped `pendingDirectBonus` cap-checks | Trusted absolutely |
| GEN_W1..7 | Hardcoded payout addresses for ORIGIN withdrawals | Trusted absolutely |
| MEV / sandwich bot | Reorder, frontrun, backrun txs on BSC | Adversarial |
| Smart contract caller / flash-loan attacker | Blocked by `tx.origin == msg.sender` on `invest`, `withdraw`, and token `_update` (non-whitelisted ↔ non-whitelisted) | Blocked |

Built-in defenses:

- `nonReentrant` modifier on `invest`, `withdraw`, `claimRank`.
- `tx.origin` check on invest/withdraw and token transfers.
- Same-block lock on both system (`lastBlockNumber`) and token (`lastTxBlock`, `lastReceiveBlock`).
- 1h withdrawal cooldown, 3-day post-launch wait.
- Per-package 2.5x ROI cap, global 6x income cap (ORIGIN exempt).
- LP burn (`addLiquidity → 0xdead`), residual token burn on invest.
- Buy time-lock 180 days on liquidity pair.

These defenses neutralize same-block flash-loan price manipulation and reentrancy. Residual threats are mostly **cross-block** oracle / state drift, **DAO trust**, and **economic / accounting bugs**.

---

## 2. Critical findings

### C-1. Withdraw mints from spot price with no caller-side slippage guard

**File:** `i6systemcontract.sol`
**Code:** `withdraw → _executeWithdrawTransfer` (lines 573–607)

`_executeWithdrawTransfer` reads `getSpotPrice()` straight off PancakeSwap pair reserves and computes

```solidity
uint256 tokensToTransfer = (totalUsdtToWithdraw * WAD) / effectivePrice;
```

The user supplies **no `minTokensOut` argument** to `withdraw()`. Same-block sandwich is blocked, but **cross-block** sandwich is not:

1. Attacker sees pending `withdraw()` in mempool / observes recent withdraws.
2. Attacker calls `invest(MAX_INVESTMENT, …)` first → the contract swaps 60% USDT into `i6` against the pair → `effectivePrice` rises sharply → next-block withdrawer mints **fewer** `i6` than expected.
3. The reverse (attacker dumps `i6` they already hold to depress price → withdraw mints excessive tokens → death-spiral acceleration) is demonstrated in `21_Economic/result.txt`: a price collapse from 1.0 → 0.1 USDT mints **10x** more `i6` per withdraw.

Note that with buying forever-off, the attacker cannot buy back the cheaper `i6`, so the pure-profit version is bounded; the realistic exploit is **death-spiral acceleration** and **withdrawal under-payment via invest-front-run**. The existing `PriceDynamics/C2_RatioSweep.t.sol` already triggers a panic (0x11 underflow) inside `withdraw()` once the spiral starts — concrete evidence the spiral is reachable.

**Impact:** Withdrawers can be systematically under-paid or, when reserves are depleted, the inflation feedback loop guarantees runaway minting until reserves are dust.

**Recommendation:**

- Add `uint256 minTokensOut` parameter to `withdraw()` and revert when `userAmount < minTokensOut`.
- Replace `getSpotPrice()` with a TWAP (`price0CumulativeLast`, `price1CumulativeLast` already imported on the interface!) over at least 30 minutes, falling back to spot only when no observation is available.
- Bound `tokensToTransfer` against a `MAX_TOKENS_PER_USD` ceiling that the DAO can tune.
- Sanity check reserves are above a minimum threshold (eg. `liquidityFloor`) before minting; if below, queue payouts instead of minting against dust reserves.

### C-2. No max-supply cap on `i6`

**File:** `i6token.sol`
**Code:** `mint` (line 104)

```solidity
function mint(address to, uint256 amount) external onlySystem { _mint(to, amount); }
```

There is **no `MAX_SUPPLY`** check. The system contract is the sole minter, so the practical ceiling is whatever total `userAmount` accumulates from `withdraw()`. Because that amount scales as `usdt / spotPrice`, a depressed `spotPrice` mints arbitrarily large amounts in a single withdraw (confirmed in `22_InvariantBreaking`: a single withdraw inflated supply by ~600,000x in the manipulated scenario).

**Recommendation:**

- Define `uint256 public constant MAX_SUPPLY` (e.g., 1_000_000_000 * 1e18) and check `totalSupply() + amount <= MAX_SUPPLY` inside `mint`.
- Alternatively, gate the system mint on `usdt * WAD / spotPrice` capped per-second (rate-limit minting).

### C-3. `rescueAccidentalTokens` can drain user-deposited USDT

**File:** `i6systemcontract.sol`
**Code:** `rescueAccidentalTokens` (lines 1310–1313)

```solidity
function rescueAccidentalTokens(address _tokenAddress, address _to, uint256 amount)
    external DAOMultiSignRequired {
    if (_tokenAddress == address(projectToken)) revert Err_CannotDrainRewardTokens();
    IERC20(_tokenAddress).safeTransfer(_to, amount);
}
```

Only `projectToken` is blocked. The contract custodies **all user-deposited USDT** between invest (full deposit pulled in) and the 60% swap (which only happens inside `_swapTokenFromPancakev2`). Any residual USDT balance on the contract — including the 40% LP slice already pulled in but not yet added to LP — is freely transferrable by the DAO. The function name says "accidental" but the check doesn't enforce that.

**Impact:** DAO multisig compromise → instant USDT rug. The system already pulls and holds USDT (especially while ranks/level income accrue), so the daily USDT float can be material.

**Recommendation:**

- Also block `usdt` rescue (analogous to the `projectToken` block).
- If accidental-USDT rescue is genuinely needed, restrict to `IERC20(usdt).balanceOf(this) - expectedFloat` where `expectedFloat` is whatever the contract should be holding for in-flight invests; safer to just block USDT entirely and require a contract migration for any recovery.

### C-4. `setDexRouter` allows hot-swap to an attacker-controlled router

**File:** `i6systemcontract.sol`
**Code:** `setDexRouter` (lines 1286–1298), `_swapTokenFromPancakev2` (lines 1176–1232)

Already documented in `23_Governance/result.txt`: DAO can swap the router and the next `invest()` swap sends the swap-portion (60% of every USDT deposit) wherever the malicious router decides. The malicious router can also return arbitrary tokens out of `quote()`, bypassing the `liquiditySlippage` minOut.

This is the same DAO-trust assumption as C-3 but more potent because it skims **every future invest**, not just current float.

**Recommendation:**

- Make `setDexRouter` time-locked (e.g., 7-day delay before activation, broadcast on-chain).
- Cap `liquiditySlippage` and the `minTokensOut` value below a hard ceiling so a malicious router can't return one wei.

---

## 3. High findings

### H-1. `_getMultiplier` silent fall-through to 0.5% for {2,3,4,6,9}

**File:** `i6systemcontract.sol:1134–1139`

```solidity
function _getMultiplier(uint256 rate) internal pure returns (uint256) {
    if (rate == 10) return 1010000000000000000;
    if (rate == 8)  return 1008000000000000000;
    if (rate == 7)  return 1007000000000000000;
    return 1005000000000000000;
}
```

`setROI` (lines 1234–1237) accepts `[2,10]`. Values {2,3,4,6,9} all silently fall through to the **default 0.5%** multiplier. Booster combinations (`userRate + boostperc`) such as `2+5=7` happen to land on a defined branch, but `4+5=9`, `6+5=11`, `9+5=14`, `5+0=5` etc. all default to 0.5%.

This is already confirmed in `20_Arithmetic/result.txt`: setting ROI to 9% still compounds at 5×10⁻³ in `getTotalLifetimeRWP`.

**Recommendation:** Replace lookup with arithmetic:

```solidity
function _getMultiplier(uint256 rate) internal pure returns (uint256) {
    return WAD + (rate * WAD) / 1000; // 5 → 1.005, 7 → 1.007, …
}
```

This makes `setROI`'s `[2,10]` range and any future booster combination correct.

### H-2. Booster rate not applied to packages created after activation

**File:** `i6systemcontract.sol`
**Code:** `invest` (line 330), `_checkAndApplyBooster` (lines 1031–1054)

When the booster qualifies (`_checkAndApplyBooster`) it sets `boostperc = newRate` on **all existing** packages of the boosted user. Good.

But the `invest` function unconditionally pushes new packages with `boostperc: 0` (line 330):

```solidity
userInvestments[msg.sender].push(Investment({
    …
    boostperc: 0
}));
```

So an investor who is already `isBoosted = true` and adds a second package compounds the second package at the **base** rate, not the boosted rate. There is no later re-application path because `_checkAndApplyBooster` exits early on `if (u.isBoosted) return;`.

**Impact:** Boosted users silently lose the +0.5% daily on every new invest. Combined with the booster only being earnable in the first 7-day window, this is permanent under-payment.

**Recommendation:** When pushing a new package in `invest`, read the user's current effective booster:

```solidity
boostperc: user.isBoosted ? MIN_BOOSTER_PERC : 0
```

### H-3. Rank metrics monotonically increase — ghost-volume rank gaming

**File:** `i6systemcontract.sol`
**Code:** `_updateDownlineBusiness` (609–617), `_checkRankQualification` (727–744)

```solidity
users[currentUpline].totalDownlineBusiness += _amount;
users[currentUpline].freshBusiness += _amount;
```

Neither field is ever decremented when:

- A downline gets `isCapped = true` (their investments stop paying out).
- A downline's package reaches the 2.5x cap (`isActive = false`).
- A downline fully withdraws and stops compounding.

`_checkRankQualification` uses `directDB.totalDeposits + directDB.totalDownlineBusiness` to qualify ranks. Because that number never goes down, an uplines's rank requirements eventually become trivially satisfiable from historical "ghost" volume — including from downlines who long ago hit their 6x cap and produce nothing.

This is exploited by:

1. Sponsoring many small accounts up to MAX_DIRECTS=200 limit.
2. Letting them cycle through invest→cap→stop.
3. Their historical deposits remain on your `totalDownlineBusiness`, so you can rank up to higher salary tiers off purely dead volume.

**Recommendation:** Decrement `totalDownlineBusiness` on `isCapped`-toggle in withdraw, and on `inv.isActive = false` deactivation. Symmetric to the existing `_updateUplineStream(..., false, …)` cap-removal flow.

### H-4. `enableBuying` is reversible

**File:** `i6token.sol`
**Code:** `enableBuying` (108-112), `disableBuying` (114-116)

Project policy per `agents.md` is "buying is permanently closed". Contract enforces a 180-day delay before `enableBuying` can be called, but `disableBuying` can flip it back any time. The reverse — once enabled it can be re-disabled — is fine, **but the underlying issue is that nothing prevents enabling at all after the 180d**. The "permanently closed" guarantee rests on DAO honesty.

If a malicious / compromised DAO ever flips `buyingEnabled = true`, anyone can buy from the LP (which is locked to `0xdead` — so the only available `i6` to buy comes from later `withdraw` recipients dumping). The economic effect is mostly cosmetic since LP supply is dead, but the off-chain narrative "you can only get i6 by investing" breaks.

**Recommendation:** Either delete `enableBuying` entirely if buying must stay off forever, or wrap it with an additional immutable flag `lockBuyingForever` that the DAO can set once and never unset.

### H-5. ORIGIN_MEMBER_ID is a hardcoded EOA bypassing all caps

**File:** `i6systemcontract.sol:84`

```solidity
address constant ORIGIN_MEMBER_ID = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
```

ORIGIN:

- Bypasses 6x cap (every `if (… ORIGIN_MEMBER_ID || …)` branch).
- Bypasses the `pendingDirectBonus` cap when ORIGIN is the referrer (line 351).
- Bypasses the cap inside `_realizePendingDirectBonus` (line 404), `_realizeSalary` (810), `getPendingSalary` (834), `_realizeUplineIncome` (1007), `_realizeLevelIncome` (1076).
- On withdraw, ORIGIN's tokens are split across `GEN_W1..GEN_W7` (lines 583–598).

If the EOA key is lost or compromised:

- Lost → no genesis withdrawals are ever triggered, level-income for those reading ORIGIN's tree continues fine but the `_executeWithdrawTransfer` Genesis branch becomes inaccessible. Non-fatal.
- Compromised → attacker calls `withdraw()` from ORIGIN repeatedly, mints unbounded tokens to GEN_W1..7. If any GEN_W* is also attacker-controlled, full rug; if all are trusted, attacker just bricks the price by inflating supply into wallets they don't control.

**Recommendation:** Replace EOA ORIGIN with a multi-sig and add `setOriginMember` (DAO-controlled, time-locked) so a compromise is recoverable.

---

## 4. Medium findings

### M-1. Same-block receive cooldown is a griefing vector against withdraw

**File:** `i6token.sol:79-81, 96-98`

```solidity
if (!isWhitelisted[to]) {
    if (lastReceiveBlock[to] == block.number) revert Err_CooldownActive();
}
…
if (!isWhitelisted[to]) {
    lastReceiveBlock[to] = block.number;
}
```

Attacker sends `1 wei` of `i6` to victim in block N. Victim now has `lastReceiveBlock[victim] = N`. If the victim's own `withdraw()` lands in block N, the `safeTransfer` to victim inside `_executeWithdrawTransfer` reverts → the whole withdraw reverts.

The same-block tx lock in `invest`/`withdraw` already forces victim to wait one block between actions, so this rarely lines up — but on BSC (3-second blocks) and especially against high-rank ORIGIN withdraws (7 separate `safeTransfer` calls, each gateable per-recipient), the griefing window is real.

**Cost to attacker:** gas + arbitrary dust. The attacker can't drain anything, only delay.

**Recommendation:** Replace the receive-side check with a sender-only same-block check, **or** whitelist `systemContract` from cooldown when it is the sender (already whitelisted on the from-side, so withdraws normally pass — but the receive-side check still bites). Easiest: change the receive-block check to only apply when `from != systemContract`.

### M-2. Genesis 7-wallet split makes ORIGIN withdraw broadly griefable

**File:** `i6systemcontract.sol:583-598`

ORIGIN withdraw fires 7 sequential `projectToken.safeTransfer` calls. Each one goes through the token's `_update` and is independently subject to M-1: if **any** of `GEN_W1..GEN_W7` received an `i6` transfer in the same block (or even from a prior internal step inside this very same tx — but they're 7 distinct addresses so that path is clean), the entire ORIGIN withdraw reverts.

Combined with M-1, an attacker griefing all 7 hardcoded wallets per block is cheap on BSC.

**Recommendation:** Whitelist `GEN_W1..GEN_W7` in `isWhitelisted` (one-time DAO call). They are protocol-owned anyway. Whitelisting eliminates M-1/M-2 entirely for these recipients without weakening anti-bot protection.

### M-3. `_swapTokenFromPancakev2` silently skips `addLiquidity`

**File:** `i6systemcontract.sol:1207-1225`

```solidity
if (projectToken.balanceOf(address(this)) >= exactTokensNeeded) {
    …
    dexRouter.addLiquidity(…);
    emit LiquidityAdded(…);
}
…
if (currentBalance > initialTokenBalance) {
    IMintableBurnableERC20(address(projectToken)).burn(tokensToBurn);
}
```

If for any reason the balance check fails (e.g. attacker frontruns with a swap that distorts the `quote(...)` output upward), `addLiquidity` is silently skipped. The 40% USDT slice is **kept by the system** (so users aren't directly robbed) but the **expected LP-burn behavior is also silently dropped**. The user paid full price expecting "60% swap + 40% LP burn"; they got "60% swap, 40% sitting on the contract".

Combined with C-3 (DAO can rescue USDT) this becomes a real risk.

**Recommendation:**

- `revert` on the missing-balance branch — invest should be all-or-nothing.
- Or emit a distinct `LiquidityAddSkipped` event so off-chain monitors notice.

### M-4. Cap-drop / boost rate asymmetry leaks `levelRewardBase`

**File:** `i6systemcontract.sol`
**Code:** `_updateUplineStream` (1085–1116), `_checkAndApplyBooster` (1031–1054), `withdraw` (541–567)

The level base for each upline is `_amount * percent * rateFactor / 5000`. The same `_amount` is added with one rate at invest and subtracted with another at cap-drop:

- Invest: `_updateUplineStream(user, usdtAmount, true, userRate, true)` where `userRate = MIN_ROI_PERC` (since `currentRwpRate` is never assigned anywhere in the contract — confirm by `grep` showing only reads).
- Booster apply: a separate addition `_updateUplineStream(_user, activeVol, true, newRate, false)` with `newRate = MIN_BOOSTER_PERC`.
- Cap-drop in withdraw: `_updateUplineStream(msg.sender, vars.dropVol, false, vars.rate, false)` where `vars.rate = MIN_ROI_PERC`.

When the user is boosted, the **base rate portion** is subtracted symmetrically (correct), but the **booster portion is never subtracted**. After a cap, the boosted-rate base sits on the upline's `levelRewardBase` permanently. Conversely, on uncap (re-invest after cap) the original invest re-add at `userRate = MIN_ROI_PERC` doesn't re-include any booster, so the booster-portion's persistence is a one-way leak.

**Impact:** Uplines earn over-inflated level income on capped-and-restarted downlines. Magnitude is small per event but compounds with churn.

**Recommendation:** Track per-package `(amount, rateAtAdd, boostAtAdd)` and subtract the exact same components on cap. Or, simpler, normalize the rate factor to a single canonical value and recompute booster-driven additions/subtractions consistently.

### M-5. `getDirectBonusInfo` over-reports `availableNow`

**File:** `i6systemcontract.sol:411-439`

The lifetime-cap check in this view omits `u.directBonus` from `lifetimeCurrent`:

```solidity
uint256 lifetimeCurrent = u.totalWithdrawn + u.levelRewardsRealized
                       + u.pendingUplineIncome + u.unwithdrawnSalary;
```

But every other cap path includes `directBonus` (see `_realizeUplineIncome:1004`, `_realizeLevelIncome:1073`, `_realizeSalary:807`, `withdraw:485-486`). The view therefore reports a slightly higher available figure than the user can actually withdraw, which off-chain UIs will surface.

**Recommendation:** Add `+ u.directBonus` to `lifetimeCurrent` in `getDirectBonusInfo`.

### M-6. Permanent booster invariant — once true, never false

Already documented in `21_Economic/result.txt`. Once `isBoosted = true` (3 direct boosters during their first 7 days + matching deposits), there is **no condition** under which it is revoked. Boosters who churn out or get capped still leave their sponsor with the +0.5% rate forever.

**Recommendation:** Re-evaluate `directBoosterCount` and `directBoosterBusiness` (decrement on direct-cap / direct-withdraw cycles) and clear `isBoosted` when the qualifying inequality breaks.

### M-7. `_rpow` precision loss favors house

**File:** `i6systemcontract.sol:1141-1149`

`_rpow` uses fixed-point multiplication `(x * x) / scalar` with `scalar = WAD = 1e18`. Each multiplication truncates downward. Over many compounding days the user receives slightly less than the mathematical expectation. Confirmed in `20_Arithmetic`: 30-day rank-1 salary of 50 USDT pays 49.99999999999968 USDT due to division-before-multiplication in `salaryPerSec`.

For the multiplier path, the daily 0.5% rate over 365 iterations introduces ~10⁻¹⁵ error per day → ~3.6e-13 over a year. Materially zero per-user but biases against users in aggregate.

**Recommendation:** Acceptable as-is; document the truncation direction. If user-facing fairness matters, switch to PRBMath or a higher-precision fixed-point representation.

---

## 5. Low / informational

### L-1. `setROI` range mismatch

`setROI` (line 1235) accepts `[2,10]` but `_getMultiplier` only handles {5,7,8,10}. Tighten the setter range to `_value ∈ {5,7,8,10}` (or fix as per H-1) so a legitimate DAO update can't silently misconfigure.

### L-2. `_consumeMaintenanceVolume` writes dead state

`maintenanceBurnedVolume` (line 207) is written by `_consumeMaintenanceVolume` (lines 772–795) but never read elsewhere. Either remove the function and storage map, or wire it into rank qualification to prevent fresh-business reuse across cycles.

### L-3. `_realizePendingDirectBonus` updates start index per-iteration

Lines 388-395 update `pendingBonusStartIndex[_user] = i + 1` inside the loop. Move it after the loop to save SSTOREs. Saves a few k gas per claim.

### L-4. Token `rescueTokens` uses raw `transfer`

`i6token.sol:151`: `IERC20(_token).transfer(_to, _amount);` — BSC USDT does not return a bool. Use `SafeERC20.safeTransfer` (already pulled in by the system contract; needs an import here too).

### L-5. No emergency pause

There is no `pause()` switch. If a critical bug is discovered, DAO must either `setTradingPair(address(0))` (reverts `getSpotPrice` → reverts withdraws but invests still partially execute until `_swapTokenFromPancakev2` hits the `address(0)` cast), or upgrade-by-setter. Cleaner: add `pause()` / `unpause()` gating on `invest`, `withdraw`, `claimRank`.

### I-1. Genesis 50,000 USDT phantom deposit

Constructor (lines 235–246) seeds ORIGIN with `totalDeposits = 50_000 USDT` without any USDT transfer. ORIGIN's `MAX_INCOME_MULTIPLIER` cap is bypassed anyway, so the seed isn't economically capping anything, but it makes the math look as if 50k USDT was deposited when in reality the protocol owes the GEN_W* wallets up to 300k USDT in tokens against zero collateral. By design; document clearly to investors.

### I-2. DAO modeled as single EOA

`DAOMultisigController` is one address. Calling it a multisig depends on the **off-chain** key being one. A single-key compromise is a full takeover (H-5, C-3, C-4). Use an actual multisig contract (e.g. Gnosis Safe) and verify on-chain.

---

## 6. Gas analysis – `invest()` and `withdraw()`

Sources combine my static read + the existing `18_DoS`, `19_StorageBloat` measurements (which already use the BSC fork via `BaseForkSetup`). Numbers below are from those runs.

### invest()

Cost components (warm storage assumed, since uplines must have been registered before they can sponsor):

| Component | Cost driver | Approx gas |
|-----------|-------------|-----------|
| `_updateDownlineBusiness` | `maxDownlineDepth` iterations × 2 warm SSTOREs + 1 SLOAD | ~1,100 gas/level → 1.1M @ 1000 |
| `_updateUplineStream` (40 lvls) | 40 × `_realizeLevelIncome` (40-lvl inner loop) + SSTORE updates | ~10-25k/level |
| `_realizePendingDirectBonus` (sponsor) | array scan from `startIndex` | ~5k+ |
| `usdt.safeTransferFrom` (BSC USDT) | ERC20 transfer | ~50k |
| `_swapTokenFromPancakev2` | router swap + addLiquidity + burn | ~250–400k |
| Misc per-user SSTOREs | totalDeposits, directVolume, eligibility, etc. | ~30-60k |

Measured from `18_DoS/result.txt`:

| Scenario | Gas |
|----------|-----|
| Depth 100, 0 direct slots | 1,659,282 |
| Depth 100, 100 direct slots | 1,467,503 |
| Depth 1000, 200 direct slots (re-invest, 100 packages) | **2,964,441** |
| Depth 1000, 200 directs, new direct (200th slot) | **3,261,203** |

**Verdict:** Within BSC's 140M block limit and the standard 30M RPC tx limit. Worst case ~3.3M, safe by ~10x. **No DoS via depth/slots/packages.** Cost to a deep-tree investor is real but bounded: ~$0.3-1.5 at typical BSC gas prices.

### withdraw()

| Component | Cost driver | Approx gas |
|-----------|-------------|-----------|
| 3-day, cooldown, tx.origin, same-block checks | 4 SLOADs + compares | ~5k |
| `_realizePendingDirectBonus` | bounded by pending-direct array | ~5-10k |
| `_updateCompounding` | iterate up to 100 packages × `_rpow(O(log days))` | scales `~25k/pkg` |
| First pkg-loop (compute available RWP) | up to 100 packages SLOADs | scales `~10k/pkg` |
| `_realizeLevelIncome` + `_realizeUplineIncome` + `_realizeSalary` | 40-lvl loops + 3 lifetime-RWP recomputes | ~80-200k |
| Second pkg-loop (deduct, mark inactive) | up to 100 packages × SSTOREs | scales `~26k/pkg` |
| `_executeWithdrawTransfer` | spot price (1 SLOAD + getReserves) + mint + transfer | ~100-150k (regular), ~250-350k (ORIGIN: 7 transfers) |

Measured from `19_StorageBloat/result.txt`:

| Packages | Gas |
|----------|-----|
| 1   | 152,716 |
| 10  | 390,316 |
| 50  | 1,446,316 |
| 100 | **2,766,316** |

**Verdict:** Same as invest — within block limit by ~50x. ORIGIN-branch withdraw with 100 packages would land near ~3.0–3.2M gas. Acceptable.

### Hotspots / cheap wins

1. **`_realizeLevelIncome` runs inside `_updateUplineStream`** (line 1094). For 40 uplines each computing 40 levels, that's 40×40 = 1,600 SLOADs of `levelRewardBase[lvl]` per invest. ~5k gas. Cache the inner loop unlocked-levels once, skip empty slots.
2. **`_realizePendingDirectBonus`** writes `pendingBonusStartIndex` inside the loop (L-3) — move to outside loop.
3. **`_swapTokenFromPancakev2` calls `pair.getReserves()` twice** (lines 1178 and 1199). The second one is needed because reserves changed after the swap; OK. The first call's reserve-zero check can be elided since the router will revert anyway if the pool is empty.
4. **Two iterations over `userInvestments` in withdraw** (lines 456-469 and 520-543). One single pass with a temporary accumulator would save ~10k per package.
5. **`User.levelRewardBase[41]`** is a 41-slot array inside the struct (line 156). It occupies 41 contiguous slots per user — already warm after first touch. OK.
6. **`getTotalLifetimeRWP` called 3 times per withdraw** (`_realizeUplineIncome` reads `up1`, `up2`, `up3`'s lifetime RWP, each loops 100 packages). Cache.

---

## 7. Coverage matrix vs. existing in-tree test suite

| Suite | Vector | Result |
|-------|--------|--------|
| `01_AccessControl` | DAO / system / mint gating | Specs documented; tests pending run |
| `02_Minting` | mint guards, supply mono | Specs documented |
| `03_SupplyManipulation` | burn/mint flows | Specs documented |
| `04_Withdrawal` | cooldown, same-block, immediate-after-deposit | Specs documented |
| `12_Cooldown` | 1h cooldown, fuzz, boundary | **PASS** (6/6) |
| `13_SameBlockProtection` | system + token same-block | **PASS** (7/7) |
| `14_txOrigin` | EOA-only enforcement | **PASS** (4/4) |
| `15_Oracle` | reserve manip pricing | **PASS** (3/3) |
| `16_Liquidity` | pair/router setters, zero-reserve guard | **PASS** (4/4) |
| `17_Reentrancy` | invest/withdraw reentry | **PASS** (2/2) |
| `18_DoS` | depth/slots/packages gas scaling | DoS not reachable; gas profile recorded |
| `19_StorageBloat` | array-size scaling | Within block limit |
| `20_Arithmetic` | salary truncation, `_getMultiplier` fall-through | **CONFIRMED** (H-1, M-7) |
| `21_Economic` | spot-price manip, permanent booster | **CONFIRMED** (C-1, M-6) |
| `22_InvariantBreaking` | supply hyper-inflation, cyclic referrals | **CONFIRMED** (C-2) |
| `23_Governance` | malicious router, controller takeover | **CONFIRMED** (C-3, C-4, H-5, I-2) |
| `PriceDynamics/C2` | death-spiral tipping point | **REVERTS w/ panic 0x11** inside `withdraw()` — exposes a real arithmetic regression along the spiral path. Worth treating as its own High-severity issue (track to root cause in `withdraw`/`_updateUplineStream` subtraction). |

The `PriceDynamics` panic is the one untriaged failing test. Recommend isolating which subtraction in `withdraw()`'s cap-drop / level-decrement path underflows — likely the `_updateUplineStream` `false` branch's clamp interacting with the asymmetric booster bug (M-4) when `levelRewardBase` was inflated by boosted-rate additions then drained at base rate.

---

## 8. Recommended action plan

**Must-fix before any operational change**

1. C-1: TWAP-based price + `minTokensOut` on `withdraw`.
2. C-2: Add `MAX_SUPPLY` cap to `mint`.
3. C-3: Block USDT in `rescueAccidentalTokens` (or strictly bound it).
4. C-4: Time-lock `setDexRouter` / `setTradingPair`.
5. H-1: Replace `_getMultiplier` with arithmetic formula.
6. H-2: Honor `isBoosted` when pushing new packages.

**Strongly recommended**

7. H-3: Decrement `totalDownlineBusiness` / `freshBusiness` on cap-toggle.
8. H-4: Make buying-off truly irreversible if that is the stated policy.
9. H-5: Replace ORIGIN EOA with a multisig + DAO-rotatable address.
10. M-1 / M-2: Whitelist `GEN_W1..7` and reconsider receive-side same-block check.
11. M-3: Revert when `addLiquidity` is skipped (or emit a distinct warning event).
12. M-4: Symmetric booster accounting in upline level base.
13. M-5: Include `directBonus` in `getDirectBonusInfo` lifetime calc.

**Hygiene**

14. L-1 — L-5 cleanups.
15. Add an emergency pause and an explicit pause-only DAO role.
16. Document I-1 (50k phantom seed) and I-2 (multisig key handling) in user-facing docs.

**Operational**

17. Migrate `DAOMultisigController` from an EOA (current `0x4EA9…32f` per `i6token-values.md`) to a real Safe (`isWhitelisted[0x4EA9…32f] = false` per the same file — verify the multisig story off-chain).
18. Investigate the failing `PriceDynamics/C2_RatioSweep` panic and ship a regression test before deploying any fix that touches `_updateUplineStream` or `withdraw`'s cap path.

---

## 9. Appendix – test runner

All tests sit under `test/Phase 4/Step 1/tests/` and inherit `BaseFork.t.sol` which pins live BSC mainnet state (token, system, DAO, pair, router, USDT). Suggested invocation:

```bash
export BSC_RPC_URL="https://bsc-rpc.publicnode.com"   # or your archive node
forge test --match-path 'test/Phase 4/Step 1/tests/**' -vv
```

Each suite's pass/fail evidence lives next to its tests in `result.txt` / `result.md`, summarized in §7.
