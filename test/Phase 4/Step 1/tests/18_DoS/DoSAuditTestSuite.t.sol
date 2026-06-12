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

contract DoSAuditTestSuite is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address userBase = address(0xAA00);
    uint256 currentBlock = 100;

    function rollBlock() internal {
        currentBlock++;
        vm.roll(currentBlock);
        vm.warp(block.timestamp + 10);
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

        usdt.transfer(ORIGIN, 100000 * 1e18);
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

    // Helper to fund and approve USDT for a user
    function _fundAndApprove(address user, uint256 amount) internal {
        usdt.mint(user, amount);
        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        vm.stopPrank();
    }

    // Helper to build a referral chain
    function _buildChain(uint256 depth) internal returns (address[] memory) {
        address[] memory chain = new address[](depth);
        address currentSponsor = ORIGIN;

        for (uint256 i = 0; i < depth; i++) {
            address user = address(uint160(0x90000 + i));
            _fundAndApprove(user, 200 * 1e18);

            vm.startPrank(user, user);
            systemContract.invest(100 * 1e18, currentSponsor, 0);
            vm.stopPrank();

            chain[i] = user;
            currentSponsor = user;
            rollBlock();
        }
        return chain;
    }

    // ==========================================
    // 1. Gas Benchmark Tests
    // ==========================================

    function test_Gas_Depth10() public {
        address[] memory chain = _buildChain(10);
        address testUser = address(0xAA10);
        _fundAndApprove(testUser, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, chain[9], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for depth 10 investment", gasUsed);
    }

    function test_Gas_Depth50() public {
        address[] memory chain = _buildChain(50);
        address testUser = address(0xAA50);
        _fundAndApprove(testUser, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, chain[49], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for depth 50 investment", gasUsed);
    }

    function test_Gas_Depth100() public {
        address[] memory chain = _buildChain(100);
        address testUser = address(0xAA100);
        _fundAndApprove(testUser, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, chain[99], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for depth 100 investment", gasUsed);
    }

    function test_Gas_Depth500() public {
        address[] memory chain = _buildChain(500);
        address testUser = address(0xAA500);
        _fundAndApprove(testUser, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, chain[499], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for depth 500 investment", gasUsed);
    }

    function test_Gas_Depth1000() public {
        address[] memory chain = _buildChain(1000);
        address testUser = address(0xAA1000);
        _fundAndApprove(testUser, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, chain[999], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for depth 1000 investment", gasUsed);
    }

    // ==========================================
    // 2. Scalability & Referral Tree DoS
    // ==========================================

    function test_Scalability_100_Referrals() public {
        address sponsor = address(0x100001);
        _fundAndApprove(sponsor, 1000 * 1e18);
        vm.prank(sponsor, sponsor);
        systemContract.invest(100 * 1e18, ORIGIN, 0);

        for (uint256 i = 0; i < 99; i++) {
            address referee = address(uint160(0x200000 + i));
            _fundAndApprove(referee, 200 * 1e18);
            vm.prank(referee, referee);
            systemContract.invest(100 * 1e18, sponsor, 0);
            rollBlock();
        }

        address testUser = address(0x200999);
        _fundAndApprove(testUser, 200 * 1e18);
        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, sponsor, 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for invest at 100 referrals", gasUsed);
    }

    function test_Scalability_500_Referrals() public {
        address sponsor = address(0x100002);
        _fundAndApprove(sponsor, 1000 * 1e18);
        vm.prank(sponsor, sponsor);
        systemContract.invest(100 * 1e18, ORIGIN, 0);

        // Build a hierarchy using multiple directs under the sponsor to reach 500 total referrals
        address[] memory directs = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            directs[i] = address(uint160(0x300000 + i));
            _fundAndApprove(directs[i], 1000 * 1e18);
            vm.prank(directs[i], directs[i]);
            systemContract.invest(100 * 1e18, sponsor, 0);
            rollBlock();
        }

        for (uint256 i = 0; i < 100; i++) {
            for (uint256 j = 0; j < 4; j++) {
                address leaf = address(uint160(0x400000 + i * 4 + j));
                _fundAndApprove(leaf, 200 * 1e18);
                vm.prank(leaf, leaf);
                systemContract.invest(100 * 1e18, directs[i], 0);
                rollBlock();
            }
        }

        address testUser = address(0x499999);
        _fundAndApprove(testUser, 200 * 1e18);
        uint256 gasBefore = gasleft();
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, directs[0], 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for invest at 500 referrals", gasUsed);
    }

    // ==========================================
    // 3. Investment Array DoS
    // ==========================================

    function test_InvestmentArray_DoS() public {
        address testUser = address(0x500001);
        _fundAndApprove(testUser, 20000 * 1e18);

        // Make 99 investments
        for (uint256 i = 0; i < 99; i++) {
            vm.prank(testUser, testUser);
            systemContract.invest(100 * 1e18, ORIGIN, 0);
            rollBlock();
        }

        // 100th investment should succeed
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, ORIGIN, 0);
        rollBlock();

        // 101st investment must revert
        _fundAndApprove(testUser, 200 * 1e18);
        vm.expectRevert(abi.encodeWithSignature("Err_MaxInvestmentsAllowed()"));
        vm.prank(testUser, testUser);
        systemContract.invest(100 * 1e18, ORIGIN, 0);
    }

    // ==========================================
    // 4. Worst Case Withdrawal Test
    // ==========================================

    function test_WorstCase_Withdrawal() public {
        address sponsor = address(0x600001);
        _fundAndApprove(sponsor, 1000 * 1e18);
        vm.prank(sponsor, sponsor);
        systemContract.invest(100 * 1e18, ORIGIN, 0);

        // Register directs to max (199 directs)
        for (uint256 i = 0; i < 199; i++) {
            address d = address(uint160(0x700000 + i));
            _fundAndApprove(d, 200 * 1e18);
            vm.prank(d, d);
            systemContract.invest(100 * 1e18, sponsor, 0);
            rollBlock();
        }

        // Fill user's own investments to 100
        _fundAndApprove(sponsor, 10000 * 1e18);
        for (uint256 i = 0; i < 99; i++) {
            vm.prank(sponsor, sponsor);
            systemContract.invest(100 * 1e18, ORIGIN, 0);
            rollBlock();
        }

        // Fast forward time to accumulate ROI/rewards
        vm.warp(block.timestamp + 30 days);

        uint256 gasBefore = gasleft();
        vm.prank(sponsor, sponsor);
        systemContract.withdraw();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas used for worst-case withdrawal", gasUsed);
    }

    // ==========================================
    // 5. Gas Griefing Attacks
    // ==========================================

    function test_GasGriefing_AttackerDirects() public {
        address sponsor = address(0x800001);
        _fundAndApprove(sponsor, 1000 * 1e18);
        vm.prank(sponsor, sponsor);
        systemContract.invest(100 * 1e18, ORIGIN, 0);

        // Attacker registers directs under sponsor to increase search complexity
        for (uint256 i = 0; i < 100; i++) {
            address direct = address(uint160(0x900000 + i));
            _fundAndApprove(direct, 200 * 1e18);
            vm.prank(direct, direct);
            systemContract.invest(100 * 1e18, sponsor, 0);
            rollBlock();
        }

        // Measure gas cost for sponsor's auto-rank traversal
        address newDirect = address(0x999999);
        _fundAndApprove(newDirect, 200 * 1e18);

        uint256 gasBefore = gasleft();
        vm.prank(newDirect, newDirect);
        systemContract.invest(100 * 1e18, sponsor, 0);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas cost of invest under sponsor with 100 directs", gasUsed);
    }
}
