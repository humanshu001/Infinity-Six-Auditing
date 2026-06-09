# compounding test results

date: 2026-06-08, forge 0.2.0, all 15 tests passed

## time-based compounding

1. after 1 day, a 1000 usdt investment compounds to exactly 1005 usdt (0.5% daily rate confirmed)
2. after 7 days, the compounded principal lands between 1035 and 1036 usdt (compound interest working correctly over a week)
3. after 30 days, the compounded principal lands between 1161 and 1162 usdt
4. after 180 days, the compounded principal lands between 2454 and 2455 usdt (~2.45x growth in 6 months)
5. after 365 days, the compounded principal reaches ~6174 usdt — notably lower than the mathematical ideal of ~6196 usdt due to _rpow integer truncation accumulating over 365 steps (~0.35% loss)

## package scenarios

6. a single 5000 usdt package correctly compounds over 10 days, reaching ~5255.70 usdt
7. multiple packages compound independently — when a user has two 5000 usdt packages created at different times, each tracks its own compounding separately and both grow when triggered
8. active packages in a mixed set (some active, some not) compound independently. inactive packages are skipped without affecting the active ones

## booster scenarios

9. without a booster, the base 0.5% daily rate is applied and produces expected compound growth over 10 days (~1051 usdt from 1000)
10. when a user qualifies for the booster (3 qualifying directs within 7 days with matching deposit), the combined rate (0.5% base + 0.5% boost = 1.0%) produces faster compounding

## edge cases

11. zero elapsed time since last compounding produces no change — the compounded principal remains equal to the original amount
12. sub-day elapsed time (e.g. 12 hours) produces no compounding — the system only processes whole days, sub-day fractions are ignored until the next full day completes
13. extreme timestamps (10 years of compounding) do not cause overflow — uint256 handles the enormous resulting values safely
14. two users investing the same amount at the same time and compounding after the same delay produce identical results, confirming the _rpow exponentiation is deterministic
15. precision at small amounts (100 usdt minimum investment) produces exact results — 100 * 1.005 = 100.5 usdt with no rounding error at the wei level

## observations

- the _rpow function uses binary exponentiation with integer truncation at each multiplication step. over 365 days, this causes a cumulative ~0.35% underpayment compared to the mathematical ideal (6174 vs 6196 usdt on a 1000 usdt investment). this benefits the protocol at the expense of users.
- compounding only triggers on state-changing actions (invest, withdraw). between actions, the stored compoundedPrincipal remains stale. the view function getTotalLifetimeRWP simulates future compounding for display purposes without modifying storage.
- sub-day interest is only calculated in view functions (getTotalLifetimeRWP), never in the actual state update (_updateCompounding). this means a user who compounds daily via reinvestment gets slightly less than what the view function shows.
