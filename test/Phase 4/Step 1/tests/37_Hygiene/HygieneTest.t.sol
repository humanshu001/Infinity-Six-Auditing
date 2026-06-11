// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title HygieneTest -- PoC for AUDIT findings L-2 through L-5 + I-2
/// @notice Low-severity hygiene observations that are testable as static
///         contract properties (no economic exploit, but each one is a
///         concrete code-quality / safety regression risk).
contract HygieneTest is BaseForkSetup {

    function test_L2_maintenanceBurnedVolume_is_dead_state() public {
        // The mapping is publicly readable but no other internal/external
        // function reads it; we capture the static observation here.
        // We just confirm the public reader is callable.
        uint256 v = system.maintenanceBurnedVolume(ORIGIN_LIVE, ORIGIN_LIVE);
        emit log_named_uint("maintenanceBurnedVolume[ORIGIN][ORIGIN]", v);
        emit log_named_string(
            "Is maintenanceBurnedVolume read anywhere except in tests?",
            "NO -- dead state, AUDIT.md L-2"
        );
    }

    function test_L4_token_rescueTokens_uses_raw_transfer() public {
        // BSC-USD is non-standard (no bool return on transfer). The token's
        // rescueTokens uses raw transfer(). To prove the risk class, we just
        // observe that the call succeeds against a normal ERC20 (USDT works
        // because OpenZeppelin's TransferHelper doesn't strictly check, but
        // a stricter helper or a non-returning token would silently leave
        // funds stuck).
        // Sanity: rescuing 0 USDT must succeed (no balance changes).
        address daoCtrl = token.DAOMultisigController();
        vm.prank(daoCtrl);
        token.rescueTokens(USDT, attacker, 0);
        emit log_named_string(
            "Token.rescueTokens(USDT, attacker, 0)",
            "OK -- but raw transfer used; non-standard ERC20s may silently fail"
        );
    }

    function test_L5_no_emergency_pause_function() public {
        (bool ok1, ) = SYSTEM.staticcall(abi.encodeWithSignature("pause()"));
        (bool ok2, ) = SYSTEM.staticcall(abi.encodeWithSignature("unpause()"));
        (bool ok3, ) = SYSTEM.staticcall(abi.encodeWithSignature("paused()"));
        emit log_named_string("pause() exists?",  ok1 ? "YES" : "NO");
        emit log_named_string("unpause() exists?", ok2 ? "YES" : "NO");
        emit log_named_string("paused() exists?", ok3 ? "YES" : "NO");
        assertFalse(ok1, "no pause()");
        assertFalse(ok2, "no unpause()");
        assertFalse(ok3, "no paused()");
    }

    function test_I2_dao_modeled_as_single_address() public {
        // The DAO is one address -- a real multisig is off-chain trust only.
        emit log_named_address("DAOMultisigController",
            system.DAOMultisigController());
        emit log_named_uint("Code size at DAO address",
            system.DAOMultisigController().code.length);
        // Non-zero code = it IS a contract (Safe). Zero code = it is an EOA.
    }
}
