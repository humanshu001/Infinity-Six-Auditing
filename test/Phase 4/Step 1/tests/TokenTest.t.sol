// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "../../../../i6token.sol";

contract TokenTest is Test {
    InfinitySixToken public token;
    address public dao;
    address public systemContract;
    address public liquidityPair;
    address public alice;
    address public bob;

    uint256 constant WAD = 1e18;

    function setUp() public {
        dao = makeAddr("dao");
        systemContract = makeAddr("systemContract");
        liquidityPair = makeAddr("liquidityPair");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy token with 1,000,000 supply minted to deployer (this contract)
        token = new InfinitySixToken(dao, 1_000_000 * WAD);

        // DAO sets up system contract and liquidity pair
        vm.startPrank(dao);
        token.setSystemContract(systemContract);
        token.setLiquidityPair(liquidityPair);
        vm.stopPrank();

        // Transfer some tokens to liquidityPair and Alice for tests
        token.transfer(liquidityPair, 100_000 * WAD);
        token.transfer(alice, 10_000 * WAD);

        // Roll block to clear same-block cooldown from setup transfers
        vm.roll(block.number + 1);
    }

    // ── 1. Buying Lock Tests ──

    function test_buy_before_unlock_fails() public {
        // Initially, buying is disabled. 
        // Buying (from liquidityPair to Alice) should revert.
        vm.prank(liquidityPair);
        vm.expectRevert(Err_BuyingRestricted.selector);
        token.transfer(alice, 100 * WAD);
    }

    function test_enable_buying_too_early_fails() public {
        // Attempting to enable buying before 180 days should revert.
        vm.warp(block.timestamp + 179 days);
        vm.prank(dao);
        vm.expectRevert(Err_UnlockTooEarly.selector);
        token.enableBuying();
    }

    function test_buy_after_unlock_succeeds() public {
        // Warp past 180 days unlock delay
        vm.warp(block.timestamp + 180 days + 1);

        // DAO enables buying
        vm.prank(dao);
        token.enableBuying();

        // Now buying (liquidityPair to Alice) succeeds
        vm.prank(liquidityPair);
        bool success = token.transfer(alice, 100 * WAD);
        assertTrue(success);
    }

    function test_buy_by_system_contract_succeeds_even_when_disabled() public {
        // Even when buying is disabled, systemContract can receive tokens from liquidityPair
        vm.prank(liquidityPair);
        bool success = token.transfer(systemContract, 100 * WAD);
        assertTrue(success);
    }

    // ── 2. Transfer Restrictions Tests ──

    function test_same_block_send_fails_for_non_whitelisted() public {
        // Alice (non-whitelisted EOA) transfers to Bob
        vm.startPrank(alice, alice);
        token.transfer(bob, 100 * WAD);

        // Second transfer from Alice in the same block should revert
        vm.expectRevert(Err_SameBlockTransferNotAllowed.selector);
        token.transfer(bob, 100 * WAD);
        vm.stopPrank();
    }

    function test_same_block_receive_fails_for_non_whitelisted() public {
        // Deploy another sender to avoid sender same-block limit
        address charlie = makeAddr("charlie");
        // Give charlie tokens in a separate block first
        token.transfer(charlie, 1000 * WAD);
        vm.roll(block.number + 1);

        // Alice transfers to Bob
        vm.prank(alice, alice);
        token.transfer(bob, 100 * WAD);

        // Charlie transfers to Bob in the same block (receiver Bob cooldown active)
        vm.prank(charlie, charlie);
        vm.expectRevert(Err_CooldownActive.selector);
        token.transfer(bob, 100 * WAD);
    }

    function test_contract_transfer_fails_for_non_whitelisted() public {
        // Deploy a simple receiver contract
        SimpleReceiver c = new SimpleReceiver(address(token));

        // Alice transfers to the contract (from EOA Alice to Contract c)
        // Since from (Alice) is EOA and to (c) is Contract:
        // tx.origin (Alice) == msg.sender (Alice), so it succeeds.
        vm.prank(alice, alice);
        token.transfer(address(c), 100 * WAD);

        // Contract c tries to transfer tokens to Bob.
        // Since both from (c) and to (Bob) are non-whitelisted, and tx.origin (Alice calling c) != msg.sender (c),
        // it must revert with Err_NoContractCallsAllowed.
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        c.forwardTokens(bob, 50 * WAD);
    }

    function test_eoa_transfer_succeeds() public {
        // Normal EOA to EOA transfer on separate blocks succeeds
        vm.prank(alice, alice);
        token.transfer(bob, 100 * WAD);

        // Roll block
        vm.roll(block.number + 1);

        vm.prank(alice, alice);
        bool success = token.transfer(bob, 100 * WAD);
        assertTrue(success);
    }

    // ── 3. Whitelist Tests ──

    function test_whitelisted_sender_bypasses_restrictions() public {
        // Whitelist Alice
        vm.prank(dao);
        token.setWhitelist(alice, true);

        address charlie = makeAddr("charlie");

        // Alice can send twice in the same block to different receivers 
        // without triggering the sender's same-block restriction
        vm.startPrank(alice, alice);
        token.transfer(bob, 100 * WAD);
        token.transfer(charlie, 100 * WAD);
        vm.stopPrank();
    }

    function test_whitelisted_receiver_bypasses_restrictions() public {
        // Whitelist Bob
        vm.prank(dao);
        token.setWhitelist(bob, true);

        address charlie = makeAddr("charlie");
        token.transfer(charlie, 1000 * WAD);

        // Multiple senders can transfer to Bob in the same block
        vm.prank(alice, alice);
        token.transfer(bob, 100 * WAD);

        vm.prank(charlie, charlie);
        bool success = token.transfer(bob, 100 * WAD);
        assertTrue(success);
    }

    // ── 4. Mint Tests ──

    function test_system_contract_mint_succeeds() public {
        vm.prank(systemContract);
        token.mint(alice, 500 * WAD);
        assertEq(token.balanceOf(alice), 10_500 * WAD);
    }

    function test_non_system_mint_fails() public {
        vm.prank(alice);
        vm.expectRevert(Err_NotSystemContract.selector);
        token.mint(alice, 500 * WAD);
    }
}

contract SimpleReceiver {
    InfinitySixToken public token;

    constructor(address _t) {
        token = InfinitySixToken(_t);
    }

    function forwardTokens(address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}
