# package cap test results

date: 2026-06-08, forge 0.2.0, all 5 tests passed

## 2.5x package cap

1. package slightly below: when a package compounds near but below the 2500 usdt cap (e.g. 1332 usdt rwp generated after 170 days), the package remains active and allows multiple withdrawals up to the generated limit
2. package exactly or exceeding cap: when a package compounds past the 2.5x limit (e.g. after 300 days), the generated rwp is capped at exactly 2500 usdt (2.5x of the 1000 usdt deposit) and the package is deactivated (isActive = false)
3. multiple packages: when a user has multiple packages, each package enforces its 2.5x cap independently, deactivating only when its own accumulated rwp reaches its cap

## state changes on cap

4. active volume removal: when a downline user's package caps, their volume is removed from their referrer's level reward base (Alice's levelRewardBase at level 1 is reduced by 1000 usdt to 0 when Bob's package caps)
5. reinvestment after cap: after a package is capped and deactivated, the user can successfully buy a new package (reinvest), which is created as a new active investment under their account

## observations

- since withdrawals are capped at 1000 usdt per transaction (roi_max_withdrawal), a user with a capped 1000 usdt package (2500 usdt total rwp) must withdraw 3 times sequentially (spaced by the 60-minute cooldown) to fully withdraw their capped rwp and trigger deactivation.
- the contract does not immediately deactivate a capped package when it hits the cap; it only deactivates it when the user actually withdraws and the total rwpWithdrawn reaches the 2.5x cap.
