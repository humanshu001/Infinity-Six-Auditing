# Infinity Six — Open Items After Owner Decisions

Owner plan: renounce ownership + set DAO multisig controller to null address (`0x0`) after audit.

This file lists **only the findings that still need attention** — either because:
- They are **NOT mitigated** by DAO-null (anyone, not just DAO, can trigger them), OR
- They are **conditional** on the contract state at the moment of renounce, OR
- They **must be done pre-renounce** because after renounce they become permanent.

Findings marked DESIGN (29, 30, 32) and findings fully closed by DAO-null (24, 27, 31, I-2) have been removed. Reference-only confirmed-safe checks (38 GasAnalysis, 39 FlashLoan) also removed.

Re-test command pattern for any item: `forge test --match-path 'test/Phase 4/Step 1/tests/<dir>/*.sol' -vv`.

---

## Scoreboard — open items only

| #  | Test            | Code     | Why still open | Required action |
|----|-----------------|----------|----------------|-----------------|
| 25 | SpotPriceMint   | C-1      | `withdraw` + `mint` not DAO-gated; any attacker can trigger | **Patch contract pre-renounce** |
| 26 | NoMaxSupply     | C-2      | `mint()` runs on every withdraw, no DAO involvement | **Patch contract pre-renounce** |
| 28 | Multiplier      | H-1, L-1 | `MIN_ROI_PERC` frozen at renounce; only some values work | **Verify value + ideally patch** |
| 33 | TokenGriefing M-1 | M-1    | Dust-spam blocks user withdraw same block; not DAO-gated | **Patch contract pre-renounce** |
| 33 | TokenGriefing M-2 | M-2    | ORIGIN 7-wallet split each griefable; mitigation needs DAO call | **Call setWhitelist BEFORE renounce** |
| 34 | LiquiditySkip   | M-3      | 40% LP step silently skipped; not DAO-gated | **Patch contract pre-renounce** |
| 35 | DirectBonusView | M-5      | View formula drifts from cap formula | **Patch contract pre-renounce** |
| 37 | Hygiene L-5     | L-5      | No pause exists, after renounce cannot be added | **Decide: accept permanent risk OR add now** |
| 40 | MEVSandwich     | (MEV)    | Cross-block sandwich costs victim ~2.35% | **Patch contract pre-renounce (same fix as C-1)** |
| later/ | 05-11        | —        | Test stubs not yet run | **Run before mainnet trust** |

---

## CRITICAL — owner reasoning needs rethinking

### 25_SpotPriceMint — C-1 — Withdraw can mint 11x more tokens than expected

**Owner's stated belief:** "Price is in USDT. If price drops, user gets more tokens, sells them, gets USDT back. No problem."

**Why this belief is wrong** — three concrete reasons:

1. **`withdraw()` MINTS new i6 from nothing.** It does not pull from a fixed reserve. Formula:
   ```
   mintAmount = usdtReward * 1e18 / getSpotPrice()
   ```
   Lower spot → MORE new tokens minted.
2. **The pool has finite USDT.** A withdrawer who minted 919 i6 (because pool was crashed) cannot sell all 919 back at par. Pool empties, slippage destroys price further.
3. **The next withdrawer mints even more.** Because the previous sale dumped, spot is lower, formula mints more. Self-reinforcing. **No DAO involvement at any step.**

**Test numbers:**
- Normal pool, spot 1.001 USDT/i6 → user got 76.62 i6.
- After dumping 5,000,000 i6 to crash pool, spot 0.167 USDT/i6 → user got 919.03 i6.
- **11x more i6 minted for the same USDT input.**
- `withdraw()` selector `0x3ccfd60b` is zero-arg → user cannot set a "minimum tokens" guard.

**Why DAO renounce does not help:**
- `withdraw()` is callable by any user.
- `mint()` access control is `onlySystem` — the system contract calls it during normal withdraw, no DAO needed.
- Any wallet with enough i6 can crash the public PancakeSwap pool.

