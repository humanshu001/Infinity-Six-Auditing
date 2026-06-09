# oracle test results

date: 2026-06-08, forge 0.2.0, all 7 tests passed

## getSpotPrice()

1. normal reserves: returns the correct exchange rate based on the token ratio when reserves are in the normal range (e.g. 485,277 usdt and 425,497 project tokens)
2. tiny reserves: returns the correct exchange rate when reserves are extremely low (10 wei and 5 wei), indicating no division-by-zero or precision limits on scale
3. huge reserves: returns the correct exchange rate when reserves are extremely large (1e30 wei), validating that the math does not cause overflow reverts
4. empty reserves: reverts with Err_NoLiquidity when either reserve is zero, preventing invalid or zero pricing operations

## manipulation

5. pump price: when an external action increases the usdt reserve and decreases the project token reserve, getSpotPrice() responds instantaneously and returns a high price (e.g. 20 usdt per token)
6. dump price: when an external action decreases the usdt reserve and increases the project token reserve, getSpotPrice() responds instantaneously and returns a low price (e.g. 0.025 usdt per token)
7. flash loan reserve distortion: when the pool reserves are crashed via a simulated flash loan swap (e.g. down to 0.01 usdt per token), a user withdrawing their roi receives heavily inflated project tokens (750 tokens instead of 6.5 tokens), proving that the contract is vulnerable to instant price distortion attacks

## observations

- getSpotPrice() relies on instantaneous reserves from the uniswap pool. because there is no time-weighted average price (twap) or external oracle fallback, the contract is highly vulnerable to flash loan price manipulation.
- an attacker can distort the pool price within a single transaction block, withdraw their generated rwp or rewards at a heavily inflated token conversion rate, and drain the protocol's mintable supply.
