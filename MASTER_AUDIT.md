# Infinity Six — Master Audit Results

Consolidated output of every executed test suite under `test/Phase 4/Step 1/tests/` plus pending suites under `later/`. Each entry lists: scope, what it checked, what the test produced, plain-English summary, recommended fix, and the run command.

Test stack: Foundry on a BSC mainnet fork (`BaseFork.t.sol`). Severity tags reference findings in `AUDIT.md`.

---

## Summary Table

| #  | Suite              | AUDIT ref   | Severity | Status | Headline result |
|----|--------------------|-------------|----------|--------|-----------------|
| 24 | RescueDrain        | C-3         | Critical | PASS   | DAO drains 1,000 USDT float in one call |
| 25 | SpotPriceMint      | C-1         | Critical | PASS   | 11x mint multiplier after spot collapse; no `minTokensOut` |
| 26 | NoMaxSupply        | C-2         | Critical | PASS   | 1 trillion i6 minted in one call; no cap |
| 27 | RouterHotSwap      | C-4         | Critical | PASS   | DAO re-points router → 600 USDT (60%) stolen per invest |
| 28 | Multiplier         | H-1, L-1    | High/Low | PASS   | `setROI(9)` silently compounds at 0.5% (default fall-through) |
| 29 | BoosterBugs        | H-2, M-6    | High/Med | PASS   | New packages after boost have `boostperc=0`; booster never revoked |
| 30 | GhostVolume        | H-3         | High     | PASS   | `totalDownlineBusiness` only grows; no decrement on cap/withdraw |
| 31 | BuyingFlip         | H-4         | High     | PASS   | DAO can re-enable buying after 180-day lock; no permanent lock fn |
| 32 | OriginBypass       | H-5         | High     | PASS   | ORIGIN bypasses 6x cap; address is EIP-7702 EOA, immutable |
| 33 | TokenGriefing      | M-1, M-2    | Medium   | PASS   | Dust transfer blocks victim withdraw same block; ORIGIN 7-wallet split griefable |
| 34 | LiquiditySkip      | M-3         | Medium   | PASS   | `addLiquidity` silently skipped on balance mismatch; no event |
| 35 | DirectBonusView    | M-5         | Medium   | PASS   | View omits `directBonus` from cap formula; over-reports `availableNow` |
| 36 | Precision          | M-7         | Medium   | PASS   | `_rpow` rounds down; salary 30-day shortfall ~320,000 wei (dust) |
| 37 | Hygiene            | L-2,L-4,L-5,I-2 | Low/Info | PASS | Dead `maintenanceBurnedVolume`; raw `transfer`; no pause; **live DAO is EOA** |
| 38 | GasAnalysis        | (DoS profile) | Info  | PASS   | Worst case ~3.56M invest / ~2.24M withdraw — NOT DoS vulnerable |
| 39 | FlashLoan          | (attack surface) | Info | PASS | `tx.origin == msg.sender` blocks flash-loan-funded invest/withdraw |
| 40 | MEVSandwich        | (MEV)        | Info     | PASS   | In-block blocked; cross-block costs victim ~2.35% i6 |
| 05 | Deposit (later)    | —           | —        | Pending| Not executed |
| 06 | Referral (later)   | —           | —        | Pending| Not executed |
| 07 | TeamVolume (later) | —           | —        | Pending| Not executed |
| 08 | ROI (later)        | —           | —        | Pending| Not executed |
| 09 | Booster (later)    | —           | —        | Pending| Not executed |
| 10 | SalaryReward (later)| —          | —        | Pending| Not executed |
| 11 | UplineIncome (later)| —          | —        | Pending| Not executed |

All 17 executed suites PASS — i.e. the test successfully demonstrated the vulnerability or measured the property.

---

## CRITICAL findings

### 24_RescueDrain — C-3 — DAO drains user USDT

- **Tests**
  - `test_C3_dao_can_drain_user_usdt_from_live_system` — PASS
  - `test_C3_project_token_rescue_still_blocked` — PASS
- **Measured**
  - System USDT at forked block: 0.000 USDT (test seeds 1,000 USDT via `deal`)
  - Drained to attacker: 1,000.000 USDT, system balance after: 0
  - `projectToken` rescue still reverts with `Err_CannotDrainRewardTokens`
