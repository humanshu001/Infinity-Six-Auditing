# token test results

date: 2026-06-08, forge 0.2.0, all 12 tests passed

## buying lock

1. buy before unlock: direct purchases from the liquidity pool (transfer from liquidityPair to Alice) before buying is enabled revert with Err_BuyingRestricted
2. buy after unlock: enabling buying succeeds via DAO signature after 180 days, allowing successful purchases from the liquidity pool
3. buy by system contract: the system contract is whitelisted to bypass the buy lock, enabling it to pull liquidity or receive tokens from the liquidity pool even when general buying is disabled

## transfer restrictions

4. same block send: non-whitelisted addresses are restricted to one send operation per block (Alice sending twice in the same block reverts with Err_SameBlockTransferNotAllowed)
5. same block receive: non-whitelisted addresses are restricted to receiving once per block (Charlie sending to Bob in the same block where Alice already sent to Bob reverts with Err_CooldownActive)
6. contract transfer: contract interactions by non-whitelisted contracts are blocked (non-whitelisted receiver contract forwarding tokens reverts with Err_NoContractCallsAllowed since tx.origin != msg.sender)
7. eoa transfer: normal EOA to EOA transfers succeed when executed across separate blocks

## whitelist

8. whitelisted sender: whitelisted senders bypass the single-send per block restriction (Alice can send to multiple recipients in the same block)
9. whitelisted receiver: whitelisted receivers bypass the single-receive per block restriction (multiple senders can transfer to Bob in the same block)

## mint

10. system contract mint: the system contract can successfully mint new tokens via mint()
11. non-system mint: any other address attempting to call mint() reverts with Err_NotSystemContract

## observations

- the anti-bot mechanisms (same-block send/receive restrictions) rely entirely on mapping the caller's last interaction block. while highly effective against flash bots and sandwich attacks, it increases gas costs by performing multiple storage writes per transfer.
- the contract call restriction (tx.origin == msg.sender) blocks multisig wallets and smart contract accounts from interacting with the token unless they are explicitly whitelisted. this should be carefully managed during launch.
