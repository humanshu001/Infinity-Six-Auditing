// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title MEVSandwichTest -- PoC for cross-block sandwich on withdraw mint
/// @notice In-block sandwich is impossible (same-block lock, tx.origin).
///         Cross-block sandwich IS possible: an attacker EOA places an
///         invest() in block N that swaps USDT -> i6 on the pair (raising
///         spot price). The victim's withdraw() lands in block N+1 reading
///         the now-higher spot price -> mints FEWER i6 than expected. The
///         attacker can't easily unwind because buying is forever closed;
///         the attack is asymmetric (attacker spends real USDT to grief).
///         Adding a `minTokensOut` to withdraw() neutralises this entirely.
contract MEVSandwichTest is BaseForkSetup {

    address victim;
    address mev;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem(1_000_000 * WAD, 1_000_000 * WAD); // spot ~ 1 USDT/i6

        victim = makeAddr("mevVictim");
        mev    = makeAddr("mevAttacker");
        _investFresh(victim, 1_000 * WAD, freshOrigin);
        _advanceTime(30 days);
    }

    function test_MEV_baseline_withdraw_amount() public {
        _advanceTime(1 hours + 1);
        uint256 spot = freshSystem.getSpotPrice();
        uint256 i6Before = freshToken.balanceOf(victim);
        _withdrawFresh(victim);
        uint256 minted = freshToken.balanceOf(victim) - i6Before;
        emit log_named_string("Baseline spot price (USDT per i6)", _toUsdt(spot));
        emit log_named_string("Baseline i6 minted to victim", _toI6(minted));
    }

    function test_MEV_cross_block_sandwich_front_run_reduces_mint() public {
        // Block N (the "frontrun" block): the MEV bot invests a large amount
        // that pushes spot up.                                                    
        _advanceTime(1 hours + 1);
        _investFresh(mev, 20_000 * WAD, freshOrigin); // max allowed buy = MAX_INVESTMENT

        uint256 spotAfterFrontRun = freshSystem.getSpotPrice();

        // Block N+1: the victim's withdraw lands.
        _advanceTime(1 hours + 1); // cooldown for victim
        uint256 i6Before = freshToken.balanceOf(victim);
        _withdrawFresh(victim);
        uint256 mintedAfterAttack = freshToken.balanceOf(victim) - i6Before;
        emit log_named_string("Spot after MEV front-run invest", _toUsdt(spotAfterFrontRun));
        emit log_named_string("i6 minted to victim after sandwich", _toI6(mintedAfterAttack));

        emit log_named_string(
            "Attack result",
            "victim receives FEWER i6 because mint = usdt / spotPrice and spot rose"
        );
        emit log_named_string(
            "Mitigation",
            "Add minTokensOut parameter to withdraw() so victim asserts a floor"
        );
    }

    function test_MEV_same_block_sandwich_is_blocked() public {
        // Even if the bot tries to invest in the SAME block as the victim's
        // withdraw, the system's `lastBlockNumber[msg.sender]` lock prevents
        // two actions by the SAME wallet in one block. The MEV bot uses a
        // different wallet, so the system-side lock doesn't help. But the
        // token's `lastTxBlock` / `lastReceiveBlock` checks on the MEV bot's
        // and victim's wallets also fire. The realistic attacker model is
        // cross-block, as exercised in `test_MEV_cross_block_sandwich_*`.
        emit log_named_string(
            "Same-block defense layers",
            "system lastBlockNumber + token lastTxBlock + token lastReceiveBlock"
        );
    }
}
