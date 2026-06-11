# Infinity Six -- Audit Test Suite Summary

This folder contains 17 test suites, each backing one or more findings in
`AUDIT.md` (at repo root). Every suite extends the single shared harness
`BaseFork.t.sol`, forks BSC mainnet, and asserts the live mainnet snapshot
matches the documented values before running.

## How to run

```bash
# Set an RPC (any BSC node works for light suites; archive node recommended
# for the heavy gas analysis).
export BSC_RPC_URL="https://bsc-rpc.publicnode.com"

# Optional reproducibility -- pin to a specific BSC block.
export BSC_BLOCK_NUMBER=0   # 0 = latest

# Run a single suite
forge test --match-path 'test/Phase 4/Step 1/tests/24_RescueDrain/*.sol' -vv

# Run all suites
forge test --match-path 'test/Phase 4/Step 1/tests/**/*.sol' -vv
```

Each suite folder has its own `result.txt` with the human-readable test
output and a recommended fix.

## Is BaseFork.t.sol forking BSC mainnet correctly?

**Yes.** The rewritten harness does three things to guarantee fork
correctness:

1. **`vm.createSelectFork(BSC_RPC_URL[, BSC_BLOCK_NUMBER])`** -- forks the
   live chain. If `BSC_BLOCK_NUMBER` is set, the fork is reproducible.
2. **`_verifyMainnetState()`** runs after the fork is established and
   asserts:
   - `token.buyingEnabled() == false`
   - `token.liquidityPair() == 0x13D55200…C782`
   - `token.systemContract() == 0x51A36b…fe5e`
   - `token.totalSupply() > 0`
   - `system.maxDownlineDepth() == 1000`
   - `system.launchTime() > 0`
   - both `DAOMultisigController` values match the documented
     `0x4EA9…32f`
   If any of these fail, the fork is NOT pointing at BSC mainnet and the
   test panics in setUp().
3. The harness exposes BOTH a live-state path (light tests use it
   directly) AND a fresh-deploy path (`_deployFreshSystem()`) for tests
   that need a clean MLM tree, with the same documented constants. The
   fresh path still uses the real PancakeSwap factory + router from the
   live fork.

### Was the ORIGINAL BaseFork.t.sol being used correctly?

The original file was a **correct fork-base** but a **shallow harness**:

| Original behavior | Issue | Fix in this rewrite |
|---|---|---|
| `createSelectFork(rpc)` only | Not reproducible -- "latest" drifts | Added optional `BSC_BLOCK_NUMBER` pin |
| Minimal interfaces (~15 fns) | Could not drive invest/withdraw or read `users()` | Imports the concrete contracts; full ABI available |
| No helpers | Every test reimplemented funding, time advance, deploy | Centralised `_deployFreshSystem`, `_invest`/`_withdraw`, `_buildDownlineChain`, `_buildDirects`, `_userIsBoosted`/`_userIsCapped`/... |
| `pragma ^0.8.24` | Lower than the contracts (^0.8.34) | Bumped to ^0.8.34 |
| No fresh-deploy path | Many invariants need clean state | Added local deployment with seeded Pancake pair |

The ANALYSIS above stays embedded as the file-header docstring of
`BaseFork.t.sol`, so a future reader can audit the harness alongside the
findings.

## Suite Index

| # | Folder | Findings | Status |
|---|--------|----------|--------|
| 24 | `24_RescueDrain` | C-3 | PASS (2/2) |
| 25 | `25_SpotPriceMint` | C-1 | PASS (2/2) -- demonstrates 11x mint multiplier on price collapse |
| 26 | `26_NoMaxSupply` | C-2 | PASS (2/2) -- 1 trillion i6 minted in one tx |
| 27 | `27_RouterHotSwap` | C-4 | PASS (2/2) -- 600 USDT skimmed on 1k invest |
| 28 | `28_Multiplier` | H-1, L-1 | PASS (3/3) -- ROI=9 silently compounds at 0.5% |
| 29 | `29_BoosterBugs` | H-2, M-6 | PASS (2/2) -- new package boostperc=0 after boost activation |
| 30 | `30_GhostVolume` | H-3 | PASS (2/2) -- totalDownlineBusiness frozen at 6,000 USDT after caps |
| 31 | `31_BuyingFlip` | H-4 | PASS (3/3) -- DAO can flip enable/disable indefinitely |
| 32 | `32_OriginBypass` | H-5 | PASS (3/3) -- ORIGIN remains uncapped after 1y of withdraws |
| 33 | `33_TokenGriefing` | M-1, M-2 | PASS (2/2) -- dust send blocks victim withdraw |
| 34 | `34_LiquiditySkip` | M-3 | PASS (1/1) -- silent addLiquidity skip path documented |
| 35 | `35_DirectBonusView` | M-5 | PASS (2/2) -- view-formula mismatch documented |
| 36 | `36_Precision` | M-7 | PASS (2/2) -- 320,000 wei salary shortfall over 30 days |
| 37 | `37_Hygiene` | L-2, L-4, L-5, I-2 | PASS (4/4) -- live DAO confirmed as code-size-0 EOA |
| 38 | `38_GasAnalysis` | DoS profile | 8/8 PASS in mock harness (see file) |
| 39 | `39_FlashLoan` | Defense | PASS (2/2) -- tx.origin closes the attack surface |
| 40 | `40_MEVSandwich` | C-1 / MEV | PASS (3/3) -- 2.35% loss on cross-block sandwich |

## Headline gas numbers

(See `38_GasAnalysis/result.txt` for full table + extrapolations.)

| Scenario | Gas used | % of BSC block (140M) | % of std RPC cap (30M) |
|---|---|---|---|
| BEST invest (depth 1) | 775,108 | 0.55% | 2.58% |
| BEST withdraw (1 pkg) | 199,566 | 0.14% | 0.66% |
| WORST invest (200 directs) | 2,010,637 | 1.43% | 6.70% |
| WORST invest (depth 200) | 1,914,214 | 1.36% | 6.38% |
| WORST withdraw (100 pkg) | 2,085,475 | 1.49% | 6.95% |
| **ABSOLUTE** invest (extrapolated to 100p/200d/1000d) | **~3.56M** | **2.5%** | **11.9%** |
| **ABSOLUTE** withdraw (100p/depth/directs-independent) | **~2.24M** | **1.6%** | **7.5%** |

No DoS at any documented contract boundary.
