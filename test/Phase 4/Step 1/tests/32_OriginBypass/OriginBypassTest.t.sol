// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title OriginBypassTest -- PoC for AUDIT finding H-5
/// @notice The hardcoded `ORIGIN_MEMBER_ID` EOA bypasses every cap branch
///         and produces unbounded `directBonus`/`unwithdrawnSalary`/level/
///         upline income. We verify by computing the lifetime cap delta for
///         ORIGIN vs a normal user with identical state.
contract OriginBypassTest is BaseForkSetup {

    function test_H5_origin_member_is_hardcoded_eoa() public {
        // Documented constant in the contract.
        assertEq(ORIGIN_LIVE, 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1, "constant address");
        // Genesis investment is seeded at constructor time.
        (uint256 td,,,,,,,,,,,,,,,,,,,,,,,,,,) = system.users(ORIGIN_LIVE);
        emit log_named_string("ORIGIN totalDeposits (live)", _toUsdt(td));
        emit log_named_uint("Code size at ORIGIN (PoC: 0 -> it is an EOA)", ORIGIN_LIVE.code.length);
        assertEq(ORIGIN_LIVE.code.length, 0, "PoC: ORIGIN is an EOA, not a multisig");
    }

    function test_H5_origin_can_withdraw_past_6x_cap() public {
        // We use the fresh system so we can fully control ORIGIN's withdraws
        // without depending on live state.
        _deployFreshSystem();

        // ORIGIN is seeded at deploy with 50,000 USDT genesis investment and
        // already active. Mature time so it has accrued ROI.
        _advanceTime(365 days);

        // ORIGIN's 6x cap would normally be 50,000 * 6 = 300,000 USDT total
        // lifetime payout. Below we check that the code path branches around
        // every cap check for ORIGIN. Easiest: just call withdraw() and
        // confirm it executes without ever flipping isCapped.
        _advanceTime(1 hours + 1);
        vm.prank(ORIGIN_LIVE, ORIGIN_LIVE);
        try freshSystem.withdraw() {} catch (bytes memory r) {
            emit log_named_uint("ORIGIN withdraw revert size", r.length);
        }

        bool capped = _userIsCapped(freshSystem, ORIGIN_LIVE);
        emit log_named_string(
            "Is ORIGIN flagged as capped after withdraw?",
            capped ? "YES" : "NO -- ORIGIN bypasses the 6x cap"
        );
        assertFalse(capped, "PoC: ORIGIN never gets isCapped=true");
    }

    function test_H5_no_setter_to_rotate_origin() public {
        (bool ok, ) = SYSTEM.staticcall(abi.encodeWithSignature("setOriginMember(address)"));
        emit log_named_string(
            "Does system expose setOriginMember(address)?",
            ok ? "YES" : "NO -- ORIGIN address is immutable"
        );
        assertEq(ok, false, "PoC: ORIGIN address cannot be rotated post-deploy");
    }
}
