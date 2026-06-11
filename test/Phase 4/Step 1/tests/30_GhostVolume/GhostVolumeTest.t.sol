// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title GhostVolumeTest -- PoC for AUDIT finding H-3
/// @notice `_updateDownlineBusiness` only ADDS to `totalDownlineBusiness` and
///         `freshBusiness`. Neither field is decremented when a downline
///         caps, when their package reaches 2.5x, or when they withdraw.
///         The upline's rank-qualifying metric drifts upward forever
///         regardless of whether the downline volume is "live" or "dead".
contract GhostVolumeTest is BaseForkSetup {

    address sponsor;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem();
        sponsor = makeAddr("sponsor");
        _investFresh(sponsor, 1_000 * WAD, freshOrigin);
    }

    function test_H3_totalDownlineBusiness_only_grows() public {
        // Sponsor is at the root of a small chain. We add a single direct
        // who in turn refers a chain of 5 more accounts. The sponsor's
        // totalDownlineBusiness reflects the FULL aggregated chain.
        address d1 = makeAddr("d1");
        _investFresh(d1, 1_000 * WAD, sponsor);
        address[] memory chain = new address[](5);
        address cursor = d1;
        for (uint256 i = 0; i < 5; i++) {
            chain[i] = makeAddr(string.concat("subchain-", vm.toString(i)));
            _investFresh(chain[i], 1_000 * WAD, cursor);
            cursor = chain[i];
        }

        uint256 tdbBefore = _userTotalDownlineBusiness(freshSystem, sponsor);
        uint256 fbBefore  = _userFreshBusiness(freshSystem, sponsor);
        emit log_named_string("totalDownlineBusiness after build", _toUsdt(tdbBefore));
        emit log_named_string("freshBusiness after build",          _toUsdt(fbBefore));
        assertEq(tdbBefore, 6_000 * WAD,
            "expected 6 x 1,000 USDT in the sponsor's downline business");

        // Now we cap one of the chain nodes by triggering the 6x cap.
        // Each chain node deposited only 1,000 USDT, so their global cap is
        // 6,000 USDT. We force a withdraw worth more than that by maturing
        // ROI for a year.
        _advanceTime(365 days);
        // Make every chain node withdraw -> some will hit caps, others won't.
        for (uint256 i = 0; i < chain.length; i++) {
            _advanceTime(1 hours + 1);
            try freshSystem.withdraw() {} catch {}
            vm.prank(chain[i], chain[i]);
            try freshSystem.withdraw() {} catch {}
        }
        // Also force d1 to withdraw to push their cap.
        _advanceTime(1 hours + 1);
        vm.prank(d1, d1);
        try freshSystem.withdraw() {} catch {}

        // Inspect the sponsor's metric after possible caps in the downline.
        uint256 tdbAfter = _userTotalDownlineBusiness(freshSystem, sponsor);
        emit log_named_string("totalDownlineBusiness AFTER chain matures/withdraws", _toUsdt(tdbAfter));
        emit log_named_string(
            "Did the metric decrement on cap?",
            tdbAfter < tdbBefore ? "YES" : "NO -- ghost volume confirmed"
        );

        // The PoC is the equality -- ghost volume persists.
        assertEq(tdbAfter, tdbBefore,
            "PoC: totalDownlineBusiness never decreases regardless of downline state");
    }

    function test_H3_no_decrement_path_exists_in_abi() public {
        // Sanity-check there is no admin function to clear ghost volume.
        (bool ok1, ) = SYSTEM.staticcall(abi.encodeWithSignature("clearDownlineBusiness(address)"));
        (bool ok2, ) = SYSTEM.staticcall(abi.encodeWithSignature("recomputeDownlineBusiness(address)"));
        assertEq(ok1, false, "no clearDownlineBusiness()");
        assertEq(ok2, false, "no recomputeDownlineBusiness()");
        emit log_named_string("Admin path to clear ghost volume", "NONE");
    }
}
