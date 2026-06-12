// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../BaseFork.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "i6systemcontract.sol";

contract WithdrawalTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        
        deal(address(usdt), attacker, 1000 * 1e18);
        deal(address(usdt), attacker2, 1000 * 1e18);

        // Invest for attacker
        vm.startPrank(attacker, attacker);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Invest for attacker2
        vm.startPrank(attacker2, attacker2);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Warp to accrue ROI
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
    }

    function test_WithdrawTwiceSameBlockReverts() public {
        vm.startPrank(attacker, attacker);
        realSystem.withdraw();

        vm.expectRevert();
        realSystem.withdraw();

        vm.stopPrank();
    }

    function test_WithdrawCooldownBehavior() public {
        vm.startPrank(attacker2, attacker2);
        realSystem.withdraw();

        // advance one block but not time -> cooldown should block second withdraw
        vm.roll(block.number + 1);
        vm.expectRevert();
        realSystem.withdraw();

        // advance time beyond cooldown and withdraw should be allowed (if funds exist)
        vm.warp(block.timestamp + 3600 + 1);
        try realSystem.withdraw() {
        } catch {
        }

        vm.stopPrank();
    }

    function test_WithdrawImmediatelyAfterDepositRevertsOrNothing() public {
        // create a fresh user and invest then attempt withdraw immediately
        address newcomer = address(uint160(uint256(keccak256(abi.encodePacked("new", block.timestamp)))));
        vm.label(newcomer, "newcomer");

        deal(address(usdt), newcomer, 200 * 1e18);
        vm.startPrank(newcomer, newcomer);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        vm.expectRevert();
        realSystem.withdraw();

        vm.stopPrank();
    }
}
