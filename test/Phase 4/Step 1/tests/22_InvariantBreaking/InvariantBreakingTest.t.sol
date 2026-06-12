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
contract InvariantBreakingTest is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address sponsor = address(0x2222);
    address user = address(0x1111);

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

    // Invariant: Uncapped Minting and Total Supply Hyper-Inflation
    function test_Invariant_SupplyHyperInflation() public {
        // Setup initial investment
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();

        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, sponsor, 0);
        vm.stopPrank();
        rollBlock();

        vm.warp(block.timestamp + 10 days);

        // Manipulate spot price to be extremely small (100 wei)
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("getReserves()"),
            abi.encode(uint112(1 * 1e18), uint112(10000000000 * 1e18), uint32(0)) // 1 USDT / 10 billion tokens -> price = 100 wei
        );

        uint256 supplyBefore = token.totalSupply();
        emit log_named_uint("Token Supply Before Withdrawal", supplyBefore);

        vm.warp(block.timestamp + 3 days); // Bypass time constraint
        vm.prank(user, user);
        systemContract.withdraw();

        uint256 supplyAfter = token.totalSupply();
        emit log_named_uint("Token Supply After Withdrawal", supplyAfter);

        // Verify that the token supply invariant has been broken by inflating the supply over 10x
        assertGt(supplyAfter - supplyBefore, supplyBefore * 10);
    }

    // Invariant: Strict referral acyclic graph check
    function test_Invariant_ReferralGraphAcyclic() public {
        // Setup sponsor active
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();

        // Try to register user under sponsor
        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, sponsor, 0);
        vm.stopPrank();
        rollBlock();

        // Verify that referrer of user is sponsor
        (,,,,,,,,,,,,,,,,,,,address ref,,,,,,,) = systemContract.users(user);
        assertEq(ref, sponsor);

        // Now, try to register sponsor under user (create a loop)
        // Since sponsor is already active and registered, their referrer cannot be changed.
        // If a new address tries to register under an inactive sponsor, it fails.
        // Let's verify we cannot refer ourselves or create loops
        address badUser = address(0x9999);
        vm.startPrank(badUser, badUser);
        usdt.approve(address(systemContract), type(uint256).max);
        vm.expectRevert(bytes4(keccak256("Err_CannotReferYourself()")));
        systemContract.invest(1000 * 1e18, badUser, 0);
        vm.stopPrank();
    }
}
