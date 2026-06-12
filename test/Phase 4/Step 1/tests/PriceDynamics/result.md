PriceDynamics test run result
=============================

Date: 2026-06-11
Suite path: test/Phase 4/Step 1/tests/PriceDynamics/*.sol

Command run:
  .\bin\forge.exe test --match-path 'test/Phase 4/Step 1/tests/PriceDynamics/*.sol' -vv

Mainnet-value setup checked before running
------------------------------------------
The suite was checked against the values documented in:
  - i6systemcontract-values.md
  - i6token-values.md

The PriceDynamics harness uses the documented BSC mainnet values for the key
external dependencies and policy assumptions:
  - Pancake router: 0x10ED43C718714eb63d5aA57B78B54704E256024E
  - USDT: 0x55d398326f99059fF775485246999027B3197955
  - DAO multisig: 0x4EA9802681Fb877DE5407974E63F197EE754032f
  - documented live i6 pair: 0x13D55200c298Ff1caE3136BE0dd889626DEAC782
  - buying is disabled / permanently closed in the token value file
  - withdrawals have a 3600 second cooldown
  - tx.origin checks block contract calls
  - same-wallet same-block actions are blocked

Important nuance:
The tests do not interact with the live deployed i6 token/system contracts at
0xd2e052c7faE5DDeD7A7B2CdDd27B5d75D18A1593 and
0x51A36b17b5dbD013C632dCb411F71E935392fe5e. Instead, they fork BSC for the real
Pancake router/USDT environment, then deploy fresh local copies of the i6 token
and system contracts and seed a fresh i6/USDT pool. Therefore these are forked
economic simulation tests using mainnet infrastructure and documented parameter
values, not direct live-contract regression tests.

Run outcome
-----------
Initial sandboxed run:
  - Compilation succeeded.
  - Fork creation failed because outbound BSC RPC access was blocked by the
    sandbox:
    vm.createSelectFork could not connect to https://bsc-dataseed.binance.org.

Rerun with network access:
  - Compilation skipped because artifacts were current.
  - Foundry ran 2 tests in C2_RatioSweep.
  - Result: 0 passed, 2 failed.

Failing tests:
  - test_C2_ratio_sweep()
  - test_C2_spiral_at_2x()

Failure:
  - Both tests revert with Solidity panic 0x11, meaning arithmetic underflow or
    overflow.
  - Verbose trace shows the panic occurs inside InfinitySixSystem.withdraw()
    during the simulated withdraw-and-sell path.

Observed emitted rows before failure:
  CSV|0|1262500000000000000|1262500000000000000000000|1000000000000000000000000|2000000000000000000000000|0|0
  CSV|1|1263601729965514131|1263451540191055616833293|999881141525136552385194|1999881141525136552385194|1000000000000000000000|48459808944383166707
  CSV|2|1264800656689543261|1264451540191055616833293|999723975081257932504463|1999723975081257932504463|2000000000000000000000|48459808944383166707

Assessment: are these tests well written?
------------------------------------------
Partially, but not enough for audit-grade conclusions yet.

What is good:
  - They use a BSC fork rather than static reserve mocks, which is the right
    direction for AMM price-dynamics testing.
  - They include the documented real router, USDT, DAO, pair, disabled-buying,
    tx.origin, cooldown, and same-block assumptions.
  - They emit CSV-style price/reserve/supply/accounting rows, which is useful
    for analyzing economic behavior instead of only pass/fail status.
  - They separate reusable mechanics into a harness.

What is weak or incorrect:
  - The tests currently fail, so they cannot support the intended death-spiral
    claim as written.
  - The harness deploys fresh local i6 contracts and a fresh pair, so it does not
    verify behavior against the actual live deployed i6 system/token state.
  - The seed price uses 1.2625e18, while i6systemcontract-values.md records
    getSpotPrice as 1262533071561801545. That is close, but not exact.
  - The harness starts currentBlock at 100 on a BSC fork whose real block number
    is around 103,580,xxx, then rolls to artificial low block numbers. That is a
    bad model for same-block protection on a fork and can create unrealistic
    sequencing.
  - The ratio-sweep withdraw logic allows expected withdraw failures to be
    swallowed with try/catch, but the test still later fails from arithmetic
    panic. Expected reverts should be classified explicitly, not silently hidden.
  - The focused test named test_C2_spiral_at_2x does not assert monotonic
    decline, despite the comment saying it does. It only runs the scenario.
  - The Read.md and comments reference old paths/names such as 19_PriceDynamics
    and C2_RatioSweep.t.sol, while the actual files are PriceDynamics/Main.t.sol
    and PriceDynamics/Price.t.sol.
  - The test suite only covers scenario C2. The documentation itself lists many
    planned scenarios that are not implemented.

Recommended improvements
------------------------
1. Initialize block rolling from the fork block:
     currentBlock = block.number;
   Then increment from there. Do not roll BSC fork tests backward to block 100.

2. Use the exact documented spot price:
     1262533071561801545
   Or derive the seed reserve ratio from that value instead of hard-coding an
   approximate 1.2625 price.

3. Add a direct live-state verification test that attaches to the deployed
   token/system addresses and asserts the current documented values before any
   simulation:
     buyingEnabled == false
     WITHDRAWAL_COOLING_PERIOD == 3600
     token.systemContract == documented system
     system.projectToken == documented token
     system.getSpotPrice == documented value, or within a deliberate tolerance

4. Fix the withdraw panic before using this suite as evidence. The trace points
   to InfinitySixSystem.withdraw(), so the test should isolate whether the
   underflow is caused by unrealistic time/block movement, insufficient
   compounding state, cap accounting, or an actual production-code arithmetic
   bug.

5. Replace broad try/catch around withdrawals with explicit expected outcomes:
     - success path: assert token amount received and sold
     - expected revert path: assert the exact custom error
     - unexpected panic: fail immediately with context

6. Make test_C2_spiral_at_2x assert what it claims. Store per-round prices and
   assert decline over the intended back-half window.

7. Add scenarios for:
     - single invest price impact
     - single withdraw price impact
     - cooldown enforcement at exactly 3599/3600/3601 seconds
     - same-wallet same-block blocking
     - contract-call rejection via tx.origin
     - buying disabled behavior for normal users
     - live deployed pair reserve comparison

Conclusion
----------
The tests are directionally useful but currently not well written enough to rely
on for final audit conclusions. They compile and reach the BSC fork, but the two
implemented PriceDynamics tests fail with arithmetic panic before completing.
The suite should be fixed and tightened before its economic results are used as
evidence.
