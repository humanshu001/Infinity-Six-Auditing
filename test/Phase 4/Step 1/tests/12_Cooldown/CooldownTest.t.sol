// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "i6systemcontract.sol";
import "../BaseFork.t.sol";

contract CooldownTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    
    error Err_WithdrawalCooldownActive();
    error Err_SameBlockTxnNotAllowed();

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        
        // Setup initial deposits for attacker and attacker2
        deal(address(usdt), attacker, 1000 * 1e18);
        deal(address(usdt), attacker2, 1000 * 1e18);

        // Approve and invest for attacker
        vm.startPrank(attacker, attacker);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Approve and invest for attacker2
        vm.startPrank(attacker2, attacker2);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Warp 10 days to accrue withdrawable ROI
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
    }

    function test_withdraw_at_3599_seconds_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // First withdrawal succeeds
        realSystem.withdraw();
        uint256 withdrawTime = block.timestamp;

        // Warp to 3599 seconds after withdrawal
        vm.warp(withdrawTime + 3599);
        vm.roll(block.number + 10);

        // Second withdrawal in cooldown should revert
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        realSystem.withdraw();
        vm.stopPrank();
    }

    function test_withdraw_at_3600_seconds_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // First withdrawal succeeds
        realSystem.withdraw();
        uint256 withdrawTime = block.timestamp;

        // Warp to exactly 3600 seconds after withdrawal
        vm.warp(withdrawTime + 3600);
        vm.roll(block.number + 10);

        // Exactly 3600 seconds should still revert (cooldown is <= lastWithdrawTime + 3600)
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        realSystem.withdraw();
        vm.stopPrank();
    }

    function test_withdraw_at_3601_seconds_passes() public {
        vm.startPrank(attacker, attacker);
        
        // First withdrawal succeeds
        realSystem.withdraw();
        uint256 withdrawTime = block.timestamp;

        // Warp to 1 day + 3601 seconds so that 1 day has elapsed (to accrue more ROI)
        // and also greater than 3600 seconds cooldown
        vm.warp(withdrawTime + 1 days + 3601);
        vm.roll(block.number + 100);

        // 3601 seconds and 1 day elapsed should pass cooldown and ROI check
        realSystem.withdraw();
        vm.stopPrank();
    }

    function test_multiple_wallets_rotating_cooldown() public {
        // Attacker 1 withdraws
        vm.prank(attacker, attacker);
        realSystem.withdraw();
        uint256 t1 = block.timestamp;

        // Attacker 2 withdraws at same time
        vm.prank(attacker2, attacker2);
        realSystem.withdraw();

        // Warp 1800 seconds (30 mins)
        vm.warp(t1 + 1800);
        vm.roll(block.number + 10);

        // Attacker 1 cannot withdraw yet
        vm.prank(attacker, attacker);
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        realSystem.withdraw();

        // Attacker 2 cannot withdraw yet
        vm.prank(attacker2, attacker2);
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        realSystem.withdraw();
    }

    function test_cooldown_reset_manipulation() public {
        vm.startPrank(attacker, attacker);
        
        // First withdrawal
        realSystem.withdraw();
        uint256 withdrawTime = block.timestamp;
        uint256 currentBlock = block.number;

        // Calling invest() during cooldown
        // Advance block and warp
        vm.warp(withdrawTime + 10);
        vm.roll(currentBlock + 10);
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        // Try to withdraw immediately after invest (at 20s post-withdraw)
        vm.warp(withdrawTime + 20);
        vm.roll(currentBlock + 20);

        // Should still revert with cooldown active (invest does not reset lastWithdrawTime or bypass cooldown)
        vm.expectRevert(Err_WithdrawalCooldownActive.selector);
        realSystem.withdraw();
        vm.stopPrank();
    }

    function testFuzz_cooldown(uint256 warpTime) public {
        // Bound warpTime between 1 second and 100 days to avoid underflow/overflow
        warpTime = bound(warpTime, 1, 100 days);

        vm.startPrank(attacker, attacker);
        
        // First withdrawal
        realSystem.withdraw();
        uint256 withdrawTime = block.timestamp;
        uint256 currentBlock = block.number;

        // Warp by fuzz value
        vm.warp(withdrawTime + warpTime);
        vm.roll(currentBlock + 100);

        if (warpTime <= 3600) {
            vm.expectRevert(Err_WithdrawalCooldownActive.selector);
            realSystem.withdraw();
        } else {
            // Ensure at least 1 day has passed to accrue ROI, so we don't hit NothingToWithdraw
            if (warpTime < 1 days) {
                vm.warp(withdrawTime + 1 days);
            }
            realSystem.withdraw();
        }
        vm.stopPrank();
    }
}



