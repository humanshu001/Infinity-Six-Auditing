// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";
import "../BaseFork.t.sol";

contract MockMaliciousPair {
    function getReserves() external pure returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (0, 0, 0);
    }
    function token0() external pure returns (address) {
        return address(0);
    }
}

contract LiquidityTest is BaseForkSetup {
    IERC20 usdt = IERC20(USDT);
    InfinitySixSystem realSystem;
    InfinitySixToken realToken;

    error Err_DAOMultiSignRequired();
    error Err_InvalidAddress();
    error Err_NoLiquidity();

    function setUp() public override {
        super.setUp();
        realSystem = InfinitySixSystem(SYSTEM);
        realToken = InfinitySixToken(TOKEN);
    }

    function test_dao_sets_pair_and_router_succeeds() public {
        address newPair = address(0x1111);
        address newRouter = address(0x2222);

        address dao = realSystem.DAOMultisigController();

        vm.startPrank(dao);
        realSystem.setTradingPair(newPair);
        realSystem.setDexRouter(newRouter);
        vm.stopPrank();

        assertEq(realSystem.uniswapPair(), newPair, "Pair not set correctly");
        assertEq(address(realSystem.dexRouter()), newRouter, "Router not set correctly");
    }

    function test_non_dao_sets_pair_and_router_reverts() public {
        address newPair = address(0x1111);
        address newRouter = address(0x2222);

        vm.startPrank(attacker);
        
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        realSystem.setTradingPair(newPair);

        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        realSystem.setDexRouter(newRouter);
        
        vm.stopPrank();
    }

    function test_set_zero_address_reverts() public {
        address dao = realSystem.DAOMultisigController();

        vm.startPrank(dao);
        
        vm.expectRevert(Err_InvalidAddress.selector);
        realSystem.setTradingPair(address(0));

        vm.expectRevert(Err_InvalidAddress.selector);
        realSystem.setDexRouter(address(0));
        
        vm.stopPrank();
    }

    function test_get_spot_price_reverts_on_zero_liquidity() public {
        address dao = realSystem.DAOMultisigController();
        MockMaliciousPair mockPair = new MockMaliciousPair();

        vm.prank(dao);
        realSystem.setTradingPair(address(mockPair));

        // Attempting to query getSpotPrice should revert with Err_NoLiquidity
        vm.expectRevert(Err_NoLiquidity.selector);
        realSystem.getSpotPrice();
    }
}

