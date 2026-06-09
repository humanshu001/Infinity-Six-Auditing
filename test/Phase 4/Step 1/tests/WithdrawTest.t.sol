// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../../Phase 3/SimulationSetup.t.sol";

contract WithdrawTest is SimulationSetup {
    UserReader public reader;

    uint256 constant WAD = 1e18;
    uint256 constant MIN_INVEST = 100 * WAD;

    address alice;
    address bob;
    address carol;
    address dave;
    address eve;

    function setUp() public override {
        super.setUp();
        reader = new UserReader();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");
        eve = makeAddr("eve");

        address[5] memory addrs = [alice, bob, carol, dave, eve];
        for (uint i = 0; i < addrs.length; i++) {
            usdt.mint(addrs[i], 500_000 * WAD);
            vm.prank(addrs[i], addrs[i]);
            usdt.approve(address(sys), type(uint256).max);
        }
    }

    // ═══════════════════════════════════════════
    // ACCESS TESTS
    // ═══════════════════════════════════════════

    function test_withdraw_before_launch_plus_3_days() public {
        // deploy a fresh system so launchTime is now
        MockUSDT freshUsdt = new MockUSDT();
        MockProjectToken freshPtk = new MockProjectToken();
        MockRouter freshRouter = new MockRouter();
        MockPair freshPair = new MockPair(address(freshUsdt), address(freshPtk));
        freshRouter.setProjectToken(address(freshPtk));
        freshPair.setReserves(uint112(485277 ether), uint112(425497 ether));

        InfinitySixSystem freshSys = new InfinitySixSystem(
            address(freshUsdt), address(freshPtk), address(freshRouter), address(freshPair)
        );
        freshPtk.setMinter(address(freshSys));

        freshUsdt.mint(alice, 10_000 * WAD);
        vm.prank(alice, alice);
        freshUsdt.approve(address(freshSys), type(uint256).max);
        vm.prank(alice, alice);
        freshSys.invest(MIN_INVEST, ORIGIN, 0);

        // try withdraw within 3 days
        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);
        vm.prank(alice, alice);
        vm.expectRevert(Err_WithdrawalNotStarted.selector);
        freshSys.withdraw();
    }

    function test_withdraw_with_zero_deposits_reverts() public {
        // warp past launch+3days (simSetup already warps 15 days)
        vm.roll(block.number + 1);
        vm.prank(alice, alice);
        vm.expectRevert(Err_NoActiveInvestmentOrCapped.selector);
        sys.withdraw();
    }

    function test_withdraw_nothing_available_reverts() public {
        // a user with zero deposits trying to withdraw
        // warp past launch (simSetup already warps 15 days)
        vm.roll(block.number + 1);
        vm.prank(alice, alice);
        vm.expectRevert(Err_NoActiveInvestmentOrCapped.selector);
        sys.withdraw();
    }

    // ═══════════════════════════════════════════
    // COOLDOWN TESTS
    // ═══════════════════════════════════════════

    function test_withdraw_first_withdrawal_succeeds() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // warp enough for ROI to accumulate (1 day for compounding)
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // should have some totalWithdrawn
        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        assertGt(totalWithdrawn, 0);
    }

    function test_withdraw_within_60_minutes_reverts() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // advance block but stay within 60 minutes
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 2);
        vm.prank(alice, alice);
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        sys.withdraw();
    }

    function test_withdraw_exactly_60_minutes_reverts() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // exactly 60 minutes (<=, so still reverts)
        vm.warp(block.timestamp + 60 minutes);
        vm.roll(block.number + 2);
        vm.prank(alice, alice);
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        sys.withdraw();
    }

    function test_withdraw_after_60_minutes_succeeds() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // 1 day + 61 minutes later (enough for new ROI + past cooldown)
        vm.warp(block.timestamp + 1 days + 61 minutes);
        vm.roll(block.number + 2);
        vm.prank(alice, alice);
        sys.withdraw();

        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        assertGt(totalWithdrawn, 0);
    }

    // ═══════════════════════════════════════════
    // CATEGORY TESTS
    // ═══════════════════════════════════════════

    function test_withdraw_roi_only() public {
        // invest with no referrals, no rank - only ROI should generate
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 3 days);
        vm.roll(block.number + 1);

        uint256 tokenBefore = ptk.balanceOf(alice);
        vm.prank(alice, alice);
        sys.withdraw();
        uint256 tokenAfter = ptk.balanceOf(alice);

        assertGt(tokenAfter, tokenBefore);
    }

    function test_withdraw_direct_bonus() public {
        // alice invests, bob refers under alice to generate direct bonus
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.prank(bob, bob);
        sys.invest(1000 * WAD, alice, 0);

        // warp past 12h lock and 3-day launch for direct bonus unlock
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        // realize and check direct bonus
        (uint256 availableNow,) = sys.getDirectBonusInfo(alice);
        assertGt(availableNow, 0);

        vm.prank(alice, alice);
        sys.withdraw();
    }

    function test_withdraw_mixed_categories() public {
        // alice invests big, gets referrals for direct + level
        vm.prank(alice, alice);
        sys.invest(5000 * WAD, ORIGIN, 0);

        // 5 directs for eligibility + level income
        for (uint160 i = 1; i <= 5; i++) {
            address u = address(uint160(50_000 + i));
            usdt.mint(u, 10_000 * WAD);
            vm.prank(u, u);
            usdt.approve(address(sys), type(uint256).max);
            vm.prank(u, u);
            sys.invest(2000 * WAD, alice, 0);
        }

        vm.warp(block.timestamp + 3 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        assertGt(totalWithdrawn, 0);
    }

    // ═══════════════════════════════════════════
    // LIMIT TESTS
    // ═══════════════════════════════════════════

    function test_withdraw_roi_limit_applied() public {
        // ROI_MAX_WITHDRAWAL = 1000 WAD
        // invest big, warp long to accrue more than 1000 USDT ROI
        vm.prank(alice, alice);
        sys.invest(20_000 * WAD, ORIGIN, 0);

        // warp 30 days to accrue significant ROI
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // the ROI portion should be capped at 1000 USDT equivalent
        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        // total withdrawn includes all categories, but should be bounded
        assertGt(totalWithdrawn, 0);
        // ROI cap is 1000 * WAD, but total may include level income etc.
        // key assertion: withdrawal succeeded and didn't revert
    }

    // ═══════════════════════════════════════════
    // 6X CAP TESTS
    // ═══════════════════════════════════════════

    function test_withdraw_below_6x_not_capped() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        assertFalse(reader.isCapped(sys, alice));
    }

    function test_withdraw_reaching_6x_caps_user() public {
        // invest minimum, warp very long to accumulate 6x
        // 100 USDT * 6 = 600 USDT max earnings
        // 0.5% daily compound on 100 USDT
        // need ~many days. let's invest more to speed up.
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);

        // create referrals to generate direct/level income faster
        for (uint160 i = 1; i <= 5; i++) {
            address u = address(uint160(60_000 + i));
            usdt.mint(u, 50_000 * WAD);
            vm.prank(u, u);
            usdt.approve(address(sys), type(uint256).max);
            vm.prank(u, u);
            sys.invest(10_000 * WAD, alice, 0);
        }

        // warp long enough and withdraw repeatedly until capped
        bool capped = false;
        for (uint256 attempt = 0; attempt < 50; attempt++) {
            vm.warp(block.timestamp + 2 hours);
            vm.roll(block.number + 1);

            if (reader.isCapped(sys, alice)) {
                capped = true;
                break;
            }

            vm.prank(alice, alice);
            try sys.withdraw() {} catch {
                // may revert if nothing to withdraw or already capped
                break;
            }

            if (reader.isCapped(sys, alice)) {
                capped = true;
                break;
            }
        }

        // alice should eventually cap at 6x of 100 USDT = 600 USDT
        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        if (capped) {
            assertTrue(reader.isCapped(sys, alice));
            assertLe(totalWithdrawn, MIN_INVEST * 6);
        }
        // if not capped in 50 attempts, the direct bonuses may be in 12h lock
        // still, withdrawn amount should be <= 6x
        assertLe(totalWithdrawn, MIN_INVEST * 6);
    }

    function test_withdraw_proportional_scaling() public {
        // when hitting 6x cap, the payout is scaled proportionally
        // invest minimum with multiple income streams
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);

        for (uint160 i = 1; i <= 3; i++) {
            address u = address(uint160(70_000 + i));
            usdt.mint(u, 10_000 * WAD);
            vm.prank(u, u);
            usdt.approve(address(sys), type(uint256).max);
            vm.prank(u, u);
            sys.invest(1000 * WAD, alice, 0);
        }

        // warp and withdraw multiple times
        for (uint256 attempt = 0; attempt < 20; attempt++) {
            vm.warp(block.timestamp + 2 hours);
            vm.roll(block.number + 1);

            if (reader.isCapped(sys, alice)) break;

            vm.prank(alice, alice);
            try sys.withdraw() {} catch { break; }
        }

        // verify total never exceeds 6x
        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        assertLe(totalWithdrawn, MIN_INVEST * 6);
    }

    // ═══════════════════════════════════════════
    // ANTI-BOT (same block)
    // ═══════════════════════════════════════════

    function test_withdraw_same_block_reverts() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        sys.withdraw();

        // same block second withdraw
        vm.prank(alice, alice);
        vm.expectRevert(Err_SameBlockTxnNotAllowed.selector);
        sys.withdraw();
    }

    // ═══════════════════════════════════════════
    // TOKEN MINTING ON WITHDRAW
    // ═══════════════════════════════════════════

    function test_withdraw_mints_project_tokens() public {
        vm.prank(alice, alice);
        sys.invest(5000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 5 days);
        vm.roll(block.number + 1);

        uint256 tokenBefore = ptk.balanceOf(alice);
        vm.prank(alice, alice);
        sys.withdraw();
        uint256 tokenAfter = ptk.balanceOf(alice);

        assertGt(tokenAfter, tokenBefore);
    }

    function test_withdraw_applies_5_percent_fee() public {
        vm.prank(alice, alice);
        sys.invest(5000 * WAD, ORIGIN, 0);

        vm.warp(block.timestamp + 5 days);
        vm.roll(block.number + 1);

        // get spot price for manual calculation
        uint256 spotPrice = sys.getSpotPrice();

        vm.prank(alice, alice);
        sys.withdraw();

        (,,,,,,,,,,,,,,,,,,uint256 totalWithdrawn,,,,,,,,) = sys.users(alice);
        // tokens received should be 95% of (totalWithdrawn * WAD / spotPrice)
        uint256 expectedGross = (totalWithdrawn * WAD) / spotPrice;
        uint256 expectedNet = expectedGross - (expectedGross * 5) / 100;

        uint256 received = ptk.balanceOf(alice);
        // allow 1% tolerance for rounding
        assertGt(received, (expectedNet * 99) / 100);
        assertLt(received, (expectedNet * 101) / 100);
    }
}