- **Mechanism**: `rescueAccidentalTokens` blocks the i6 token but NOT USDT. DAO multisig (`0x4EA9...32f`) can call any time, no time-lock, transfer entire in-flight invest float to any address.
- **Fix**: Block USDT (and any custodied token) inside `rescueAccidentalTokens`. If non-USDT rescue ever needed, bound to `IERC20(token).balanceOf(this) - expectedFloat`.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/24_RescueDrain/*.sol' -vv`

### 25_SpotPriceMint — C-1 — withdraw mints against unprotected spot

- **Tests**
  - `test_C1_withdraw_mints_proportional_to_spot_collapse` — PASS
  - `test_C1_no_minTokensOut_parameter_exposed` — PASS
- **Measured**
  - Baseline spot 1.001 USDT/i6 → 76.62 i6 minted
  - Manipulated spot 0.167 USDT/i6 (after dumping 5M i6 into pair) → 919.03 i6 minted
  - Mint multiplier: **11x**
  - `withdraw()` selector `0x3ccfd60b` is zero-arg — no `minTokensOut`
- **Mechanism**: `withdraw()` takes zero args. Mint = `usdtReward * 1e18 / getSpotPrice()`. Pool spot can be collapsed pre-withdraw → 10x+ inflation. This is core of the death-spiral.
- **Fix**:
  1. Add `uint256 minTokensOut` to `withdraw()` and revert when `userAmount < minTokensOut`.
  2. Replace `getSpotPrice()` with TWAP via `price0CumulativeLast`/`price1CumulativeLast` over ≥30 min.
  3. Cap mint per withdraw against DAO-tunable `MAX_TOKENS_PER_USD`.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/25_SpotPriceMint/*.sol' -vv`

### 26_NoMaxSupply — C-2 — i6 token has no ceiling

- **Tests**
  - `test_C2_token_has_no_max_supply_constant` — PASS
  - `test_C2_system_can_mint_arbitrary_amount` — PASS
- **Measured**
  - `MAX_SUPPLY()` getter: **absent**
  - Supply before: ~594,389 i6 (live mainnet)
  - Minted in single call: **1,000,000,000,000 i6 (1 trillion)**
  - Supply after: ~1,000,000,594,389 i6 — no revert, no cap, no event
- **Mechanism**: Sole access on `mint()` = "caller must be configured system". Combined with C-1, one withdraw against depressed reserves hyper-inflates supply (22_InvariantBreaking measured 600,000x inflation in 1 tx).
- **Fix**: Add immutable `uint256 public constant MAX_SUPPLY` (e.g. `1e9 * 1e18`); check `totalSupply() + amount <= MAX_SUPPLY` inside `mint()`. Alternative: rate-limit per second/block.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/26_NoMaxSupply/*.sol' -vv`

### 27_RouterHotSwap — C-4 — DAO swaps router, skims 60%

- **Tests**
  - `test_C4_dao_can_hot_swap_router_and_steal_invest_swap_portion` — PASS
  - `test_C4_no_timelock_on_setDexRouter` — PASS
- **Measured**
  - `setDexRouter(MaliciousRouter)` — instant, no delay
  - 1,000 USDT invest after swap → **600 USDT (60%) stolen** by attacker
  - `pendingDexRouter()` does not exist — no two-phase migration
- **Mechanism**: Compromised DAO installs malicious router; `swapExactTokensForTokens` pulls approved USDT and forwards to attacker. Skims 60% (swap portion) of every invest forever. Combined with C-3, DAO has near-total power over funds.
- **Fix**: Two-phase / time-locked `setDexRouter`: set `pendingDexRouter`, emit event, activate after delay (e.g. 7 days). Apply same to `setTradingPair`. Delay = investors get a withdrawal window.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/27_RouterHotSwap/*.sol' -vv`

---

## HIGH findings

### 28_Multiplier — H-1 + L-1 — ROI fall-through

- **Tests**
  - `test_H1_documented_rates_compound_correctly` — PASS — ROI=5 → 161.40 USDT lifetime RWP @ 30d
  - `test_H1_undocumented_rates_silently_fall_to_default` — PASS — ROI=5 and ROI=9 BOTH yield 161.40 USDT (bug)
  - `test_L1_setROI_accepts_values_that_fall_through` — PASS — `setROI(6)`/`setROI(9)` accepted; `setROI(1)`/`setROI(11)` revert
- **Mechanism**: `_getMultiplier(rate)` is hardcoded switch on `{5,7,8,10}`; default returns 0.5% daily. `setROI` accepts `[2,10]` → 2,3,4,6,9 all silently fall through to 0.5%.
- **Fix**: Replace switch with arithmetic:
  ```solidity
  function _getMultiplier(uint256 rate) internal pure returns (uint256) {
      return WAD + (rate * WAD) / 1000;
  }
  ```
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/28_Multiplier/*.sol' -vv`

### 29_BoosterBugs — H-2 + M-6 — booster only applies once, never revoked

- **Tests**
  - `test_H2_new_package_after_boost_has_zero_boostperc` — PASS — second package has `boostperc=0` (expected 5)
  - `test_M6_isBoosted_is_never_revoked` — PASS — no `revokeBooster()`/`removeBooster()` selector
- **Mechanism**:
  - H-2: `invest()` hardcodes `boostperc: 0` on every new package even after `isBoosted == true`. Later deposits lose +0.5% daily forever.
  - M-6: `_checkAndApplyBooster` exits early on already-boosted; no clear path. Sticky permanently even if directs cap/withdraw.
- **Fix**:
  - H-2: At package-creation in invest, `boostperc: user.isBoosted ? MIN_BOOSTER_PERC : 0`.
  - M-6: Re-evaluate `directBoosterCount`/`directBoosterBusiness` on direct cap/withdraw, clear `isBoosted` when inequality breaks — or document as design intent.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/29_BoosterBugs/*.sol' -vv`

### 30_GhostVolume — H-3 — `totalDownlineBusiness` only grows

- **Tests**
  - `test_H3_totalDownlineBusiness_only_grows` — PASS — 6,000 USDT after build → 6,000 USDT after 1y + every chain member withdraws (UNCHANGED)
  - `test_H3_no_decrement_path_exists_in_abi` — PASS — no `clearDownlineBusiness()`/`recomputeDownlineBusiness()`
- **Mechanism**: `_updateDownlineBusiness` increments on invest. NEVER decremented on cap, 2.5x, or withdraw. Rank metrics climb on "ghost volume" no longer producing income.
- **Fix**: Symmetric decrement: when `isCapped` flips true (and on each package deactivation), walk up `maxDownlineDepth` uplines and SUBTRACT from `totalDownlineBusiness` + `freshBusiness`. Existing `_updateUplineStream(false, ...)` cap-drop loop is the right shape — extend it.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/30_GhostVolume/*.sol' -vv`

### 31_BuyingFlip — H-4 — DAO can flip buying after 180-day lock

- **Tests**
  - `test_H4_buyingEnabled_currently_false_but_unlock_pending` — PASS — `buyingEnabled=false`, `timeUntilBuyUnlock ~10,633,134s (~123 days)`
  - `test_H4_dao_can_enable_then_disable_then_re_enable` — PASS — 3 flips succeeded
  - `test_H4_no_lock_buying_forever_function_exists` — PASS — no `lockBuyingForever()` selector
- **Mechanism**: agents.md says "buying disabled forever", but on-chain only a 180-day delay then DAO can flip freely. `enableBuying` and `disableBuying` reversible after `deployTime + 180d`.
- **Fix**: If buying-off is a hard guarantee:
  1. Remove `enableBuying()` entirely, OR
  2. Add immutable one-shot `lockBuyingForever()`.
  Document choice in whitepaper.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/31_BuyingFlip/*.sol' -vv`

### 32_OriginBypass — H-5 — ORIGIN immune to 6x cap, hardcoded immutable

- **Tests**
  - `test_H5_origin_member_is_hardcoded` — PASS — ORIGIN at `0xdF4f...1cd1`, 50,000 USDT genesis, code size 23 → **EIP-7702 set-code delegate** (EOA with delegate)
  - `test_H5_origin_can_withdraw_past_6x_cap` — PASS — `isCapped=false` after 1y + withdraw
  - `test_H5_no_setter_to_rotate_origin` — PASS — no `setOriginMember(address)` selector; constant IMMUTABLE
- **Mechanism**: Every cap branch short-circuits on `_user == ORIGIN_MEMBER_ID`. ORIGIN unbounded lifetime payout. If ORIGIN private key compromised → attacker can `withdraw()` forever, minting i6 to GEN_W1..GEN_W7. Either unbounded extraction or supply-bricking.
- **Fix**:
  1. Replace EOA / EIP-7702 ORIGIN with a real multisig contract.
  2. DAO-controlled time-locked `setOriginMember()` for key compromise recovery.
  3. Cap ORIGIN withdrawals per-day.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/32_OriginBypass/*.sol' -vv`

---

## MEDIUM findings

### 33_TokenGriefing — M-1 + M-2 — receive cooldown grief + ORIGIN 7-wallet split

- **Tests**
  - `test_M1_dust_send_to_victim_blocks_withdraw_in_same_block` — PASS — withdraw REVERTS at block N with `Err_CooldownActive` after attacker sends 1 wei i6; succeeds at block N+1 (76.62 i6)
  - `test_M2_origin_withdraw_splits_to_7_wallets` — PASS — ORIGIN withdraw fires 7 sequential transfers; each independently gated by `lastReceiveBlock`
- **Mechanism**: Token `_update` reverts when non-whitelisted recipient already received in same block. Dust spam ahead of victim's withdraw → revert. ORIGIN's 7-wallet split amplifies: any one recipient griefed → entire ORIGIN withdraw fails.
- **Fix**:
  1. Remove receive-side same-block check, OR exempt transfers from `systemContract`.
  2. DAO whitelists `GEN_W1..GEN_W7` so ORIGIN's split never trips cooldown.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/33_TokenGriefing/*.sol' -vv`

### 34_LiquiditySkip — M-3 — `addLiquidity` silently skipped

- **Tests**
  - `test_M3_no_revert_when_addLiquidity_path_is_skipped` — PASS — normal invest mints ~399.97 LP to `0xdead` (40% portion burned)
- **Mechanism**: `_swapTokenFromPancakev2` wraps `addLiquidity` in `if (projectToken.balanceOf(this) >= exactTokensNeeded)`. No else branch → no revert, no event when guard fails. User paid for 60% swap + 40% LP, got only 60% swap. Leftover sits on contract, drainable per C-3.
- **Fix**: Either revert in missing-balance branch (all-or-nothing invest) or emit `LiquidityAddSkipped` event.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/34_LiquiditySkip/*.sol' -vv`

### 35_DirectBonusView — M-5 — view omits `directBonus` from cap calc

- **Tests**
  - `test_M5_view_omits_directBonus_from_cap_check` — PASS
  - `test_M5_view_does_not_revert_on_cap_users` — PASS — ORIGIN `availableNow=0`, `pendingLocked=0`
- **Mechanism**:
  - View `getDirectBonusInfo`: `lifetimeCurrent = totalWithdrawn + levelRewardsRealized + pendingUplineIncome + unwithdrawnSalary`
  - State path: `... + directBonus + ...`
  - View over-reports `availableNow` near the 6x cap.
- **Fix**: Add `+ u.directBonus` to `lifetimeCurrent` in `getDirectBonusInfo`.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/35_DirectBonusView/*.sol' -vv`

### 36_Precision — M-7 — compounding/salary rounding bias

- **Tests**
  - `test_M7_compound_truncation_after_1_year` — PASS — 1,000 USDT principal → 2,500 USDT lifetime RWP (= 2.5x cap)
  - `test_M7_salary_per_second_truncation` — PASS
    - `salaryPerSec` Rank 1: 19,290,123,456,790 wei
    - Sum over 30 days: 49.99999999999968 USDT
    - Expected: 50.0 USDT
    - **Shortfall: ~320,000 wei (~0.00032 cents)**
- **Mechanism**: `_rpow` rounds down on every multiplication. `_realizeSalary` divides `rankIncome / 30 days` before multiplying by elapsed seconds. Dust loss biased AGAINST user — protocol "house edge".
- **Fix**: Acceptable as-is; document direction. If fairness matters, switch to PRBMath and round HALF_UP.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/36_Precision/*.sol' -vv`

---

## LOW / INFORMATIONAL findings

### 37_Hygiene — L-2, L-4, L-5, I-2

- **Tests**
  - `test_L2_maintenanceBurnedVolume_is_dead_state` — PASS — read OK (0); no other code reads it → dead state
  - `test_L4_token_rescueTokens_uses_raw_transfer` — PASS — uses `IERC20.transfer` not `SafeERC20.safeTransfer`; non-bool-returning tokens (legacy BSC USDT layout) may silently fail
  - `test_L5_no_emergency_pause_function` — PASS — no `pause()` / `unpause()` / `paused()`; bug response = redeploy
  - `test_I2_dao_modeled_as_single_address` — PASS — DAO = `0x4EA9802681Fb877DE5407974E63F197EE754032f`, **code size 0 → EOA, not multisig**
- **Headline (I-2)**: "DAOMultisigController" name implies multisig; live address is single-key EOA. Every "DAO can rug" scenario in AUDIT.md gated on one private key.
- **Fix**
  - L-2: Remove `maintenanceBurnedVolume` or integrate into `_checkMaintenanceQualification`.
  - L-4: Switch `rescueTokens` to `SafeERC20.safeTransfer`.
  - L-5: Add OZ Pausable + `onlyDAO whenNotPaused` on `invest`/`withdraw`/`claimRank`.
  - I-2: Replace EOA DAO with Gnosis Safe (or similar).
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/37_Hygiene/*.sol' -vv`

### 38_GasAnalysis — invest/withdraw DoS profile

Methodology: BSC fork + LOCAL mock USDT / pair / router to isolate MLM-logic gas from PancakeSwap overhead. Add ~350k to invest and ~150k to ORIGIN-withdraw for real on-chain interactions.

Boundaries: 100 packages/user, 200 directs/sponsor, 1000 upline depth.

**Raw measurements (all PASS):**

| Scenario | Gas | % of 140M BSC block | % of 30M RPC cap |
|---|---|---|---|
| BEST invest under ORIGIN (1st, depth=1) | 775,108 | 0.55% | 2.58% |
| BEST withdraw, 1 package, depth=1 | 199,566 | 0.14% | 0.66% |
| MED invest depth=100 | 1,805,116 | 1.28% | 6.01% |
| MED withdraw, 10 packages | 443,709 | 0.31% | 1.47% |
| WORST invest depth=200 | 1,914,214 | 1.36% | 6.38% |
| WORST invest, 200th direct on sponsor | 2,010,637 | 1.43% | 6.70% |
| WORST withdraw, 100 packages | 2,085,475 | 1.49% | 6.95% |
| ABSOLUTE WORST withdraw 100p/50d/100d | 2,085,475 | 1.49% | 6.95% |

**Slopes:**
- invest vs upline depth: cold levels ~10,404 gas/level (1..100); warm ~1,090 gas/level (100..200)
- invest vs sponsor directs: ~6,210 gas/direct at depth-1
- withdraw vs packages: cold ~27,127 gas/pkg (1..10); warm ~18,242 gas/pkg (10..100)

**Extrapolated absolute worst (100p / 200d / 1000d):**
- invest: 775k + 1.235M (200 directs) + 1.2M (999 levels) + 350k (Pancake) ≈ **~3,560,000 gas** (2.5% BSC block, 11.9% RPC cap)
- withdraw: 2.085M (100 pkg) + 150k (Pancake) ≈ **~2,235,000 gas** (1.6% BSC block, 7.5% RPC cap)

**Verdict**: Worst case fits in single tx with ~10x RPC headroom and ~30-60x BSC block headroom. **NOT gas-DoS vulnerable.** Confirms earlier 18_DoS / 19_StorageBloat result (~3.26M for same boundary on real-router path).

`BaseFork.t.sol` verified to fork BSC mainnet correctly via `_verifyMainnetState()` (buyingEnabled=false, correct pair, system, maxDownlineDepth=1000, non-zero launchTime, documented DAO). Public BSC RPCs prune state — heavy tests use local mocks; light tests (24, 25, 27 etc.) use live state directly.

- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/38_GasAnalysis/*.sol' -vv`

### 39_FlashLoan — attack surface closed

- **Tests**
  - `test_flash_loan_invest_is_rejected_by_tx_origin_check` — PASS — invest reverts inside `pancakeCall` callback; pair K-check then reverts outer swap; attacker loses nothing, extracts nothing
  - `test_flash_loan_via_token_pair_dump_blocked` — PASS — `token.isWhitelisted(SYSTEM)=true`, `attacker=false`; contract↔contract transfer between non-whitelisted reverts with `Err_NoContractCallsAllowed`
- **Mechanism**: `tx.origin == msg.sender` on `invest()`/`withdraw()`/`claimRank()` closes the entire flash-loan surface. Token `_update` extends to transfers between non-whitelisted accounts.
- **Trade-off**: Audited multisig wallets (Gnosis Safe, EIP-7702 accounts) cannot interact with the protocol at all.
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/39_FlashLoan/*.sol' -vv`

### 40_MEVSandwich — cross-block sandwich on withdraw

- **Tests**
  - `test_MEV_baseline_withdraw_amount` — PASS — baseline spot 1.001 USDT/i6 → 153.15 i6 minted
  - `test_MEV_cross_block_sandwich_front_run_reduces_mint` — PASS — MEV bot front-runs with 20,000 USDT invest, spot → 1.025 USDT/i6, victim mint → 149.54 i6, **loss ~3.61 i6 (~2.35%)**
  - `test_MEV_same_block_sandwich_is_blocked` — PASS — system `lastBlockNumber` + token `lastTxBlock` + token `lastReceiveBlock`
- **Mechanism**: In-block sandwich impossible. Cross-block possible: MEV invests right before target withdraw, pushes spot up, shrinks victim's i6 by ~2-3%. Bot cost = real invest amount; incentive murky since buying is closed (cannot easily resell minted i6). Most likely manifestation = unintentional, from clustered EOA timing.
- **Fix**: Add `uint256 minTokensOut` to `withdraw()`. UI computes expected mint and sets `minTokensOut` to ~98% of expected. Any front-run pushing mint below 98% reverts. (Same fix as C-1.)
- **Run**: `forge test --match-path 'test/Phase 4/Step 1/tests/40_MEVSandwich/*.sol' -vv`

---

## Pending suites (`later/`)

These directories contain stub `result.txt` only — tests not yet executed.

| Dir | Topic |
|---|---|
| 05_Deposit | Deposit Attacks |
| 06_Referral | Referral Attacks |
| 07_TeamVolume | Team Volume Attacks |
| 08_ROI | ROI Attacks |
| 09_Booster | Booster Attacks |
| 10_SalaryReward | Salary Reward Attacks |
| 11_UplineIncome | Upline Income Attacks |

Each stub reads: `Pending test execution results.`

---

## Aggregate verdict

- **4 Critical** confirmed (C-1, C-2, C-3, C-4). DAO holds drain, router-skim, mint, and supply-cap power; all four chain together for total fund extraction.
- **5 High** confirmed (H-1..H-5). ROI fall-through, booster strip, ghost volume, buying re-enable, ORIGIN bypass.
- **6 Medium** confirmed (M-1, M-2, M-3, M-5, M-6, M-7). Grief vectors, silent skip, view drift, sticky booster, rounding dust.
- **4 Low/Info** confirmed (L-1, L-2, L-4, L-5, I-2). Hygiene + the structural finding that the "DAO multisig" is a live EOA.
- **Attack-surface profile**: flash-loan blocked by `tx.origin`; in-block MEV blocked; cross-block MEV costs ~2.35%; protocol NOT gas-DoS vulnerable at configured boundaries.
- **Single highest-leverage fix**: replace `getSpotPrice()` with TWAP + add `minTokensOut` to `withdraw()` — neutralizes C-1 and M-40 cross-block MEV simultaneously and removes the core death-spiral amplifier.
- **Single highest-leverage governance fix**: replace the EOA DAO (`0x4EA9...32f`) with a Gnosis Safe — every "DAO can rug" scenario is currently gated on one private key.
