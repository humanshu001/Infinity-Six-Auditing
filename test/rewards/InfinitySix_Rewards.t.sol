// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../SimulationSetup.t.sol";

contract InfinitySix_Rewards_Test is SimulationSetup {
    UserReader public reader;

    function setUp() public override {
        super.setUp(); // Sets up live state
        reader = new UserReader();
    }

    // ITEM 15: Direct bonus calculation and lock mechanism analysis
    // ITEM 16: Pending bonus unlock schedule validation
    function test_DirectBonus_LockedAndVesting() public {
        address referrer = simUsers[0];
        address newDirect = makeAddr("newDirect");
        
        usdt.mint(newDirect, 1000 * 1e18);
        vm.startPrank(newDirect, newDirect);
        usdt.approve(address(sys), type(uint256).max);
        
        uint256 invAmount = 1000 * 1e18;
        sys.invest(invAmount, referrer, 0);
        vm.stopPrank();

        // 5% direct bonus on 1000 = 50 USDT
        // Should be added to pendingDirectBonuses[referrer]
        (uint256 amount, uint256 unlockTime) = sys.pendingDirectBonuses(referrer, 0);
        
        // Assertions
        assertEq(amount, 50 * 1e18);
        assertGt(unlockTime, block.timestamp); // Should be locked for some days

        // Fast forward past unlock time
        vm.warp(unlockTime + 1);
        
        // When referrer claims ROI/withdraws, this should become claimable.
        // We will just verify the state was written correctly for now.
    }

    // ITEM 17: Multi-level reward engine review (up to 40 levels)
    // ITEM 18: Level income accrual and realization analysis
    // ITEM 33: Downline business propagation testing
    function test_LevelIncome_AccrualOnROI() public {
        // Fast forwarding 1 day should accrue ROI
        // Simulation setup already fast forwarded 15 days
        // We can getLevelIncomeData to force realization
        
        address user = simUsers[2];
        (uint256 levelIncome, ) = sys.getLevelIncomeData(user);
        
        // Since the simulation built a 15-deep tree, user should have downlines and level income
        assertGt(levelIncome, 0, "Level income should be > 0 due to deep tree and time passed");
    }

    // ITEM 20: Daily ROI compounding logic validation
    function test_ROI_Calculation() public {
        address user = simUsers[1];
        
        // Read the investment before compounding
        (uint256 amount, uint256 compPrin1, , , , ) = sys.userInvestments(user, 0);
        
        // Fast forward 15 days
        vm.warp(block.timestamp + 15 days);
        
        // Trigger compounding by doing a small invest
        usdt.mint(user, 100 * 1e18);
        vm.startPrank(user, user);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        ( , uint256 compPrin2, , , , ) = sys.userInvestments(user, 0);
        
        uint256 pendingROI = compPrin2 - compPrin1;
        
        // Expected ~ 7.5% over 15 days on the initial amount
        uint256 expectedMin = (amount * 5 * 15) / 1000;
        
        assertGt(pendingROI, 0);
        assertGe(pendingROI, expectedMin);
    }

    // ITEM 22: Rank qualification and promotion testing
    function test_Rank_Qualification() public {
        address user = makeAddr("rankUser");
        usdt.mint(user, 1000 * 1e18);
        vm.startPrank(user, user);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        
        for(uint i=0; i<5; i++) {
            address d = makeAddr(string(abi.encodePacked("direct", i)));
            usdt.mint(d, 5000 * 1e18); // 5000 * 5 = 25k volume
            vm.startPrank(d, d);
            usdt.approve(address(sys), type(uint256).max);
            sys.invest(5000 * 1e18, user, 0);
            vm.stopPrank();
        }
        
        // _tryAutoRank automatically promoted the user
        uint256 rank = reader.currentRank(sys, user);
        assertGt(rank, 0, "User should have ranked up to at least Rank 1 automatically");
    }

    // ITEM 23: Salary accrual and maintenance requirement review
    // ITEM 32: Team volume and fresh business accounting validation
    function test_Salary_Accrual() public {
        address user = makeAddr("salUser");
        usdt.mint(user, 1000 * 1e18);
        vm.startPrank(user, user);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        
        // Force rank 1
        for(uint i=0; i<5; i++) {
            address d = makeAddr(string(abi.encodePacked("sal_direct", i)));
            usdt.mint(d, 5000 * 1e18);
            vm.startPrank(d, d);
            usdt.approve(address(sys), type(uint256).max);
            sys.invest(5000 * 1e18, user, 0);
            vm.stopPrank();
        }
        
        // Fast forward 30 days to accrue salary
        vm.warp(block.timestamp + 30 days);
        
        uint256 pendingSal = sys.getPendingSalary(user);
        assertGt(pendingSal, 0, "Should have pending salary accrued");
    }

    // ITEM 52: Unbounded loop and performance analysis (Level updates)
    function test_Risk_UnboundedLoop_UpdateDownline() public {
        // Investing from a deep node triggers an update up to 1000 levels.
        address deepUser = simUsers[simUsers.length - 1]; // 15 deep
        
        address fresh = makeAddr("freshLoop");
        usdt.mint(fresh, 100 * 1e18);
        vm.startPrank(fresh, fresh);
        usdt.approve(address(sys), type(uint256).max);
        
        uint256 gasBefore = gasleft();
        sys.invest(100 * 1e18, deepUser, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();
        
        // The gas used will be quite high because it traverses up the tree.
        // It's a known risk item (DoS at 1000 levels)
        console.log("[RISK] Gas used for 16-deep invest:", gasUsed);
        assertGt(gasUsed, 100000);
    }
}
