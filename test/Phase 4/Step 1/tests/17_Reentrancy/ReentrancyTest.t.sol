// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";
import "../BaseFork.t.sol";

contract ReentrantCallContract {
    InfinitySixSystem system;
    IERC20 usdt;
    address origin;

    constructor(address _system, address _usdt, address _origin) {
        system = InfinitySixSystem(_system);
        usdt = IERC20(_usdt);
        origin = _origin;
    }

    function tryInvest(uint256 amount) external {
        usdt.transferFrom(msg.sender, address(this), amount);
        usdt.approve(address(system), amount);
        system.invest(amount, origin, 0);
    }

    function tryWithdraw() external {
        system.withdraw();
    }
}

contract ReentrancyTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    InfinitySixToken realToken;
    ReentrantCallContract attackerContract;

    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    error Err_NoContractCallsAllowed();

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        realToken = InfinitySixToken(TOKEN);
        
        attackerContract = new ReentrantCallContract(SYSTEM, USDT, ORIGIN);
        
        deal(address(usdt), attacker, 1000 * 1e18);
        vm.prank(attacker);
        usdt.approve(address(attackerContract), type(uint256).max);
    }

    function test_reentrancy_blocked_by_tx_origin_on_invest() public {
        vm.startPrank(attacker, attacker);
        
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attackerContract.tryInvest(100 * 1e18);
        
        vm.stopPrank();
    }

    function test_reentrancy_blocked_by_tx_origin_on_withdraw() public {
        vm.startPrank(attacker, attacker);
        
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attackerContract.tryWithdraw();
        
        vm.stopPrank();
    }
}

