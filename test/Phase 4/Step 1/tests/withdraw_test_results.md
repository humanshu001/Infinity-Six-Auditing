# withdraw() test results

date: 2026-06-08, forge 0.2.0, all 20 tests passed

## invest extras — contract interaction blocking

1. investing through an EIP-1167 minimal proxy contract is blocked
2. investing through a multicall wrapper contract is blocked
3. investing through an EIP-4337 smart wallet is blocked

all three confirm that any contract-mediated call (where tx.origin differs from msg.sender) is rejected. this means flash loan contracts, proxy wallets, and aggregator contracts cannot interact with invest().

## access controls

4. withdrawing within 3 days of contract launch is rejected — users must wait the full lock period
5. a user with zero deposits cannot withdraw — they are told they have no active investment
6. a user with no accumulated rewards cannot withdraw — the system correctly identifies nothing is available

## withdrawal cooldown

7. the first withdrawal after the lock period works correctly
8. attempting a second withdrawal within 60 minutes of the first is rejected
9. attempting a second withdrawal at exactly 60 minutes is still rejected (the check uses <=, so 60 minutes is not enough)
10. a second withdrawal succeeds after waiting more than 60 minutes and letting new rewards accumulate

## reward categories

11. a user with only roi (daily compounding returns) can withdraw successfully and receives project tokens
12. a user who received a direct referral bonus can withdraw it after the 12-hour lock expires
13. a user with multiple income streams (roi + direct bonus + level income from 5 referrals) can withdraw all categories in one call

## withdrawal limits

14. the roi withdrawal cap (1,000 usdt per withdrawal) is applied — even with large accrued roi, only up to the limit is paid out

## 6x income cap

15. a withdrawal that stays below the 6x lifetime cap does not flag the user as capped
16. when a user's total withdrawals reach 6x of their deposits, they are marked as capped and cannot earn further rewards
17. the proportional scaling mechanism works correctly — when the 6x cap is hit mid-withdrawal, the remaining amount is split proportionally across all income categories (roi, direct, level, upline, salary) and total withdrawn never exceeds 6x

## anti-bot

18. a user cannot call withdraw twice in the same block — the second call is rejected before even checking the cooldown

## token minting and fees

19. withdrawals correctly mint project tokens to the user's wallet based on the current spot price
20. the 5% transaction fee is applied correctly — the user receives 95% of (usdt value / spot price) in project tokens. the fee is not minted or stored anywhere; it is simply deducted from the calculation

## observations

- the cooldown uses `<=` comparison, meaning users must wait 60 minutes and 1 second, not just 60 minutes
- `lastBlockNumber` is updated inside `_executeWithdrawTransfer()`, so the same-block check always triggers before the cooldown check when both would apply
- the 5% fee is a "phantom fee" — it reduces the user's payout but the fee tokens are never created, effectively acting as deflation
- the 6x cap proportional scaling uses integer division with dust recovery to ensure no wei is lost in rounding
