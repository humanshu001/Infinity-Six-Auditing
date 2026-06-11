// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseFork.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBurnable {
    function burn(uint256 amount) external;
}

contract SupplyManipulationTest is BaseForkSetup {

    function test_BurnThenMint() public {
        // mint some tokens to attacker, burn part, then mint again
        uint256 before = IERC20(TOKEN).balanceOf(attacker);

        vm.prank(SYSTEM);
        token.mint(attacker, 100 ether);

        uint256 afterMint = IERC20(TOKEN).balanceOf(attacker);
        assertEq(afterMint, before + 100 ether);

        vm.prank(attacker);
        IBurnable(TOKEN).burn(50 ether);

        uint256 afterBurn = IERC20(TOKEN).balanceOf(attacker);
        assertEq(afterBurn, before + 50 ether);

        vm.prank(SYSTEM);
        token.mint(attacker, 25 ether);

        uint256 finalBal = IERC20(TOKEN).balanceOf(attacker);
        assertEq(finalBal, before + 75 ether);
    }

    function test_MintThenBurn() public {
        uint256 before = IERC20(TOKEN).balanceOf(attacker);
        vm.prank(SYSTEM);
        token.mint(attacker, 20 ether);

        vm.prank(attacker);
        IBurnable(TOKEN).burn(10 ether);

        uint256 afterBal = IERC20(TOKEN).balanceOf(attacker);
        assertEq(afterBal, before + 10 ether);
    }

    function test_SupplyAccountingMonotonic() public {
        uint256 totalBefore = token.totalSupply();
        vm.prank(SYSTEM);
        token.mint(attacker, 5 ether);
        uint256 totalAfter = token.totalSupply();
        assertGt(totalAfter, totalBefore);
    }
}
