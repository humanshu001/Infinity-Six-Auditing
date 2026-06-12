// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import {PriceDynamicsHarness} from "./Price.t.sol";

/// @title C2 - Invest / Withdraw Ratio Sweep (death-spiral tipping point)
/// @notice Parametrises "for every X invests there are Y withdraws" and sweeps
///         the Y/X ratio to find the critical point where the i6 spot price
///         stops recovering and enters a monotonic decline (the death spiral).
///
/// Run on a BSC fork:
///   forge test --match-path "*19_PriceDynamics/C2_RatioSweep.t.sol*" -vv
///
/// Output: grep "CSV|" out.log to plot round -> price / reserves, exactly like
/// the gas_plots.png produced for the 18_DoS suite. A "ratio -> finalPrice"
/// summary table is emitted at the end of test_C2_ratio_sweep.
contract C2_RatioSweep is PriceDynamicsHarness {
    // Pool seeded so spot matches the documented live getSpotPrice value.
    uint256 constant LIVE_SPOT_PRICE = 1262533071561801545;
    uint256 constant SEED_I6 = 1_000_000 * 1e18;
    uint256 constant SEED_USDT = (SEED_I6 * LIVE_SPOT_PRICE) / 1e18;

    uint256 constant INVEST_SIZE = 1_000 * 1e18; // $1k per invest action
    uint256 constant ROUNDS = 40; // rounds per ratio scenario
    uint256 constant MATURE = 3 days + 7 days; // launch gate + ROI accrual

    function setUp() public {
        _forkAndDeploy(SEED_USDT, SEED_I6);
        // Move past the 3-day withdrawal launch gate up front.
        _advanceTime(3 days + 1);
    }

    /// @dev Runs one scenario at a fixed withdraws-per-invest ratio (in tenths,
    ///      e.g. ratioTenths=15 => 1.5 withdraws per invest) and returns the
    ///      final spot price after ROUNDS.
    function _runScenario(uint256 ratioTenths, uint256 saltBase)
        internal
        returns (uint256 startPrice, uint256 finalPrice)
    {
        startPrice = _spotPrice();
        emit log_named_uint("=== scenario ratioTenths (withdraws*10 per invest)", ratioTenths);
        _csvRow(0);

        // Pool of participants who first invest (so they have a position to
        // withdraw against later). They all sponsor under ORIGIN (active).
        uint256 withdrawCursor = 0;
        address[] memory parked = new address[](ROUNDS + 5);
        uint256 parkedCount;

        for (uint256 round = 1; round <= ROUNDS; round++) {
            // --- invests for this round (always 1 invest baseline) ---
            address inv = _newUser(saltBase + round);
            _fundAndApprove(inv, INVEST_SIZE * 2);
            _invest(inv, INVEST_SIZE, ORIGIN);
            parked[parkedCount++] = inv;

            // --- withdraws for this round, scaled by the ratio ---
            uint256 withdrawsThisRound = ratioTenths / 10;
            uint256 fractional = ratioTenths % 10; // probabilistic extra withdraw
            if ((round * fractional) % 10 < fractional) {
                withdrawsThisRound += 1;
            }

            for (uint256 w = 0; w < withdrawsThisRound && withdrawCursor < parkedCount; w++) {
                address victim = parked[withdrawCursor++];
                // Let ROI mature and respect the 1h cooldown.
                _advanceTime(MATURE);
                _withdrawAndSell(victim);
            }

            _csvRow(round);
        }

        finalPrice = _spotPrice();
        _logState("scenario-end", ratioTenths);
    }

    function _runScenarioWithPrices(uint256 ratioTenths, uint256 saltBase)
        internal
        returns (uint256 startPrice, uint256 finalPrice, uint256[] memory prices)
    {
        prices = new uint256[](ROUNDS + 1);
        startPrice = _spotPrice();
        prices[0] = startPrice;
        emit log_named_uint("=== scenario ratioTenths (withdraws*10 per invest)", ratioTenths);
        _csvRow(0);

        uint256 withdrawCursor = 0;
        address[] memory parked = new address[](ROUNDS + 5);
        uint256 parkedCount;

        for (uint256 round = 1; round <= ROUNDS; round++) {
            address inv = _newUser(saltBase + round);
            _fundAndApprove(inv, INVEST_SIZE * 2);
            _invest(inv, INVEST_SIZE, ORIGIN);
            parked[parkedCount++] = inv;

            uint256 withdrawsThisRound = ratioTenths / 10;
            uint256 fractional = ratioTenths % 10;
            if ((round * fractional) % 10 < fractional) {
                withdrawsThisRound += 1;
            }

            for (uint256 w = 0; w < withdrawsThisRound && withdrawCursor < parkedCount; w++) {
                address victim = parked[withdrawCursor++];
                _advanceTime(MATURE);
                _withdrawAndSell(victim);
            }

            prices[round] = _spotPrice();
            _csvRow(round);
        }

        finalPrice = prices[ROUNDS];
        _logState("scenario-end", ratioTenths);
    }

    /// @dev external wrapper so the per-victim withdraw can be try/caught.
    function externalWithdrawAndSell(address user) external {
        require(msg.sender == address(this), "only self");
        _withdrawAndSell(user);
    }

    function test_C2_ratio_sweep() public {
        // Sweep withdraws-per-invest from 0.1x up to 5.0x.
        uint256[10] memory ratiosTenths = [uint256(1), 5, 8, 10, 12, 15, 20, 30, 40, 50];

        uint256[10] memory finals;
        uint256 start;

        for (uint256 i = 0; i < ratiosTenths.length; i++) {
            // Fresh pool per scenario for clean comparison.
            _forkAndDeploy(SEED_USDT, SEED_I6);
            _advanceTime(3 days + 1);
            totalUsdDepositedIn = 0;
            totalUsdRealizedOut = 0;

            (uint256 s, uint256 f) = _runScenario(ratiosTenths[i], 0x10000 * (i + 1));
            start = s;
            finals[i] = f;
        }

        // Summary table: ratio -> final price (grep "RATIO|").
        emit log_string("========== C2 SUMMARY: ratio -> finalPrice ==========");
        emit log_named_uint("startPrice (all scenarios)", start);
        for (uint256 i = 0; i < ratiosTenths.length; i++) {
            emit log_string(
                string(
                    abi.encodePacked(
                        "RATIO|",
                        vm.toString(ratiosTenths[i]),
                        "|finalPrice|",
                        vm.toString(finals[i])
                    )
                )
            );
        }

        // Invariant checks that hold regardless of the live pool state:
        // 1. A withdraw-heavy regime must end below an invest-heavy regime.
        assertLt(
            finals[ratiosTenths.length - 1], // 5.0x withdraws
            finals[0], // 0.1x withdraws
            "heavy-withdraw regime should end at a lower price than invest-heavy"
        );
        // 2. Price must be strictly positive (pool never fully drained to 0).
        assertGt(finals[ratiosTenths.length - 1], 0, "pool price collapsed to zero");
    }

    /// @notice Focused 2x withdraw/invest run under current documented values.
    ///         With the present mechanics, 2x is not enough to force a spiral.
    function test_C2_price_recovers_at_2x() public {
        (uint256 startPrice, uint256 finalPrice, uint256[] memory prices) = _runScenarioWithPrices(20, 0xABCDEF);

        for (uint256 round = (ROUNDS / 2) + 1; round <= ROUNDS; round++) {
            assertGe(prices[round], prices[round - 1], "back-half price should keep recovering");
        }
        assertGt(finalPrice, startPrice, "2x withdraw pressure should not overcome invest pressure");
    }
}
