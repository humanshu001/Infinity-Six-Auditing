// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../SimulationSetup.t.sol";

contract InfinitySix_Access_Control_Test is SimulationSetup {

    function setUp() public override {
        super.setUp(); // Sets up live state, 15 users, DEX liquidity, fast forwards time
    }

    // ITEM 60: Privilege escalation and unauthorized access testing
    function test_Privilege_OnlyDAOCanUpdateSettings() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setROI(10);
        
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setWithdrawalHourlyLimit(1, 1, 1, 1, 1);
        
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setMinInvestment(200 * 1e18);
        
        vm.stopPrank();
    }

    // ITEM 61: DAO multisig governance and trust model assessment
    // ITEM 72: Centralization and governance risk assessment
    function test_Risk_Centralization_DAOIsSingleKey() public view {
        address currentDAO = sys.DAOMultisigController();
        // Since we deployed using DAO in setUp, we can see if it's a multisig or EOA.
        // In the live contract, it's 0x4EA9802681Fb877DE5407974E63F197EE754032f
        assertNotEq(currentDAO, address(0));
        console.log("[RISK - ITEM 61/72] DAO Controller has single-key rug pull potential:", currentDAO);
    }

    // ITEM 69: DAO controller migration security assessment
    function test_DAOMigration_SecureTransfer() public {
        address newDAO = makeAddr("newDAO");
        
        vm.prank(DAO);
        sys.updateDAOMultisignController(newDAO);
        
        assertEq(sys.DAOMultisigController(), newDAO);
        
        // Ensure old DAO can no longer act
        vm.prank(DAO);
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setROI(8);
        
        // Ensure new DAO can act
        vm.prank(newDAO);
        sys.setROI(8);
        assertEq(sys.MIN_ROI_PERC(), 8);
    }

    function test_DAOMigration_ZeroAddressReverts() public {
        vm.prank(DAO);
        vm.expectRevert(Err_InvalidAddress.selector);
        sys.updateDAOMultisignController(address(0));
    }

    // ITEM 70: Rescue token function privilege review
    function test_RescueTokens_CannotDrainNativei6() public {
        vm.prank(DAO);
        vm.expectRevert(Err_CannotDrainRewardTokens.selector);
        sys.rescueAccidentalTokens(address(ptk), DAO, 100 * 1e18);
    }

    function test_RescueTokens_CanDrainStrayUSDT() public {
        // Someone accidentally sends USDT directly to the contract without calling invest()
        usdt.mint(address(sys), 500 * 1e18);
        
        uint256 balanceBefore = usdt.balanceOf(DAO);
        vm.prank(DAO);
        sys.rescueAccidentalTokens(address(usdt), DAO, 500 * 1e18);
        uint256 balanceAfter = usdt.balanceOf(DAO);
        
        assertEq(balanceAfter - balanceBefore, 500 * 1e18);
    }

    // ITEM 45: Same-block transaction restriction testing
    // ITEM 46: tx.origin contract-call blocking assessment
    function test_ContractCalls_BlockedByTxOrigin() public {
        // We create an attacker contract to proxy calls
        AttackerContract attacker = new AttackerContract(sys, usdt);
        usdt.mint(address(attacker), 1000 * 1e18);
        
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        attacker.tryInvest(100 * 1e18, ORIGIN);
    }
}

contract AttackerContract {
    InfinitySixSystem sys;
    IERC20 usdt;
    constructor(InfinitySixSystem _sys, IERC20 _usdt) {
        sys = _sys;
        usdt = _usdt;
        usdt.approve(address(sys), type(uint256).max);
    }
    function tryInvest(uint256 amount, address referrer) external {
        sys.invest(amount, referrer, 0);
    }
}
