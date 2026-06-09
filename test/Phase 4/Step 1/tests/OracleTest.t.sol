// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../../Phase 3/SimulationSetup.t.sol";

contract OracleTest is SimulationSetup {
    uint256 constant WAD = 1e18;

    address alice;
    uint256 currentTimestamp;
    uint256 currentBlock;

    function setUp() public override {
        super.setUp();

        currentTimestamp = block.timestamp;
        currentBlock = block.number;

        alice = makeAddr("alice");
        usdt.mint(alice, 1000 * WAD);

        vm.startPrank(alice, alice);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * WAD, ORIGIN, 0);
        vm.stopPrank();

        // Warp 15 days so Alice has ROI accrued
        warpAndRoll(15 days, 15 days / 3);
    }

    function warpAndRoll(uint256 sec, uint256 blocks) internal {
        currentTimestamp += sec;
        currentBlock += blocks;
        vm.warp(currentTimestamp);
        vm.roll(currentBlock);
    }

    // ── 1. Spot Price Calculation ──

    function test_spot_price_normal_reserves() public view {
        // Query current reserves dynamically and verify getSpotPrice() returns the correct ratio
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 expectedPrice = (uint256(r0) * WAD) / uint256(r1);
        uint256 price = sys.getSpotPrice();
        assertEq(price, expectedPrice);
    }

    function test_spot_price_tiny_reserves() public {
        // Set reserves to extremely tiny values (e.g. 10 wei USDT, 5 wei ptk)
        pair.setReserves(10, 5);
        
        // Price should be (10 * 1e18) / 5 = 2 * 1e18
        uint256 price = sys.getSpotPrice();
        assertEq(price, 2 * WAD);
    }

    function test_spot_price_huge_reserves() public {
        // Set reserves to huge values close to uint112 max (e.g. 1e30)
        uint112 hugeReserve = 1e30;
        pair.setReserves(hugeReserve, hugeReserve);

        // Price should be (1e30 * 1e18) / 1e30 = 1e18
        uint256 price = sys.getSpotPrice();
        assertEq(price, 1 * WAD);
    }

    function test_spot_price_empty_reserves_reverts() public {
        // If USDT reserve is 0, it should revert with Err_NoLiquidity
        pair.setReserves(0, 1000 * uint112(WAD));
        vm.expectRevert(Err_NoLiquidity.selector);
        sys.getSpotPrice();

        // If ptk reserve is 0, it should revert with Err_NoLiquidity
        pair.setReserves(1000 * uint112(WAD), 0);
        vm.expectRevert(Err_NoLiquidity.selector);
        sys.getSpotPrice();
    }

    // ── 2. Price Manipulation ──

    function test_oracle_manipulation_pump() public {
        uint256 initialPrice = sys.getSpotPrice();

        // Pump the price by heavily increasing USDT reserve and decreasing ptk reserve
        // e.g. USDT = 2,000,000 ether, ptk = 100,000 ether
        pair.setReserves(2_000_000 * uint112(WAD), 100_000 * uint112(WAD));

        uint256 pumpedPrice = sys.getSpotPrice();
        assertGt(pumpedPrice, initialPrice);
        assertEq(pumpedPrice, 20 * WAD); // 20 USDT per ptk
    }

    function test_oracle_manipulation_dump() public {
        uint256 initialPrice = sys.getSpotPrice();

        // Dump the price by heavily decreasing USDT reserve and increasing ptk reserve
        // e.g. USDT = 50,000 ether, ptk = 2,000,000 ether
        pair.setReserves(50_000 * uint112(WAD), 2_000_000 * uint112(WAD));

        uint256 dumpedPrice = sys.getSpotPrice();
        assertLt(dumpedPrice, initialPrice);
        assertEq(dumpedPrice, (50_000 * WAD) / 2_000_000); // 0.025 USDT per ptk
    }

    // ── 3. Flash Loan Distortion Impact ──

    function test_flash_loan_distortion_impact() public {
        // Alice has some pending ROI now.
        // We crash the price to 0.01 USDT per token using flash loan simulation
        pair.setReserves(1000 * uint112(WAD), 100_000 * uint112(WAD));
        uint256 crashedPrice = sys.getSpotPrice();
        assertEq(crashedPrice, 100 * 1e14); // 0.01 USDT

        uint256 balanceBefore = ptk.balanceOf(alice);

        // Alice withdraws during the crashed price period
        vm.prank(alice, alice);
        sys.withdraw();

        uint256 balanceAfter = ptk.balanceOf(alice);
        uint256 withdrawnAmount = balanceAfter - balanceBefore;

        // Since the price was distorted downward, Alice receives heavily inflated tokens
        // For 15 days, 100 USDT investment generates ~7.5 USDT.
        // At normal price (~1.14 USDT), she would receive ~6.5 tokens.
        // At crashed price (0.01 USDT), she receives 750 tokens!
        assertGt(withdrawnAmount, 700 * WAD);
    }
}
