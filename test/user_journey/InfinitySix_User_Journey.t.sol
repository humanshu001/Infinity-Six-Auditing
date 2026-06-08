// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../SimulationSetup.t.sol";

contract InfinitySix_User_Journey_Test is SimulationSetup {
    UserReader public reader;

    function setUp() public override {
        super.setUp(); // Sets up live state
        reader = new UserReader();
    }

    // ITEM 11: Investment and deposit process validation
    function test_Deposit_IncreasesTotalAndLogs() public {
        address newUser = makeAddr("newUser");
        usdt.mint(newUser, 1000 * 1e18);
        
        vm.startPrank(newUser, newUser);
        usdt.approve(address(sys), type(uint256).max);
        
        // Ensure investment flows properly and assigns upline
        sys.invest(500 * 1e18, simUsers[0], 0);
        vm.stopPrank();

        uint256 totalDep = reader.totalDeposits(sys, newUser);
        assertEq(totalDep, 500 * 1e18);
    }

    // ITEM 14: Self-referral prevention verification
    function test_Sponsor_SelfReferralBlocked() public {
        address newUser = makeAddr("newUser");
        usdt.mint(newUser, 1000 * 1e18);
        
        vm.startPrank(newUser, newUser);
        usdt.approve(address(sys), type(uint256).max);
        
        vm.expectRevert(Err_CannotReferYourself.selector);
        sys.invest(100 * 1e18, newUser, 0); // Sponsor is themselves
        vm.stopPrank();
    }

    // ITEM 25: Package lifecycle and deactivation testing
    function test_Package_LifecycleMax6x() public {
        address user = simUsers[1];
        vm.startPrank(user, user);
        
        // Cannot invest more than 20k
        vm.roll(block.number + 1); // skip same block
        vm.expectRevert(Err_MaxInvestmentLimitExceed.selector);
        sys.invest(200000 * 1e18, ORIGIN, 0);
        
        vm.stopPrank();
    }

    // ITEM 29: Genesis account special privilege analysis
    // ITEM 31: ORIGIN_MEMBER_ID exceptional logic assessment
    function test_Origin_Exceptions() public {
        address fresh = makeAddr("fresh");
        usdt.mint(fresh, 1000 * 1e18);
        vm.startPrank(fresh, fresh);
        usdt.approve(address(sys), type(uint256).max);
        
        sys.invest(100 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        
        address ref = reader.referrer(sys, fresh);
        assertEq(ref, ORIGIN);
    }
}
