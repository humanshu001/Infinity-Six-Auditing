# 19_PriceDynamics - i6 Buy/Sell, Price Movement & Death-Spiral Tests

This suite models the **economic price dynamics** of the InfinitySix system,
not gas/DoS (that lives in `18_DoS`). It exercises how the i6 spot price moves
up and down with investments and withdrawals, and demonstrates the conditions
under which the token economy enters a **death spiral**.

## Why this MUST be a fork test

The death spiral is an **emergent property of the AMM constant-product curve**.
It only appears when pool reserves actually move with each buy/sell. The
`18_DoS` suite uses static `vm.mockCall` reserves, which freeze the price and
would hide the spiral. These tests therefore run against a **BSC mainnet fork**
with the real PancakeSwap V2 router and a real i6/USDT pair.

```bash
export BSC_RPC_URL="https://bsc-dataseed.binance.org"   # or your archive node
forge test --match-path "*19_PriceDynamics/*" -vv
```

## Mechanics being modelled

Matching `_swapTokenFromPancakev2` and `_executeWithdrawTransfer`:

| Action     | Effect on pool / supply |
|------------|--------------------------|
| **invest($X)** | 60% of `X` swapped USDT->i6 (price **up**, pool i6 down); 40% added as LP to `0xdead` (locked); surplus i6 **burned** (supply down) |
| **withdraw()** | 100% of the USD reward value **minted** as i6 at spot price; 5% fee; remainder sent to user, who **sells** it (price **down**, supply up) |

Net seed of the spiral: invest = *buy + LP-lock + burn*; withdraw = *mint + sell*.
With external buying closed forever, the only buy pressure is contract-driven on
invest, so once withdraw pressure dominates, price reflexively declines.

## Files

- `PriceDynamicsHarness.t.sol` - base harness: BSC fork + deploy, pool seeding
  (seeded so spot ~= 1.2625 USDT/i6, the live `getSpotPrice` value), funding
  helpers, `_invest`, `_withdrawAndSell`, price/reserve readers, an in-test
  USD-in vs USD-out solvency ledger, and a `CSV|`/`RATIO|` logger for plotting.
- `C2_RatioSweep.t.sol` - **Scenario C2**: sweeps withdraws-per-invest from 0.1x
  to 5.0x and reports `ratio -> finalPrice`, locating the tipping point. Also
  includes `test_C2_spiral_at_2x` for a focused single-ratio demonstration.

## Reading the output

```bash
forge test --match-contract C2_RatioSweep -vv | grep '^  CSV|'   > c2_curve.csv
forge test --match-contract C2_RatioSweep -vv | grep '^  RATIO|' > c2_summary.csv
```

Columns for `CSV|`: `round | spotPrice | poolUsdtReserve | poolI6Reserve | totalSupply | usdDepositedIn | usdRealizedOut`.
Plot `round` vs `spotPrice` and vs `poolUsdtReserve` to visualise the spiral
(equivalent to `gas_plots.png` in `18_DoS`).

## Planned scenarios (this MR ships the harness + C2)

- **A. Single-action calibration** - per-action price impact (invest/withdraw at
  $100 / $1k / $20k); invest/withdraw asymmetry residual.
- **B. Healthy growth** - many invests / few withdraws; hidden compounding
  liability overhang.
- **C. Death spiral** - C1 withdrawal wave, **C2 ratio sweep (shipped)**,
  C3 pool-USDT drain to zero, C4 spot-price manipulation amplifier (finding #5).
- **D. User-base composition** - whales vs minnows, early vs late cohort
  realised USD, ORIGIN/genesis uncapped extraction, coordinated bank run.
- **E. Guard interactions** - cooldown throttle, per-stream withdrawal caps,
  6x cap as supply ceiling, invest-swap slippage under volatility.

Subsequent MRs will add A, B, C1/C3/C4, D and E on top of this harness.
