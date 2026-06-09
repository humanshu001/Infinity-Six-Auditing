# invest() test results

date: 2026-06-08, forge 0.2.0, all 30 tests passed

## basic investment checks

1. a user can make their first investment successfully
2. a user can reinvest after their first deposit (in a new block)
3. investing exactly 100 usdt (the minimum) is accepted
4. investing less than 100 usdt is rejected
5. investing exactly 20,000 usdt (the maximum) is accepted
6. investing more than 20,000 usdt in a single call is rejected
7. a user can invest in multiple rounds as long as their total stays at or below 20,000 usdt
8. a user whose total would exceed 20,000 usdt with the new deposit is rejected

## referral checks

9. investing with a zero address as referrer is rejected
10. investing with yourself as the referrer is rejected
11. investing under a referrer who hasn't deposited anything is rejected
12. investing under a valid, active referrer works correctly and records the relationship
13. a referrer who already has 199 direct referrals can still accept one more (the 200th)
14. a referrer who already has 200 direct referrals cannot accept any more — the 201st is rejected

## anti-bot and contract interaction checks

15. a user cannot invest twice in the same block — the second call is rejected
16. a smart contract trying to call invest() is rejected (tx.origin != msg.sender)
17. investing through an EIP-1167 minimal proxy is rejected
18. investing through a multicall wrapper contract is rejected
19. investing through an EIP-4337 smart wallet (account abstraction) is rejected

## state and accounting checks

20. the first deposit correctly initializes the user's data: total deposits, referrer, investment package, and activation timestamp
21. when an existing user reinvests, the system first compounds their existing packages before adding the new one
22. a non-capped user can reinvest and remains non-capped
23. when bob invests under alice within 7 days of alice's activation, alice's booster direct counter increments
24. when bob invests under alice after 7 days of alice's activation, alice's booster direct counter does not increment
25. when bob invests under alice, alice's downline business counter increases by bob's deposit amount
26. when bob invests under alice, a direct bonus (5% of bob's deposit) is created for alice with a 12-hour lock period
27. the investor's usdt balance decreases by exactly the investment amount
28. when bob invests under alice, alice's team volume increases by bob's deposit amount
29. multiple investments by the same user create separate investment packages (not merged into one)
30. the system has a guard limiting users to 100 investment packages maximum

## observations

- the 200-direct tests consume ~248 million gas each due to 200 sequential invest calls, showing the system is gas-heavy at maximum direct capacity
- the 12-hour direct bonus lock works correctly — bonuses are created as pending entries with a future unlock timestamp
- reinvestment properly triggers compounding on existing packages before adding new ones, confirmed by the compounded principal growing above the original amount after 5 days
- the booster period window (7 days from sponsor activation) is enforced correctly
