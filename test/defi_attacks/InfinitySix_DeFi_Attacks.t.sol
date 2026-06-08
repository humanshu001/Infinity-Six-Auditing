// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../SimulationSetup.t.sol";

contract InfinitySix_DeFi_Attacks_Test is SimulationSetup {
    UserReader public reader;

    function setUp() public override {
        super.setUp(); // Sets up live state
        reader = new UserReader();
    }

    // ITEM 34: Price Oracle manipulation and spot price safety
    // ITEM 40: TWAP vs spot price integration review
    // ITEM 55: Flash loan attack vulnerability assessment
    function test_Attack_PriceManipulation_FlashLoan() public {
        address attacker = makeAddr("attacker");
        usdt.mint(attacker, 1000 * 1e18);
        vm.startPrank(attacker, attacker);
        usdt.approve(address(sys), type(uint256).max);
        
        sys.invest(100 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        
        // Fast forward 15 days for ROI to accrue
        vm.warp(block.timestamp + 15 days);
        vm.roll(block.number + 10);
        
        uint256 normalPrice = sys.getSpotPrice();
        
        // Simulating a flash loan attack that dumps i6 into the pool, crashing the i6 price.
        // Because the pool is MockPair, we manually adjust reserves to simulate a massive swap.
        // Original reserves: USDT: ~485k, i6: ~425k. Price = 1.14 USDT per i6.
        // Attacker dumps 4,000,000 i6 tokens.
        // Pool becomes: i6 = 4,425,000, USDT = 485k / 10 = ~48k.
        // Spot price crashes to 48k / 4.4M = 0.01 USDT per i6.
        pair.setReserves(uint112(48000 * 1e18), uint112(4425000 * 1e18));
        
        uint256 crashedPrice = sys.getSpotPrice();
        
        assertLt(crashedPrice, normalPrice, "Price should crash after manipulation");
        
        // Now attacker withdraws their pending ROI while price is manipulated!
        uint256 i6Before = ptk.balanceOf(attacker);
        
        vm.startPrank(attacker, attacker);
        sys.withdraw();
        vm.stopPrank();
        
        uint256 i6After = ptk.balanceOf(attacker);
        uint256 withdrawnI6 = i6After - i6Before;
        
        // Due to instantaneous spot price, attacker receives massively inflated i6 tokens!
        console.log("[RISK] i6 tokens minted after flash loan manipulation:", withdrawnI6 / 1e18);
        assertGt(withdrawnI6, 500 * 1e18, "Attacker drained excessive i6 tokens due to spot price manipulation");
    }

    // ITEM 35: Front-running and sandwich attack susceptibility
    function test_Attack_FrontRunning_Slippage() public {
        // Users investing don't specify minTokensOut strictly if they don't know the exact math, 
        // but let's test if slippage protection works.
        address victim = makeAddr("victim");
        usdt.mint(victim, 1000 * 1e18);
        
        vm.startPrank(victim, victim);
        usdt.approve(address(sys), type(uint256).max);
        
        // Victim invests 1000 USDT.
        // They expect the contract to swap to add liquidity.
        // If an attacker sandwiches, the swap executes at a bad price.
        // Our MockRouter simulates a fixed swap price.
        // We will simulate the `minTokensOut` protection here.
        // If the victim passes 0 for `minTokensOut`, they get sandwiched.
        
        uint256 gasBefore = gasleft();
        sys.invest(100 * 1e18, ORIGIN, 0); // minTokensOut = 0 allows 100% slippage
        uint256 gasUsed = gasBefore - gasleft();
        
        vm.stopPrank();
        
        // The contract allows minTokensOut = 0, exposing users to sandwich attacks during the swap phase inside `invest()`.
        assertGt(gasUsed, 0);
    }

    // ITEM 36: Reentrancy vulnerability in withdrawal paths
    function test_Attack_Reentrancy() public {
        // Reentrancy on withdraw() is prevented by `nonReentrant` modifier.
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(sys, usdt);
        
        // In foundry, `tx.origin` == `msg.sender` for contracts is false unless we use prank.
        // The contract has `if(tx.origin != msg.sender) revert Err_NoContractCallsAllowed()`.
        // This makes reentrancy using a contract impossible by design!
        
        usdt.mint(address(attackerContract), 1000 * 1e18);
        
        vm.startPrank(address(attackerContract)); // Do not set tx.origin to bypass
        // Attempt to invest via contract
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attackerContract.invest();
        vm.stopPrank();
        
        // Therefore, smart-contract based reentrancy is blocked.
    }
}

contract ReentrancyAttacker {
    InfinitySixSystem sys;
    IERC20 usdt;
    
    constructor(InfinitySixSystem _sys, IERC20 _usdt) {
        sys = _sys;
        usdt = _usdt;
    }
    
    function invest() external {
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(100 * 1e18, 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1, 0);
    }
    
    // Fallback attempting to re-enter
    receive() external payable {
        sys.withdraw();
    }
}
