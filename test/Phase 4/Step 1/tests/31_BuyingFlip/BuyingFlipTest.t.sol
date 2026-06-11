// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title BuyingFlipTest -- PoC for AUDIT finding H-4
/// @notice The token's `enableBuying()` has a 180-day lock from deploy but
///         is otherwise REVERSIBLE -- the DAO can call `disableBuying()` and
///         `enableBuying()` freely after the lock expires. The
///         "buying-off-forever" policy from agents.md rests entirely on DAO
///         honesty, with no on-chain enforcement.
contract BuyingFlipTest is BaseForkSetup {

    function test_H4_buyingEnabled_currently_false_but_unlock_pending() public {
        assertEq(token.buyingEnabled(), false, "live state: buyingEnabled=false");
        uint256 timeLeft = token.timeUntilBuyUnlock();
        emit log_named_uint("timeUntilBuyUnlock (seconds)", timeLeft);
        emit log_named_string(
            "Once unlocked, can DAO enable buying?",
            "YES -- enableBuying() has no other guard"
        );
    }

    function test_H4_dao_can_enable_then_disable_then_re_enable() public {
        address dao = token.DAOMultisigController();
        // Warp past the 180-day lock relative to deployTime.
        uint256 unlockTime = token.deployTime() + 180 days;
        if (block.timestamp < unlockTime) {
            vm.warp(unlockTime + 1);
        }

        vm.prank(dao);
        token.enableBuying();
        assertEq(token.buyingEnabled(), true, "DAO can enable");
        emit log_named_string("DAO call enableBuying()", "OK");

        vm.prank(dao);
        token.disableBuying();
        assertEq(token.buyingEnabled(), false, "DAO can disable again");
        emit log_named_string("DAO call disableBuying()", "OK");

        vm.prank(dao);
        token.enableBuying();
        assertEq(token.buyingEnabled(), true, "DAO can re-enable");
        emit log_named_string(
            "Flip count tested",
            "3 -- enable/disable/enable all succeeded"
        );
    }

    function test_H4_no_lock_buying_forever_function_exists() public {
        (bool ok, ) = TOKEN.staticcall(abi.encodeWithSignature("lockBuyingForever()"));
        emit log_named_string(
            "Does token expose lockBuyingForever()?",
            ok ? "YES" : "NO -- forever-off policy is off-chain trust only"
        );
        assertEq(ok, false, "PoC: no on-chain irrevocable buying-off flag");
    }
}
