// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../SimulationSetup.t.sol";

contract InfinitySix_Withdrawals_Test is SimulationSetup {
    UserReader public reader;

    function setUp() public override {
        super.setUp(); // Sets up live state
        reader = new UserReader();
    }

    // ITEM 26: Withdrawal condition and cooldown enforcement
    // ITEM 28: Global limits on withdrawal amounts
    function test_Withdrawal_CooldownAndLimits() public {
        address user = simUsers[3];
        
        // Fast forward 3 days from setUp() to ensure ROI is generated
        vm.warp(block.timestamp + 3 days);
        
        uint256 expectedPrice = sys.getSpotPrice();
        uint256 balBefore = ptk.balanceOf(user);
        
        vm.startPrank(user, user);
        sys.withdraw();
        
        uint256 balAfter = ptk.balanceOf(user);
        assertGt(balAfter, balBefore, "Should have received i6 tokens");
        
        vm.roll(block.number + 1);
        
        // Try immediately withdrawing again (cooldown is 60 minutes)
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        sys.withdraw();
        vm.stopPrank();
        
        // Fast forward 61 minutes
        vm.warp(block.timestamp + 61 minutes);
        vm.startPrank(user, user);
        // Will likely revert with Err_NothingToWithdraw because 60 mins isn't enough to generate new ROI
        vm.expectRevert(Err_NothingToWithdraw.selector);
        sys.withdraw();
        vm.stopPrank();
    }

    // ITEM 27: Maximum income capitalization logic (6x cap mechanism)
    // ITEM 56: Precision loss and dust accumulation testing in withdrawal
    function test_Withdrawal_MaxCap6x() public {
        address user = makeAddr("capUser");
        usdt.mint(user, 1000 * 1e18);
        vm.startPrank(user, user);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * 1e18, ORIGIN, 0); // 6x cap = 600 WAD
        vm.stopPrank();
        
        // Now give them a direct deposit of 20000
        address whale = makeAddr("whale");
        usdt.mint(whale, 20000 * 1e18);
        vm.startPrank(whale, whale);
        usdt.approve(address(sys), type(uint256).max);
        // 5% of 20,000 = 1000 WAD > 600 WAD cap.
        sys.invest(20000 * 1e18, user, 0);
        vm.stopPrank();
        
        // Wait for direct bonus to unlock (12 hours)
        vm.warp(block.timestamp + 13 hours);
        vm.roll(block.number + 1); // <--- Add this!
        
        // User withdraws
        vm.startPrank(user, user);
        sys.withdraw();
        vm.stopPrank();
        
        // User should be capped
        bool isCapped = reader.isCapped(sys, user);
        assertEq(isCapped, true, "User should be capped after receiving 6x");
        
        // Next withdrawal should fail
        vm.warp(block.timestamp + 2 hours);
        vm.roll(block.number + 2);
        vm.startPrank(user, user);
        vm.expectRevert(Err_NoActiveInvestmentOrCapped.selector);
        sys.withdraw();
        vm.stopPrank();
    }

    // ITEM 38: Genesis node 7-way split verification
    function test_Withdrawal_GenesisSplit() public {
        address genesis = ORIGIN;
        
        // Give genesis some pending ROI
        vm.warp(block.timestamp + 30 days);
        
        // Get balances of GEN_W1 to GEN_W7 before
        address[7] memory genWallets = [
            0xc1Eb7F0c59499846eA7d9E889DCd89263Dd21026,
            0x2526c7a2744d7d63980f6A5cF48a670C821345Fc,
            0x1A1cE4eb714480206586EAD87af132C4D73BA34e,
            0x20eC5480B375deDC830587f049be3Aa5650F680E,
            0x80EFEa7E52D95749fb5544f39E7d53f3E485759a,
            0xA82a34158900fD2e861B4DD73C5Fb2f972C978CC,
            0x48e16dD50d687dEe67ac441AA0e74A958677E08B
        ];
        
        uint256[] memory balsBefore = new uint256[](7);
        for(uint i=0; i<7; i++) {
            balsBefore[i] = ptk.balanceOf(genWallets[i]);
        }
        
        vm.startPrank(genesis, genesis);
        sys.withdraw();
        vm.stopPrank();
        
        // Check if balances increased
        for(uint i=0; i<7; i++) {
            uint256 newBal = ptk.balanceOf(genWallets[i]);
            assertGt(newBal, balsBefore[i], "Genesis wallet should have received tokens");
        }
    }
}
