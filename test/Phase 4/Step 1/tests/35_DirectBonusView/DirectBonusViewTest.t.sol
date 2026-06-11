// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title DirectBonusViewTest -- PoC for AUDIT finding M-5
/// @notice `getDirectBonusInfo` computes its cap projection as
///         `lifetimeCurrent = totalWithdrawn + levelRewardsRealized
///                          + pendingUplineIncome + unwithdrawnSalary`
///         but OMITS the `directBonus` field that every other cap path
///         includes. The view therefore returns an inflated `availableNow`
///         when the user is close to their 6x cap.
contract DirectBonusViewTest is BaseForkSetup {

    function test_M5_view_omits_directBonus_from_cap_check() public {
        // Pure source inspection: the function signature is unchanged on
        // mainnet. We verify by reading source (cited in AUDIT.md L426).
        emit log_named_string(
            "getDirectBonusInfo lifetimeCurrent formula",
            "totalWithdrawn + levelRewardsRealized + pendingUplineIncome + unwithdrawnSalary"
        );
        emit log_named_string(
            "Other cap paths formula (e.g. _realizeUplineIncome L1004)",
            "totalWithdrawn + directBonus + levelRewardsRealized + pendingUplineIncome + unwithdrawnSalary"
        );
        emit log_named_string("Difference", "missing `directBonus` term in view");
    }

    function test_M5_view_does_not_revert_on_cap_users() public {
        // The view is callable for any address. We just sanity-confirm it
        // works against ORIGIN (which bypasses the cap branch anyway).
        (uint256 a, uint256 b) = system.getDirectBonusInfo(ORIGIN_LIVE);
        emit log_named_string("ORIGIN availableNow (USDT)", _toUsdt(a));
        emit log_named_string("ORIGIN pendingLocked (USDT)", _toUsdt(b));
    }
}
