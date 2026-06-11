// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";
import "../BaseFork.t.sol";

contract IntermediaryContract {
    InfinitySixSystem system;
    IERC20 usdt;

    constructor(address _system, address _usdt) {
        system = InfinitySixSystem(_system);
        usdt = IERC20(_usdt);
    }

    function tryInvest(uint256 amount, address referrer) external {
        usdt.transferFrom(msg.sender, address(this), amount);
        usdt.approve(address(system), type(uint256).max);
        system.invest(amount, referrer, 0);
    }

    function tryWithdraw() external {
        system.withdraw();
    }
}

contract IntermediaryTokenCaller {
    InfinitySixToken token;

    constructor(address _token) {
        token = InfinitySixToken(_token);
    }

    function tryTransfer(address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}

contract TxOriginTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    InfinitySixToken realToken;
    IntermediaryContract intermediary;
    IntermediaryTokenCaller tokenCaller;

    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    error Err_NoContractCallsAllowed();

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        realToken = InfinitySixToken(TOKEN);
        
        intermediary = new IntermediaryContract(SYSTEM, USDT);
        tokenCaller = new IntermediaryTokenCaller(TOKEN);

        deal(address(usdt), attacker, 1000 * 1e18);
        deal(address(usdt), address(intermediary), 1000 * 1e18);

        vm.startPrank(attacker, attacker);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Warp to accrue ROI
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
    }

    function test_eoa_calls_succeed() public {
        // EOA invest succeeds
        vm.startPrank(attacker, attacker);
        realSystem.invest(100 * 1e18, ORIGIN, 0);

        // Advance block
        vm.roll(block.number + 1);

        // EOA withdraw succeeds
        realSystem.withdraw();
        vm.stopPrank();
    }

    function test_contract_invest_fails() public {
        vm.startPrank(attacker, attacker);
        usdt.approve(address(intermediary), type(uint256).max);
        
        // Attacker calls contract, which tries to invest -> should revert with Err_NoContractCallsAllowed
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        intermediary.tryInvest(100 * 1e18, ORIGIN);
        vm.stopPrank();
    }

    function test_contract_withdraw_fails() public {
        // Intermediary contract cannot withdraw because system checks tx.origin == msg.sender
        vm.prank(attacker, attacker);
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        intermediary.tryWithdraw();
    }

    function test_contract_token_transfer_fails() public {
        deal(address(realToken), address(tokenCaller), 100 * 1e18);

        vm.prank(attacker, attacker);
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        tokenCaller.tryTransfer(attacker, 10 * 1e18);
    }
}

