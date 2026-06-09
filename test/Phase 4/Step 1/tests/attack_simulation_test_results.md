# attack simulation test results

date: 2026-06-08, forge 0.2.0, all 4 tests passed

## flash loan direct blocks

1. flash loan invest: direct investments by a flash loan contract are blocked (reverts with Err_NoContractCallsAllowed since tx.origin != msg.sender)
2. flash loan rank: rank claims or updates called by a smart contract are blocked (reverts with Err_NoActiveDirects or Err_NoContractCallsAllowed because contract addresses cannot establish direct downline referrers)
3. flash loan booster: booster status activation attempts by contract addresses are blocked (reverts with Err_NoContractCallsAllowed since contract accounts cannot hold active packages or recruit downlines)

## flash loan oracle exploit

4. flash loan eoa oracle exploit: demonstrates a successful two-step oracle manipulation exploit using a contract and a cooperating EOA. first, a flash loan contract swaps heavily on the Uniswap pair, crashing the project token price (e.g. from 1.14 USDT to 0.01 USDT). second, the attacker's EOA calls withdraw() in the same block, which is allowed by the tx.origin check. due to the distorted spot price, the EOA receives heavily inflated project tokens (3,689 tokens instead of 33.5 tokens). finally, the EOA transfers the tokens to the contract to pay back the flash loan and realize a risk-free profit.

## observations

- while the system contract's strict tx.origin == msg.sender verification successfully blocks direct smart contract reentrancy and direct flash loan interactions (invest/withdraw calls), it is entirely bypassed when a flash loan contract manipulates the external Uniswap pair's reserves and a cooperating EOA acts as the execution agent.
- this exploit allows an attacker to drain the project token's mintable supply by inflating withdrawal amounts without violating any of the system contract's internal access control parameters.
