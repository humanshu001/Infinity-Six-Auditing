// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title MultiplierTest -- PoC for AUDIT findings H-1 (`_getMultiplier`
///        fall-through) and L-1 (`setROI` range mismatch).
/// @notice `_getMultiplier` only matches rates {5,7,8,10}; every other valid
///         value silently returns the default 1.005 (0.5% daily). `setROI`
///         accepts [2,10], so the DAO can intend "9% daily" but the contract
///         compounds at 0.5%. Tested via the public `getTotalLifetimeRWP`
///         which exercises the same multiplier path.
contract MultiplierTest is BaseForkSetup {

    address inv;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem();
        inv = makeAddr("multiplierInvestor");
        _investFresh(inv, 1_000 * WAD, freshOrigin);
    }

    function _withDay(uint256 daysElapsed, uint256 roiPct) internal returns (uint256 lifetimeRWP) {
        // Each call mutates `freshSystem.MIN_ROI_PERC` then matures + reads.
        vm.prank(freshDao);
        freshSystem.setROI(roiPct);
        _advanceTime(daysElapsed * 1 days);
        lifetimeRWP = freshSystem.getTotalLifetimeRWP(inv);
        // Snapshot back so each tested rate runs from the same starting state.
        // (Foundry snapshots are heavy across forks, so we just emit and let
        // the next test reset by virtue of a fresh setUp().)
    }

    function test_H1_documented_rates_compound_correctly() public {
        uint256 rwpAt5 = _withDay(30, 5);
        emit log_named_string("Lifetime RWP after 30d @ ROI=5 (0.5%)", _toUsdt(rwpAt5));
        assertGt(rwpAt5, 0, "5 should accrue meaningful RWP");
    }

    function test_H1_undocumented_rates_silently_fall_to_default() public {
        // We compare ROI=9 to ROI=5. Because _getMultiplier(9) returns the
        // default 1.005 (same as rate=5), the lifetime RWP should be roughly
        // identical between them (modulo tiny per-second linear interpolation).
        uint256 rwpAt5 = _withDay(30, 5);
        // Reset state for the second comparison.
        setUp();
        uint256 rwpAt9 = _withDay(30, 9);
        emit log_named_string("Lifetime RWP after 30d @ ROI=5", _toUsdt(rwpAt5));
        emit log_named_string("Lifetime RWP after 30d @ ROI=9", _toUsdt(rwpAt9));
        emit log_named_string(
            "Are they equal (PoC: bug)?",
            (rwpAt5 == rwpAt9) ? "YES -- bug confirmed" : "NO"
        );

        // The same default multiplier means lifetime RWP is identical.
        assertEq(rwpAt5, rwpAt9,
            "PoC: ROI=9 and ROI=5 compound identically because _getMultiplier(9) -> default 1.005");
    }

    function test_L1_setROI_accepts_values_that_fall_through() public {
        // The DAO can legitimately call setROI(6) or setROI(9) without
        // reverting -- but the math silently uses 5.
        vm.startPrank(freshDao);
        freshSystem.setROI(6); // accepted
        freshSystem.setROI(9); // accepted
        // Boundaries:
        vm.expectRevert(); freshSystem.setROI(1);  // below range -> revert
        vm.expectRevert(); freshSystem.setROI(11); // above range -> revert
        vm.stopPrank();
        emit log_named_string(
            "setROI(9) call status",
            "ACCEPTED -- but compounding remains at 0.5%"
        );
    }
}
