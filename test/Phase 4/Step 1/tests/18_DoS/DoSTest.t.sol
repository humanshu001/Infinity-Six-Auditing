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
contract DoSTest is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address attacker = address(0x1111);
    uint256 currentBlock = 100;

    function rollBlock() internal {
        currentBlock++;
        vm.roll(currentBlock);
    }

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

        usdt.transfer(attacker, 100000 * 1e18);
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

    function _buildChain(uint256 depth) internal returns (address[] memory) {
        address[] memory chain = new address[](depth);
        chain[0] = attacker;

        rollBlock();
        vm.startPrank(attacker, attacker);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        for (uint256 i = 1; i < depth; i++) {
            address user = address(uint160(0x2000 + (depth * 100) + i));
            rollBlock();
            vm.prank(attacker, attacker);
            usdt.transfer(user, 200 * 1e18);

            rollBlock();
            vm.startPrank(user, user);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, chain[i - 1], 0);
            vm.stopPrank();

            chain[i] = user;
        }

        return chain;
    }

    function test_dos_varying_depths_gas_usage() public {
        // Test depth 10
        address[] memory chain10 = _buildChain(10);
        address user10 = address(0x9010);
        rollBlock();
        usdt.transfer(user10, 200 * 1e18);
        rollBlock();
        vm.startPrank(user10, user10);
        usdt.approve(address(systemContract), type(uint256).max);
        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, chain10[9], 0);
        uint256 gasUsed10 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint("Gas used for investment at 10 levels depth", gasUsed10);

        // Test depth 30
        address[] memory chain30 = _buildChain(30);
        address user30 = address(0x9030);
        rollBlock();
        usdt.transfer(user30, 200 * 1e18);
        rollBlock();
        vm.startPrank(user30, user30);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, chain30[29], 0);
        uint256 gasUsed30 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint("Gas used for investment at 30 levels depth", gasUsed30);

        // Test depth 50
        address[] memory chain50 = _buildChain(50);
        address user50 = address(0x9050);
        rollBlock();
        usdt.transfer(user50, 200 * 1e18);
        rollBlock();
        vm.startPrank(user50, user50);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, chain50[49], 0);
        uint256 gasUsed50 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint("Gas used for investment at 50 levels depth", gasUsed50);

        // Assert gas usage grows linearly
        assertGt(gasUsed50, gasUsed30, "Gas usage should grow with depth");
        assertGt(gasUsed30, gasUsed10, "Gas usage should grow with depth");
    }

    function test_dos_max_investment_gas() public {
        address[] memory chain = _buildChain(20);
        
        // Invest minimum investment (100 USDT)
        address userMin = address(0x8001);
        rollBlock();
        usdt.transfer(userMin, 200 * 1e18);
        rollBlock();
        vm.startPrank(userMin, userMin);
        usdt.approve(address(systemContract), type(uint256).max);
        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, chain[19], 0);
        uint256 gasUsedMin = gasStart - gasleft();
        vm.stopPrank();

        // Invest maximum investment (20000 USDT)
        address userMax = address(0x8002);
        rollBlock();
        usdt.transfer(userMax, 30000 * 1e18);
        rollBlock();
        vm.startPrank(userMax, userMax);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(20000 * 1e18, chain[19], 0);
        uint256 gasUsedMax = gasStart - gasleft();
        vm.stopPrank();

        emit log_named_uint("Gas used for minimum investment (100 USDT)", gasUsedMin);
        emit log_named_uint("Gas used for maximum investment (20000 USDT)", gasUsedMax);
    }

    function test_dos_unfilled_vs_filled_referral_slots() public {
        uint256 depth = 15;
        // Build active chain first
        address[] memory chain = _buildChain(depth);

        // For each referrer in the chain, we fill their slots with 5 extra direct referrals
        for (uint256 i = 0; i < depth; i++) {
            address referrer = chain[i];
            for (uint256 d = 0; d < 5; d++) {
                address directUser = address(uint160(0x7000 + i * 10 + d));
                rollBlock();
                vm.prank(attacker);
                usdt.transfer(directUser, 200 * 1e18);
                
                rollBlock();
                vm.startPrank(directUser, directUser);
                usdt.approve(address(systemContract), type(uint256).max);
                systemContract.invest(100 * 1e18, referrer, 0);
                vm.stopPrank();
            }
        }

        // Invest at the bottom of the chain
        address bottomUser = address(0x9900);
        rollBlock();
        vm.prank(attacker);
        usdt.transfer(bottomUser, 200 * 1e18);
        
        rollBlock();
        vm.startPrank(bottomUser, bottomUser);
        usdt.approve(address(systemContract), type(uint256).max);

        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, chain[depth - 1], 0);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit log_named_uint("Gas used for investment at 15 levels depth with filled slots", gasUsed);
    }

    function _registerDirects(address referrer, uint256 count, uint256 startId) internal {
        usdt.mint(attacker, count * 200 * 1e18);

        for (uint256 i = 0; i < count; i++) {
            address directUser = address(uint160(startId + i));
            rollBlock();
            vm.prank(attacker, attacker);
            usdt.transfer(directUser, 200 * 1e18);

            rollBlock();
            vm.startPrank(directUser, directUser);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, referrer, 0);
            vm.stopPrank();
        }
    }

    function _runVaryingSlotsForDepth(uint256 depth, uint256 startAddrOffset) internal {
        usdt.mint(attacker, depth * 200 * 1e18 + 1000000 * 1e18);
        address[] memory chain = _buildChain(depth);
        address immediateReferrer = chain[depth - 1];

        // 0 slots
        address bottomUser0 = address(uint160(startAddrOffset + 0));
        rollBlock();
        usdt.mint(bottomUser0, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser0, bottomUser0);
        usdt.approve(address(systemContract), type(uint256).max);
        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas0 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 0 slots")), gas0);

        // 20 slots
        _registerDirects(immediateReferrer, 20, startAddrOffset + 100);
        address bottomUser20 = address(uint160(startAddrOffset + 20));
        rollBlock();
        usdt.mint(bottomUser20, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser20, bottomUser20);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas20 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 20 slots")), gas20);

        // 40 slots
        _registerDirects(immediateReferrer, 20, startAddrOffset + 200);
        address bottomUser40 = address(uint160(startAddrOffset + 40));
        rollBlock();
        usdt.mint(bottomUser40, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser40, bottomUser40);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas40 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 40 slots")), gas40);

        // 60 slots
        _registerDirects(immediateReferrer, 20, startAddrOffset + 300);
        address bottomUser60 = address(uint160(startAddrOffset + 60));
        rollBlock();
        usdt.mint(bottomUser60, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser60, bottomUser60);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas60 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 60 slots")), gas60);

        // 80 slots
        _registerDirects(immediateReferrer, 20, startAddrOffset + 400);
        address bottomUser80 = address(uint160(startAddrOffset + 80));
        rollBlock();
        usdt.mint(bottomUser80, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser80, bottomUser80);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas80 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 80 slots")), gas80);

        // 100 slots
        _registerDirects(immediateReferrer, 20, startAddrOffset + 500);
        address bottomUser100 = address(uint160(startAddrOffset + 1000));
        rollBlock();
        usdt.mint(bottomUser100, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser100, bottomUser100);
        usdt.approve(address(systemContract), type(uint256).max);
        gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gas100 = gasStart - gasleft();
        vm.stopPrank();
        emit log_named_uint(string(abi.encodePacked("Gas used for ", vm.toString(depth), " levels with 100 slots")), gas100);
    }

    function test_dos_100_levels_varying_slots() public {
        _runVaryingSlotsForDepth(100, 0x100000);
    }

    function test_dos_300_levels_varying_slots() public {
        _runVaryingSlotsForDepth(300, 0x300000);
    }

    function test_dos_500_levels_varying_slots() public {
        _runVaryingSlotsForDepth(500, 0x500000);
    }

    function test_dos_700_levels_varying_slots() public {
        _runVaryingSlotsForDepth(700, 0x700000);
    }

    function test_dos_1000_levels_200_slots() public {
        usdt.mint(attacker, 1000 * 200 * 1e18 + 2000000 * 1e18);
        address[] memory chain = _buildChain(1000);
        address immediateReferrer = chain[999];

        // Fill referrer's investments to 99 entries
        usdt.mint(immediateReferrer, 98 * 100 * 1e18);
        for (uint256 j = 0; j < 98; j++) {
            rollBlock();
            vm.startPrank(immediateReferrer, immediateReferrer);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, chain[998], 0);
            vm.stopPrank();
        }

        // Register 199 directs to immediate referrer
        _registerDirects(immediateReferrer, 199, 0x1000000);

        // Fill bottom user's investments to 99 entries
        address bottomUser = address(0x2000000);
        usdt.mint(bottomUser, 100 * 100 * 1e18);
        for (uint256 j = 0; j < 99; j++) {
            rollBlock();
            vm.startPrank(bottomUser, bottomUser);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, immediateReferrer, 0);
            vm.stopPrank();
        }

        // Measure the 100th investment of the bottom user
        rollBlock();
        vm.startPrank(bottomUser, bottomUser);
        usdt.approve(address(systemContract), type(uint256).max);

        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit log_named_uint("Gas used for absolute maximum 1000 levels with 200 slots and 100 investment packages", gasUsed);
    }

    function test_dos_1000_levels_200_slots_new_direct() public {
        usdt.mint(attacker, 1000 * 200 * 1e18 + 2000000 * 1e18);
        address[] memory chain = _buildChain(1000);
        address immediateReferrer = chain[999];

        // Fill referrer's investments to 100 entries (99 additional + 1 genesis)
        usdt.mint(immediateReferrer, 99 * 100 * 1e18);
        for (uint256 j = 0; j < 99; j++) {
            rollBlock();
            vm.startPrank(immediateReferrer, immediateReferrer);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, chain[998], 0);
            vm.stopPrank();
        }

        // Register 199 directs to immediate referrer
        _registerDirects(immediateReferrer, 199, 0x1000000);

        // Bottom user registers as the 200th direct (first investment)
        address bottomUser = address(0x2000000);
        rollBlock();
        usdt.mint(bottomUser, 200 * 1e18);
        rollBlock();
        vm.startPrank(bottomUser, bottomUser);
        usdt.approve(address(systemContract), type(uint256).max);

        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, immediateReferrer, 0);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();

        emit log_named_uint("Gas used for absolute maximum 1000 levels with 200 slots (new direct, referrer 100 packages)", gasUsed);
    }
}



