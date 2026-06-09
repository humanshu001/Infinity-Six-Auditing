1. INVEST() TESTS
Basic
Valid first investment
Valid reinvestment
Minimum investment exactly 100 USDT
Below minimum investment
Exactly maximum investment
Above maximum investment
Total deposits reaching max limit
Total deposits exceeding max limit
Referral
Zero referrer
Self referrer
Inactive referrer
Active referrer
Referrer at 199 directs
Referrer at 200 directs
Referrer exceeding 200 directs
Anti-Bot
Same block double invest
Contract call invest
Proxy contract invest
Multicall invest
EIP4337 wallet invest
State
First deposit initialization
Existing user reinvestment
Capped user reinvestment
Booster period active
Booster period expired
2. WITHDRAW() TESTS
Access
Withdraw before launch+3days
Withdraw with zero deposits
Withdraw while capped
Withdraw with nothing available
Cooldown
First withdrawal
Within 60 minutes
Exactly 60 minutes
After 60 minutes
Categories
ROI only
Direct only
Level only
Salary only
Upline only
Mixed categories
Limits
ROI limit hit
Direct limit hit
Level limit hit
Salary limit hit
Upline limit hit
Cap
Withdrawal below 6x
Withdrawal reaching exactly 6x
Withdrawal exceeding 6x
Proportional scaling correctness
3. COMPOUNDING TESTS
Time
1 day
7 days
30 days
180 days
365 days
Packages
Single package
Multiple packages
Mixed active/inactive packages
Booster
Base ROI only
Base ROI + booster
Booster removed
Booster added mid-life
Edge
Huge timestamps
Tiny timestamps
Zero elapsed time
4. PACKAGE CAP TESTS
2.5x Package Cap
Exactly 2.5x
Slightly below
Slightly above
Multiple packages
State
Package deactivation
Active volume removal
Reinvestment after package cap
5. GLOBAL 6X CAP TESTS
Progression
1x
2x
5x
5.99x
6x
6.01x
Reinvestment
Capped user reinvests
Capped user uncaps
New package after cap
Rewards
Direct bonus near cap
Salary near cap
Level income near cap
Upline near cap
6. DIRECT BONUS TESTS
Generation
Single referral
Multiple referrals
Multiple deposits
Lock
Before 12h
Exactly 12h
After 12h
Cap
Direct bonus at cap
Direct bonus exceeding cap
Queue
1 pending bonus
100 pending bonuses
Large pending queue
7. LEVEL INCOME TESTS
Tree
1 level
2 levels
5 levels
40 levels
Qualification
Qualified upline
Unqualified upline
Mixed qualification
Accounting
Add volume
Remove volume
Package cap volume removal
Abuse
Reinvest loops
Cap/un-cap loops
Volume recycling
8. UPLINE INCOME TESTS
Eligibility
Deposit <1500
Deposit =1500
Deposit >1500
Directs
4 directs
5 directs
6 directs
Tracking
Upline ROI increase
Upline ROI decrease
Multiple uplines
9. BOOSTER TESTS
Qualification
1 qualifying direct
2 qualifying directs
3 qualifying directs
Time Window
Within 7 days
Exactly 7 days
After 7 days
Volume
Equal deposit
Lower deposit
Higher deposit
Abuse
Sybil accounts
Flash loan volume
Temporary volume
10. RANK TESTS
Qualification
Rank 1
Rank 2
...
Rank 10
40/60 Rule
Exactly 40/60
Strong leg too large
Weak leg insufficient
Fresh Business
Maintenance passed
Maintenance failed
Auto Rank
Auto rank on invest
Auto rank on withdraw
11. SALARY TESTS
Accrual
Daily
Weekly
Monthly
Maintenance
Maintained rank
Lost rank
Withdrawal
Partial
Full
Max salary limit
12. TOKEN CONTRACT TESTS
Buying Lock
Buy before unlock
Buy after unlock
Buy by system contract
Transfer Restrictions
Same block send
Same block receive
Contract transfer
EOA transfer
Whitelist
Whitelisted sender
Whitelisted receiver
Both whitelisted
Mint
System contract mint
Non-system mint
13. ORACLE TESTS
getSpotPrice()
Normal reserves
Tiny reserves
Huge reserves
Empty reserves
Manipulation
Pump price
Dump price
Flash loan reserve distortion
14. ATTACK SIMULATIONS
Flash Loan
Flash loan invest
Flash loan rank
Flash loan booster
Flash loan salary
Flash loan level rewards
Oracle Manipulation
Lower token price before withdraw
Raise token price before withdraw
Same block manipulation
Sandwich
Front-run withdraw
Back-run withdraw
Sybil
Hundreds of fake referrals
Rank farming
Reentrancy
invest()
withdraw()
claimRank()
DAO Compromise
Malicious router
Malicious pair
Malicious system contract
15. FUZZING TARGETS
invest()

Fuzz:

amount
referral tree depth
referral count
existing deposits
withdraw()

Fuzz:

timestamps
package counts
reward balances
rank system

Fuzz:

team structures
volumes
fresh business
compounding

Fuzz:

time elapsed
rate
booster
oracle

Fuzz:

reserves
reserve ratios
16. INVARIANT TESTS

These are the most important.

Accounting
User never exceeds 6x
Package never exceeds 2.5x
No negative balances
No underflows
No overflows
MLM
Direct count ≤ 200
Rank volume consistent
Team volume consistent
Token
Only system can mint
Buying disabled means buying disabled
Whitelist behaves correctly
Reward System
Rewards cannot appear from nowhere
Rewards cannot exceed caps
Capped users stop earning
17. GAS / DOS TESTS
Arrays
100 investments
200 directs
1000 depth tree
Worst Cases
Maximum pending bonuses
Maximum rank calculations
Maximum withdrawal loops
Measure
invest() gas
withdraw() gas
claimRank() gas