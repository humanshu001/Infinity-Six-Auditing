// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseFork.t.sol";

contract AccessControlTest is BaseForkSetup {

    function test_MainnetStateIsCorrect()
        public
    {
        assertEq(
            token.systemContract(),
            SYSTEM
        );

        assertEq(
            token.liquidityPair(),
            PAIR
        );

        assertEq(
            token.buyingEnabled(),
            false
        );
    }

    function test_AttackerCannotSetSystem()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.setSystemContract(
            attacker
        );

        vm.stopPrank();
    }

    function test_AttackerCannotSetPair()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.setLiquidityPair(
            attacker
        );

        vm.stopPrank();
    }

    function test_AttackerCannotWhitelist()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.setWhitelist(
            attacker,
            true
        );

        vm.stopPrank();
    }

    function test_AttackerCannotDisableBuying()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.disableBuying();

        vm.stopPrank();
    }

    function test_AttackerCannotUpdateDAO()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.updateDAOMultisigController(
            attacker
        );

        vm.stopPrank();
    }

    function test_AttackerCannotMint()
        public
    {
        vm.startPrank(attacker);

        vm.expectRevert();

        token.mint(
            attacker,
            100 ether
        );

        vm.stopPrank();
    }

    function test_DAOAddressStoredCorrectly()
        public
    {
        assertEq(
            token.DAOMultisigController(),
            DAO
        );
    }

    function test_OldDAOCannotCallAfterDAOUpdate()
        public
    {
        // DAO updates to a new controller
        address newDao = address(0xBEEF0001);

        vm.prank(DAO);
        token.updateDAOMultisigController(newDao);

        // original DAO should no longer be able to call DAO-only functions
        vm.startPrank(DAO);
        vm.expectRevert();
        token.setWhitelist(address(0x1111), true);
        vm.stopPrank();
    }

    function test_DAOUpdatesItselfRepeatedly()
        public
    {
        // DAO can set the controller to itself (no-op) and change back-and-forth
        vm.prank(DAO);
        token.updateDAOMultisigController(DAO);

        vm.prank(DAO);
        token.updateDAOMultisigController(attacker);

        // new controller can set it back
        vm.prank(attacker);
        token.updateDAOMultisigController(DAO);
    }

    function test_DAOCannotSetZeroAddress()
        public
    {
        vm.prank(DAO);
        vm.expectRevert();
        token.updateDAOMultisigController(address(0));
    }

    function test_DAOCanSetSystemToArbitraryAddress()
        public
    {
        vm.prank(DAO);
        token.setSystemContract(attacker);
        assertEq(token.systemContract(), attacker);
    }

    function test_PreviouslyWhitelistedAccountToggle()
        public
    {
        // DAO grants and then revokes whitelist
        vm.prank(DAO);
        token.setWhitelist(attacker, true);
        assertEq(token.isWhitelisted(attacker), true);

        vm.prank(DAO);
        token.setWhitelist(attacker, false);
        assertEq(token.isWhitelisted(attacker), false);
    }
}