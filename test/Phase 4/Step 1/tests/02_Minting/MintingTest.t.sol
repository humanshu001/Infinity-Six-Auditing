// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseFork.t.sol";

contract MintingTest is BaseForkSetup {

    function test_TotalSupplyExists()
        public
    {
        assertGt(
            token.totalSupply(),
            0
        );
    }

    function test_AttackerCannotMint()
        public
    {
        uint256 beforeSupply =
            token.totalSupply();

        vm.startPrank(attacker);

        vm.expectRevert();

        token.mint(
            attacker,
            1e18
        );

        vm.stopPrank();

        assertEq(
            token.totalSupply(),
            beforeSupply
        );
    }

    function test_DAOCannotMintDirectly()
        public
    {
        uint256 beforeSupply =
            token.totalSupply();

        vm.startPrank(DAO);

        vm.expectRevert();

        token.mint(
            DAO,
            100 ether
        );

        vm.stopPrank();

        assertEq(
            token.totalSupply(),
            beforeSupply
        );
    }

    function test_SystemAddressConfigured()
        public
    {
        assertEq(
            token.systemContract(),
            SYSTEM
        );
    }

    function test_SupplyPositive()
        public
    {
        uint256 supply =
            token.totalSupply();

        assertGt(
            supply,
            0
        );
    }

    function test_BuyingDisabled()
        public
    {
        assertEq(
            token.buyingEnabled(),
            false
        );
    }

    function test_SystemCanMint()
        public
    {
        uint256 before = token.totalSupply();

        vm.prank(SYSTEM);
        token.mint(attacker, 1 ether);

        assertGt(token.totalSupply(), before);
    }

    function test_MintMaxUintReverts()
        public
    {
        vm.prank(SYSTEM);
        vm.expectRevert();
        token.mint(attacker, type(uint256).max);
    }

    function test_MintToZeroReverts()
        public
    {
        vm.prank(SYSTEM);
        vm.expectRevert();
        token.mint(address(0), 1 ether);
    }

    function test_PreviousSystemCannotMintAfterChange()
        public
    {
        // DAO transfers system to attacker
        vm.prank(DAO);
        token.setSystemContract(attacker);

        // original SYSTEM should no longer be able to mint
        vm.prank(SYSTEM);
        vm.expectRevert();
        token.mint(attacker, 1 ether);
    }
}