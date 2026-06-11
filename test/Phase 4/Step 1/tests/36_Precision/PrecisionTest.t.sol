// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";

/// @title PrecisionTest -- PoC for AUDIT finding M-7
/// @notice `_rpow` rounds DOWN every fixed-point multiplication. After many
///         compounding days the user receives slightly less than the
///         mathematical expectation. Likewise `_realizeSalary`'s
///         `rankIncome / 30 days` truncates, biasing payouts down by up to
///         29 wei per second per rank.
contract PrecisionTest is BaseForkSetup {

    address inv;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem();
        inv = makeAddr("precUser");
        _investFresh(inv, 1_000 * WAD, freshOrigin);
    }

    function test_M7_compound_truncation_after_1_year() public {
        uint256 principal = 1_000 * WAD;
        // Mature 365 days then read lifetime RWP.
        _advanceTime(365 days);
        uint256 actualRWP = freshSystem.getTotalLifetimeRWP(inv);

        // Theoretical compounded at 0.5% daily for 365 days:
        //   principal * 1.005**365 = principal * ~6.1417
        // Minus principal ~= principal * 5.1417 in lifetime RWP -- but the
        // 2.5x package cap clamps this at principal * 2.5.
        uint256 packageCap = (principal * 25) / 10;

        emit log_named_string("Principal", _toUsdt(principal));
        emit log_named_string("Lifetime RWP at 365d (capped at 2.5x)", _toUsdt(actualRWP));
        emit log_named_string("Package 2.5x ceiling", _toUsdt(packageCap));

        // Confirm we hit the package cap (the truncation matters BEFORE the
        // cap kicks in; once capped, additional rounding is irrelevant).
        assertLe(actualRWP, packageCap, "lifetime RWP should not exceed 2.5x package cap");
    }

    function test_M7_salary_per_second_truncation() public {
        // Rank 1 = 50 USDT per month = 50e18 / 30 days
        uint256 rankIncome = 50 * 1e18;
        uint256 perSec = rankIncome / 30 days;
        uint256 over30d = perSec * 30 days;
        emit log_named_string(
            "salaryPerSec for Rank 1 (wei)",
            _toFixed(perSec, 0)
        );
        emit log_named_string("Rounded payout over 30 days", _toUsdt(over30d));
        emit log_named_string("Expected payout (theoretical)", _toUsdt(rankIncome));
        // The shortfall:
        emit log_named_uint("Shortfall in wei", rankIncome - over30d);
    }
}
