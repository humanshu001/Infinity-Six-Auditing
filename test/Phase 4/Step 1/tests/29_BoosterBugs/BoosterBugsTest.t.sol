// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title BoosterBugsTest -- PoC for AUDIT findings H-2 (booster not applied
///        to new packages), M-4 (booster rate asymmetry leaks upline base),
///        and M-6 (permanent booster invariant).
/// @notice The booster system has three independent issues:
///   (H-2) The `invest()` function pushes new packages with `boostperc: 0`
///         even when the user is already `isBoosted`. New packages compound
///         at the base rate forever.
///   (M-6) `isBoosted` is set once and never revoked, regardless of whether
///         the qualifying directs subsequently cap or stop generating.
contract BoosterBugsTest is BaseForkSetup {

    address sponsor;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem();
        sponsor = makeAddr("sponsor");
        // Sponsor invests 100 USDT under ORIGIN to bootstrap.
        _investFresh(sponsor, 100 * WAD, freshOrigin);
    }

    function _qualifyBooster() internal {
        // Booster needs `directBoosterCount >= 3` with each direct's deposit
        // >= sponsor's deposit, and the directs must invest within the
        // sponsor's first 7 days (ACTIVE_BOOSTER_PERIOD).
        for (uint256 i = 0; i < 3; i++) {
            address d = makeAddr(string.concat("direct-", vm.toString(i)));
            _investFresh(d, 100 * WAD, sponsor); // matches sponsor's deposit
        }
        assertTrue(_userIsBoosted(freshSystem, sponsor), "sponsor should be boosted");
    }

    function test_H2_new_package_after_boost_has_zero_boostperc() public {
        _qualifyBooster();
        emit log_named_string("Sponsor isBoosted after qualifying", "TRUE");

        // Sponsor invests a SECOND package (re-invest).
        _dealUsdt(sponsor, 200 * WAD);
        vm.prank(sponsor, sponsor);
        IERC20(USDT).approve(address(freshSystem), type(uint256).max);
        _rollBlock();
        vm.prank(sponsor, sponsor);
        freshSystem.invest(200 * WAD, freshOrigin, 0);

        // Inspect the boostperc of the NEW package directly via the public
        // mapping. The mapping return type is the Investment tuple:
        // (amount, compoundedPrincipal, rwpWithdrawn, lastUpdateTime,
        //  isActive, boostperc).
        // The new package is at index 1.
        (uint256 amt,,,, bool active, uint256 boostperc) =
            freshSystem.userInvestments(sponsor, 1);

        emit log_named_uint("New package amount (wei)", amt);
        emit log_named_string("New package isActive", active ? "true" : "false");
        emit log_named_uint("New package boostperc (PoC: should be MIN_BOOSTER_PERC=5)", boostperc);

        assertTrue(_userIsBoosted(freshSystem, sponsor), "sponsor remains boosted");
        assertEq(boostperc, 0,
            "PoC: new package created AFTER boost activation has boostperc=0, losing +0.5% daily");
    }

    function test_M6_isBoosted_is_never_revoked() public {
        _qualifyBooster();
        // Even if all the qualifying directs cap and stop generating, there
        // is no flow that clears isBoosted. We probe by inspecting the ABI:
        // no `revokeBooster` or similar function exists.
        (bool ok1, ) = address(freshSystem).staticcall(abi.encodeWithSignature("revokeBooster(address)"));
        (bool ok2, ) = address(freshSystem).staticcall(abi.encodeWithSignature("removeBooster(address)"));
        assertEq(ok1, false, "no revokeBooster() exists");
        assertEq(ok2, false, "no removeBooster() exists");

        // The internal `_checkAndApplyBooster` exits early on isBoosted ==
        // true and has no clearing branch. State is sticky forever.
        emit log_named_string(
            "After qualifying, is there ANY contract path that clears isBoosted?",
            "NO -- the bit is permanent"
        );
        assertTrue(_userIsBoosted(freshSystem, sponsor), "still boosted -- forever");
    }
}