**Fix — must be applied BEFORE renouncing (after renounce, unfixable):**
1. Add `uint256 minTokensOut` to `withdraw()`. Revert if `userAmount < minTokensOut`.
2. Replace `getSpotPrice()` with TWAP using `price0CumulativeLast` / `price1CumulativeLast` over at least 30 minutes.
3. Cap mint per withdraw against `MAX_TOKENS_PER_USD`.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/25_SpotPriceMint/*.sol' -vv`

---

### 26_NoMaxSupply — C-2 — Token has no maximum supply

**Owner's stated belief:** "Once owner renounced and DAO is null, no person can change router → safe."

**Why this belief is wrong** — `mint()` is **not** DAO-gated.

```solidity
function mint(address to, uint256 amount) external onlySystem { ... }
```

`onlySystem` means "caller = configured system contract". The system contract calls `mint()` automatically inside every `withdraw()` to give the user their i6 reward. So:

- Every normal user withdraw → triggers a mint.
- No DAO approval required.
- No human button press.

**Combined with C-1:** one bad withdraw against a crashed pool mints trillions of i6. Test demonstrated 1 trillion in one call. Renouncing DAO does **not** touch this path.

**Test recap:**
- `MAX_SUPPLY()` getter: does not exist.
- Single call minted 1,000,000,000,000 i6.
- Supply went from ~594,389 → ~1 trillion. No revert. No event.

**Fix — BEFORE renounce (after renounce, unfixable):**
- Add `uint256 public constant MAX_SUPPLY = 1e9 * 1e18;` (or whatever ceiling).
- Inside `mint()`:
  ```solidity
  require(totalSupply() + amount <= MAX_SUPPLY, "cap");
  ```
- Alternative: per-second / per-block rate limit.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/26_NoMaxSupply/*.sol' -vv`

---

## HIGH — conditional, must verify at renounce time

### 28_Multiplier — H-1 + L-1 — ROI fall-through (full deep dive)

#### The function

```solidity
function _getMultiplier(uint256 rate) internal pure returns (uint256) {
    if (rate == 10) return 1010000000000000000;  // 1.010 → 1.0% daily
    if (rate == 8)  return 1008000000000000000;  // 1.008 → 0.8% daily
    if (rate == 7)  return 1007000000000000000;  // 1.007 → 0.7% daily
    return         1005000000000000000;          // 1.005 → 0.5% daily ← catch-all
}
```

Only 3 rates handled explicitly: 10, 8, 7. Everything else → 0.5% default.

#### The setter

```solidity
function setROI(uint256 _value) external DAOMultiSignRequired {
    if (_value < 2 || _value > 10) revert Err_InvalidROI();
    MIN_ROI_PERC = _value;
}
```

`setROI` accepts 2..10 inclusive.

#### Truth table

| `setROI(x)` | DAO intends | What user gets | Verdict |
|-------------|-------------|----------------|---------|
| 2  | 0.2% | **0.5%** | broken — protocol over-pays |
| 3  | 0.3% | **0.5%** | broken — protocol over-pays |
| 4  | 0.4% | **0.5%** | broken — protocol over-pays |
| 5  | 0.5% | 0.5% | works (by accident — hits default) |
| 6  | 0.6% | **0.5%** | broken — user UNDER-paid |
| 7  | 0.7% | 0.7% | works |
| 8  | 0.8% | 0.8% | works |
| 9  | 0.9% | **0.5%** | broken — user UNDER-paid |
| 10 | 1.0% | 1.0% | works |

Only 4 of 9 valid inputs give the rate they appear to set.

#### Booster makes it worse

In `_updateCompounding`:
```solidity
uint256 multiplier = _getMultiplier(userRate + packages[i].boostperc);
```

Lookup uses `userRate + boostperc`. Combinations that fall through:

- userRate=5, boostperc=5 → lookup=10 → 1.0% daily ✓
- userRate=7, boostperc=5 → lookup=12 → **0.5%** ✗ (boost makes user slower!)
- userRate=8, boostperc=5 → lookup=13 → **0.5%** ✗
- userRate=10, boostperc=5 → lookup=15 → **0.5%** ✗

So if rate is ever 7, 8, or 10, every boosted user gets demoted to 0.5%.

#### Math impact — 1,000 USDT, 30 days

| Rate | multiplier^30 | Lifetime RWP after 30d | Profit % |
|------|---------------|------------------------|----------|
| 10 (works)        | 1.34785 | 1,347.85 USDT | 34.79% |
| 8  (works)        | 1.27024 | 1,270.24 USDT | 27.02% |
| 7  (works)        | 1.23271 | 1,232.71 USDT | 23.27% |
| 6 expected (0.6%) | 1.19668 | **1,196.68 USDT** | 19.67% |
| 6 actual (0.5%)   | 1.16140 | **1,161.40 USDT** | 16.14% |
| 9 expected (0.9%) | 1.30865 | **1,308.65 USDT** | 30.87% |
| 9 actual (0.5%)   | 1.16140 | **1,161.40 USDT** | 16.14% |

`setROI(9)`: users expect ~31% in 30 days, get ~16%. **Roughly half the promised return**, silently, no error.

#### After renounce

`setROI` is `DAOMultiSignRequired`. With DAO = null:
- `MIN_ROI_PERC` frozen at whatever value at renounce.
- Renounce while `MIN_ROI_PERC ∈ {5, 7, 8, 10}` → safe forever.
- Renounce while `MIN_ROI_PERC ∈ {2, 3, 4, 6, 9}` → **permanently broken**.

#### Required pre-renounce actions

**1. Verify current rate on live system:**
```bash
cast call <SYSTEM_ADDR> "MIN_ROI_PERC()(uint256)" --rpc-url <BSC_RPC>
```
Must be 5, 7, 8, or 10. If anything else → call `setROI(...)` to a safe value BEFORE renouncing.

**2. Strongly recommended — replace switch with arithmetic so every rate works AND booster combinations work:**
```solidity
function _getMultiplier(uint256 rate) internal pure returns (uint256) {
    return WAD + (rate * WAD) / 1000;
}
```
After this fix:
- `rate = 2` → 0.2% ✓
- `rate = 6` → 0.6% ✓
- `rate = 9` → 0.9% ✓
- All booster combinations work.

Kills H-1 AND L-1 in one change. **Without it, every boosted user at rate ∈ {7,8,10} silently compounds at 0.5%.**

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/28_Multiplier/*.sol' -vv`

---

## MEDIUM — must fix pre-renounce (cheap, permanent if missed)

### 33_TokenGriefing M-1 — Dust attack blocks withdraw

- Attacker sends 1 wei of i6 to victim at block N. Victim's `withdraw()` at block N reverts with `Err_CooldownActive`. Next block works.
- Not DAO-gated. Any wallet can grief any user repeatedly.
- **Fix (pre-renounce):** Remove receive-side same-block check OR exempt transfers coming from `systemContract`.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/33_TokenGriefing/*.sol' -vv`

### 33_TokenGriefing M-2 — ORIGIN payout split griefable

- ORIGIN withdraw sends to 7 hardcoded wallets `GEN_W1..GEN_W7` sequentially. Any one being dust-spammed in the same block bricks the whole ORIGIN withdraw.
- **Mitigation (DAO action, must be done BEFORE renounce):** DAO calls `setWhitelist(GEN_Wn, true)` for each of the 7 wallets. After renounce this is impossible.

### 34_LiquiditySkip — M-3 — 40% LP step silently skipped

- Code: `if (balanceOf >= needed) { addLiquidity(...); emit ...; }` — no else branch.
- On balance mismatch the 40% step is skipped silently. User paid for it, got nothing. Leftover sits on contract.
- **Fix (pre-renounce):** Either revert in the missing-balance branch OR emit `LiquidityAddSkipped` event so off-chain monitors notice.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/34_LiquiditySkip/*.sol' -vv`

### 35_DirectBonusView — M-5 — Dashboard formula drifts from real cap math

- View `getDirectBonusInfo` omits `directBonus` from `lifetimeCurrent`. Real cap-check includes it.
- Dashboards over-report user's `availableNow` near the 6x cap.
- **Fix (pre-renounce):** Add `+ u.directBonus` to the view's `lifetimeCurrent` term.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/35_DirectBonusView/*.sol' -vv`

### 40_MEVSandwich — Cross-block sandwich on withdraw

- MEV bot front-runs victim's withdraw with a 20,000 USDT invest. Spot rises to 1.025 USDT/i6. Victim's mint shrinks ~2.35%.
- Same fix as C-1: `minTokensOut` argument on `withdraw()`. Kills both findings.
- Must be done pre-renounce.

Run: `forge test --match-path 'test/Phase 4/Step 1/tests/40_MEVSandwich/*.sol' -vv`

---

## INFO — permanent risk to accept consciously

### 37_Hygiene L-5 — No emergency pause

- No `pause()` / `unpause()` / `paused()` exists on the system contract.
- After renounce, **a pause function cannot be added**. If any new bug surfaces later (including new bugs in dependencies, BSC consensus changes, PancakeSwap exploits), the only response is "do not interact with the contract".
- **Decision needed:**
  - Accept this risk permanently (renounce as planned), OR
  - Add Pausable + a non-renouncing pause guardian BEFORE renouncing main owner.

If accepting: document publicly so users understand the trade-off.

---

## Pending — run before live mainnet trust

Stubs in `later/`. Test execution not started. Each currently reads "Pending test execution results."

| Folder | Topic |
|---|---|
| 05_Deposit | Deposit attacks |
| 06_Referral | Referral attacks |
| 07_TeamVolume | Team volume attacks |
| 08_ROI | ROI attacks |
| 09_Booster | Booster attacks |
| 10_SalaryReward | Salary reward attacks |
| 11_UplineIncome | Upline income attacks |

These categories overlap several findings already confirmed (28, 29, 30, 35). Running them may surface additional cases that interact with the renounce decision.

---

## Pre-renounce checklist (do everything below, in order)

If any step missed, the corresponding bug becomes permanent.

1. **Patch C-1**: add `minTokensOut` to `withdraw()`, switch `getSpotPrice()` to TWAP, add per-USD mint cap. Same patch also kills MEV cross-block (#40).
2. **Patch C-2**: add `MAX_SUPPLY` cap inside `mint()`.
3. **Patch H-1 / L-1**: replace `_getMultiplier` switch with arithmetic. Alternatively at minimum, set `MIN_ROI_PERC` to 5, 7, 8, or 10 before renouncing — but this still leaves boosted users broken.
4. **Patch M-1**: relax receive-side same-block check or exempt `systemContract` transfers.
5. **DAO action M-2**: call `setWhitelist(GEN_Wn, true)` for each of the 7 GEN wallets.
6. **Patch M-3**: revert or emit on liquidity-skip branch.
7. **Patch M-5**: fix view formula.
8. **Decide L-5**: accept no-pause permanently OR add Pausable + guardian.
9. **Pre-renounce state verification:**
   - `dexRouter()` = real PancakeSwap V2 router (`0x10ED43C718714eb63d5aA57B78B54704E256024E`).
   - `buyingEnabled()` = `false` AND `timeUntilBuyUnlock` still high.
   - `MIN_ROI_PERC` ∈ {5, 7, 8, 10}.
   - All 7 GEN wallets whitelisted on the token.
10. **Run the 7 pending test suites in `later/` to confirm no new findings** before final renounce.

---

## Bottom line

Open after owner decisions:
- **2 Critical** require code patches (C-1, C-2) — owner's reasoning that DAO-null mitigates them is wrong; these paths are not DAO-gated.
- **1 High** is conditional (H-1) — must verify rate is in a safe set, ideally patch to arithmetic so booster combinations also work.
- **4 Medium** are cheap pre-renounce patches (M-1, M-3, M-5, MEV cross-block) — trivial to fix today, impossible to fix after renounce.
- **1 Info** (L-5 no pause) is a permanent risk decision.
- **7 test suites pending** — run before renounce so no surprise findings surface after the contract is frozen.

**Single highest-leverage patch:** `withdraw()` gets a `minTokensOut` argument + TWAP price. Closes C-1, neutralizes MEV cross-block, and prevents C-2's unlimited-mint path from being reachable through normal user behaviour.
