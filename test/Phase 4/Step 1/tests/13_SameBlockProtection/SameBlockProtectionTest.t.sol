// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";
import "../BaseFork.t.sol";

contract SameBlockProtectionTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    InfinitySixToken realToken;

    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    error Err_SameBlockTxnNotAllowed();
    error Err_SameBlockTransferNotAllowed();
    error Err_CooldownActive();

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        realToken = InfinitySixToken(TOKEN);

        deal(address(usdt), attacker, 1000 * 1e18);
        deal(address(usdt), attacker2, 1000 * 1e18);

        vm.startPrank(attacker, attacker);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        vm.startPrank(attacker2, attacker2);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Warp to accrue ROI
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
    }

    function test_deposit_twice_same_block_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // First deposit in block
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        // Second deposit in same block should revert
        vm.expectRevert(Err_SameBlockTxnNotAllowed.selector);
        realSystem.invest(100 * 1e18, ORIGIN, 0);
        
        vm.stopPrank();
    }

    function test_withdraw_twice_same_block_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // First withdraw
        realSystem.withdraw();

        // Second withdraw in same block should revert
        vm.expectRevert(Err_SameBlockTxnNotAllowed.selector);
        realSystem.withdraw();

        vm.stopPrank();
    }

    function test_deposit_and_withdraw_same_block_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // Deposit
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        // Withdraw in same block should revert
        vm.expectRevert(Err_SameBlockTxnNotAllowed.selector);
        realSystem.withdraw();

        vm.stopPrank();
    }

    function test_withdraw_and_deposit_same_block_reverts() public {
        vm.startPrank(attacker, attacker);
        
        // Withdraw
        realSystem.withdraw();

        // Deposit in same block should revert
        vm.expectRevert(Err_SameBlockTxnNotAllowed.selector);
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        vm.stopPrank();
    }

    function test_transfer_twice_same_block_sender_reverts() public {
        // Attacker needs some token balance first to test transfer.
        // Since buying is closed, we will deal some token directly.
        deal(address(realToken), attacker, 100 * 1e18);

        vm.startPrank(attacker, attacker);
        
        // First transfer in block
        realToken.transfer(attacker2, 10 * 1e18);

        // Second transfer in same block from same sender should revert
        vm.expectRevert(Err_SameBlockTransferNotAllowed.selector);
        realToken.transfer(attacker3, 10 * 1e18);

        vm.stopPrank();
    }

    function test_transfer_twice_same_block_receiver_reverts() public {
        deal(address(realToken), attacker, 50 * 1e18);
        deal(address(realToken), attacker2, 50 * 1e18);

        // Attacker transfers to attacker3
        vm.prank(attacker, attacker);
        realToken.transfer(attacker3, 10 * 1e18);

        // Attacker2 trying to transfer to attacker3 in the same block should revert (cooldown active)
        vm.prank(attacker2, attacker2);
        vm.expectRevert(Err_CooldownActive.selector);
        realToken.transfer(attacker3, 10 * 1e18);
    }

    function test_multi_wallet_same_block_succeeds() public {
        // Confirm that two different wallets can execute transactions in the same block
        vm.prank(attacker, attacker);
        realSystem.withdraw();

        vm.prank(attacker2, attacker2);
        realSystem.withdraw();
    }
}

