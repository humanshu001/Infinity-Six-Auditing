// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../../Phase 3/SimulationSetup.t.sol";

contract PackageCapTest is SimulationSetup {
    uint256 constant WAD = 1e18;
    uint256 constant MIN_INVEST = 100 * WAD;

    address alice;
    address bob;

    uint256 currentTimestamp;
    uint256 currentBlock;

    function setUp() public override {
        super.setUp();

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        usdt.mint(alice, 500_000 * WAD);
        usdt.mint(bob, 500_000 * WAD);

        vm.prank(alice, alice);
        usdt.approve(address(sys), type(uint256).max);
        vm.prank(bob, bob);
        usdt.approve(address(sys), type(uint256).max);

        currentTimestamp = block.timestamp;
        currentBlock = block.number;
    }

    function warpAndRoll(uint256 sec, uint256 blocks) internal {
        currentTimestamp += sec;
        currentBlock += blocks;
        vm.warp(currentTimestamp);
        vm.roll(currentBlock);
    }

    // helper to read a package's fields
    function _getPackage(address user, uint256 idx) internal view returns (uint256 amount, uint256 compounded, uint256 rwpWithdrawn, uint256 lastUpdateTime, bool isActive) {
        (amount, compounded, rwpWithdrawn, lastUpdateTime, isActive, ) = sys.userInvestments(user, idx);
    }

    // ── 2.5x Package Cap: Exactly 2.5x, Slightly below, Slightly above ──

    function test_package_cap_slightly_below() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // Max RWP allowed is 2.5x of 1000 = 2500 USDT.
        // Warp enough to get near but below 2500 USDT in compounding principal.
        // 1000 * 1.005^170 = ~2332 USDT (RWP = 1332 USDT).
        warpAndRoll(170 days, 170 days / 3);

        // Withdraw once (gets 1000 WAD)
        vm.prank(alice, alice);
        sys.withdraw();

        (,, uint256 rwpWithdrawn,, bool isActive) = _getPackage(alice, 0);
        assertEq(rwpWithdrawn, 1000 * WAD);
        assertTrue(isActive);

        // Withdraw again after cooldown
        warpAndRoll(61 minutes, 2);
        vm.prank(alice, alice);
        sys.withdraw();

        (,, rwpWithdrawn,, isActive) = _getPackage(alice, 0);
        // Total withdrawn is now 1332 WAD (which is < 2500 WAD)
        assertLt(rwpWithdrawn, 2500 * WAD);
        assertTrue(isActive);
    }

    function test_package_cap_exactly_or_exceeding_cap() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // Warp 300 days, compounding exceeds 3.5x (around 4460 WAD, meaning > 2500 WAD RWP generated)
        warpAndRoll(300 days, 300 days / 3);

        // Call sequential withdrawal helper to cap it
        _capUserPackages(alice);

        (,, uint256 rwpWithdrawn,, bool isActive) = _getPackage(alice, 0);
        // It must cap exactly at 2500 USDT (2.5x of 1000)
        assertEq(rwpWithdrawn, 2500 * WAD);
        assertFalse(isActive);
    }

    // ── Multiple Packages Capping ──

    function test_package_cap_multiple_packages() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // wait 10 days and add second package
        warpAndRoll(10 days, 10 days / 3);
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // warp 300 days. both will exceed 2.5x cap.
        warpAndRoll(300 days, 300 days / 3);

        // Call sequential withdrawal helper to cap both
        _capUserPackages(alice);

        (,, uint256 rwp0,, bool active0) = _getPackage(alice, 0);
        (,, uint256 rwp1,, bool active1) = _getPackage(alice, 1);

        assertEq(rwp0, 2500 * WAD);
        assertFalse(active0);

        assertEq(rwp1, 2500 * WAD);
        assertFalse(active1);
    }

    // ── State: Package deactivation, Active volume removal, Reinvestment after package cap ──

    function test_package_cap_active_volume_removal_from_upline() public {
        // Alice refers Bob
        vm.prank(alice, alice);
        sys.invest(2000 * WAD, ORIGIN, 0);

        vm.prank(bob, bob);
        sys.invest(1000 * WAD, alice, 0);

        // Bob's investment adds 1000 to Alice's level base volume.
        // Let's verify Alice's levelRewardBase at level 1 is non-zero
        uint256 baseBefore = getLevelRewardBase(alice, 1);
        assertGt(baseBefore, 0);

        // Warp Bob to cap his package (300 days)
        warpAndRoll(300 days, 300 days / 3);

        // Cap Bob's package
        _capUserPackages(bob);

        (,,,, bool bobActive) = _getPackage(bob, 0);
        assertFalse(bobActive);

        // Since Bob's package is capped (inactive), Alice's levelRewardBase for level 1
        // should be reduced by the dropVol (1000 WAD volume removed from stream)
        uint256 baseAfter = getLevelRewardBase(alice, 1);
        assertEq(baseAfter, 0);
    }

    function test_reinvestment_after_package_cap() public {
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        // Warp to cap Alice's package
        warpAndRoll(300 days, 300 days / 3);

        // Cap Alice's package
        _capUserPackages(alice);

        (,,,, bool activeBefore) = _getPackage(alice, 0);
        assertFalse(activeBefore);

        // Reinvest after package cap
        warpAndRoll(1 days, 100);
        vm.prank(alice, alice);
        sys.invest(1000 * WAD, ORIGIN, 0);

        (,,,, bool activeAfter) = _getPackage(alice, 1);
        assertTrue(activeAfter);
    }

    // helper to read Alice's levelRewardBase via vm.load (slot 46)
    function getLevelRewardBase(address user, uint256 level) public view returns (uint256) {
        bytes32 baseSlot = keccak256(abi.encode(user, uint256(46)));
        bytes32 targetSlot = bytes32(uint256(baseSlot) + 7 + level);
        return uint256(vm.load(address(sys), targetSlot));
    }

    // helper to sequentially withdraw to cap packages
    function _capUserPackages(address user) internal {
        uint256 len = _getUserInvestmentsLength(user);
        for (uint256 iter = 0; iter < 10; iter++) {
            vm.prank(user, user);
            try sys.withdraw() {} catch {
                break;
            }
            
            bool anyActive = false;
            for (uint256 i = 0; i < len; i++) {
                (,,,, bool active) = _getPackage(user, i);
                if (active) {
                    anyActive = true;
                }
            }
            if (!anyActive) {
                break;
            }
            warpAndRoll(61 minutes, 2);
        }
    }

    // helper to get user investments length
    function _getUserInvestmentsLength(address user) internal view returns (uint256) {
        uint256 count = 0;
        while (true) {
            try sys.userInvestments(user, count) {
                count++;
            } catch {
                break;
            }
        }
        return count;
    }
}
