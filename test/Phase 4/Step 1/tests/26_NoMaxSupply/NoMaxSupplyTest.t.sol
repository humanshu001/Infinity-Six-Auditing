// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title NoMaxSupplyTest -- PoC for AUDIT finding C-2
/// @notice The i6 token has NO max-supply cap. `mint()` is callable by the
///         system contract with any `amount`. Combined with C-1 (spot-price
///         mint with no slippage guard), this enables runaway inflation when
///         pool reserves are depleted.
contract NoMaxSupplyTest is BaseForkSetup {

    function test_C2_token_has_no_max_supply_constant() public {
        // No `MAX_SUPPLY()` getter exists on the deployed token. We probe by
        // calling the selector and checking the call reverts (function not
        // present).
        (bool ok, ) = TOKEN.staticcall(abi.encodeWithSignature("MAX_SUPPLY()"));
        emit log_named_string("Does i6 expose MAX_SUPPLY()?", ok ? "YES" : "NO");
        assertEq(ok, false, "PoC: token does NOT expose any MAX_SUPPLY cap");
    }

    function test_C2_system_can_mint_arbitrary_amount() public {
        // Roleplay the system contract calling mint(). We prank as
        // `token.systemContract()` (live system) so the access check passes.
        address sys = token.systemContract();
        uint256 supplyBefore = token.totalSupply();

        uint256 huge = 1_000_000_000_000 * WAD; // 1 trillion i6
        vm.prank(sys);
        token.mint(attacker, huge);

        uint256 supplyAfter = token.totalSupply();
        emit log_named_string("Supply before mint", _toI6(supplyBefore));
        emit log_named_string("Supply after  mint", _toI6(supplyAfter));
        emit log_named_string("Newly minted to attacker", _toI6(supplyAfter - supplyBefore));

        assertEq(supplyAfter - supplyBefore, huge,
            "PoC: system contract minted 1 TRILLION i6 in one call -- no cap fired");
    }
}
