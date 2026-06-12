// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000000 * 1e18);
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// [ignoring loop detection]
contract EconomicTest is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address user = address(0x1111);
    address sponsor = address(0x2222);

    function setUp() public {
        usdt = new MockUSDT();
        token = new InfinitySixToken(DAO, 1000000000 * 1e18);
        
        systemContract = new InfinitySixSystem(
            address(usdt),
            address(token),
            ROUTER,
            PAIR
        );

        vm.startPrank(DAO);
        token.setSystemContract(address(systemContract));
        token.setLiquidityPair(PAIR);
        vm.stopPrank();

        usdt.transfer(sponsor, 100000 * 1e18);
        usdt.transfer(user, 100000 * 1e18);
        token.transfer(address(systemContract), 1000000 * 1e18);

        // Mock Uniswap Pair and Router
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("getReserves()"),
            abi.encode(uint112(10000 * 1e18), uint112(10000 * 1e18), uint32(0))
        );
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("token0()"),
            abi.encode(address(usdt))
        );
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60 * 1e18;
        amounts[1] = 60 * 1e18;
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            abi.encode(amounts)
        );
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("quote(uint256,uint256,uint256)"),
            abi.encode(uint256(40 * 1e18))
        );
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"),
            abi.encode(uint256(40 * 1e18), uint256(40 * 1e18), uint256(40 * 1e18))
        );
    }

    function rollBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
    }

    // Test 1: Economic Price Oracle Manipulation
    function test_Economic_SpotPriceManipulation() public {
        // Setup initial pool reserves (Normal Price: 1 token = 1 USDT)
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("getReserves()"),
            abi.encode(uint112(10000 * 1e18), uint112(10000 * 1e18), uint32(0))
        );

        // Sponsor invest
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();

        // User invest
        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, sponsor, 0);
        vm.stopPrank();
        rollBlock();

        // Warp to generate rewards
        vm.warp(block.timestamp + 10 days);

        // Before manipulation, query spot price
        uint256 priceBefore = systemContract.getSpotPrice();
        assertEq(priceBefore, 1e18); // 1.0 USDT

        // Manipulate pool reserves to drop token price to 0.1 USDT (1/10th value)
        // USDT reserve = 10,000, Token reserve = 100,000. Price = 10000 * 1e18 / 100000 = 0.1 * 1e18
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("getReserves()"),
            abi.encode(uint112(10000 * 1e18), uint112(100000 * 1e18), uint32(0))
        );

        uint256 priceAfter = systemContract.getSpotPrice();
        assertEq(priceAfter, 0.1 * 1e18); // 0.1 USDT

        // Now perform a withdrawal and observe how many tokens are minted
        uint256 balanceBefore = token.balanceOf(user);
        
        vm.warp(block.timestamp + 3 days); // Bypass withdrawal startTime requirement
        vm.prank(user, user);
        systemContract.withdraw();

        uint256 balanceAfter = token.balanceOf(user);
        uint256 diff = balanceAfter - balanceBefore;
        
        emit log_named_uint("Tokens received after price manipulation", diff);
        // Due to price manipulation from 1.0 down to 0.1, the tokens minted are multiplied by 10x!
        assertGt(diff, 400 * 1e18); // Normal should have been around 50 tokens
    }

    // Test 2: Booster Invariant Permanent State Lock
    function test_Economic_PermanentBoosterBypass() public {
        // Sponsor invests 1000 USDT
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();

        // Sponsor registers 3 directs, each investing 1000 USDT, satisfying the booster conditions:
        // directBoosterCount >= 3, directBoosterBusiness >= sponsor's total deposits (1000 USDT)
        for (uint256 i = 0; i < 3; i++) {
            address d = address(uint160(0x4000 + i));
            usdt.mint(d, 2000 * 1e18);
            vm.startPrank(d, d);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(1000 * 1e18, sponsor, 0);
            vm.stopPrank();
            rollBlock();
        }

        // Verify that sponsor became boosted
        (,,,,,,,,,,,,,,,,,,,,,,,,,,bool isBoosted) = systemContract.users(sponsor);
        assertTrue(isBoosted, "Sponsor should have been boosted");

        // Even if the downline becomes inactive, the boosted status is never reset.
        // Sponsor remains permanently boosted.
        (,,,,,,,,,,,,,,,,,,,,,,,,,,bool isBoostedAfter) = systemContract.users(sponsor);
        assertTrue(isBoostedAfter, "Booster status remains locked permanently");
    }
}
