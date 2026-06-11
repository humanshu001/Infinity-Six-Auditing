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
contract StorageBloatTest is Test {
    MockUSDT usdt;

    function setUp() public {
        usdt = new MockUSDT();
    }

    // ==========================================
    // 1. Directs Scaling (claimRank)
    // ==========================================

    function test_storage_bloat_claim_rank_scaling() public {
        uint256[5] memory counts = [uint256(10), 50, 100, 150, 200];
        
        for (uint256 idx = 0; idx < counts.length; idx++) {
            uint256 count = counts[idx];
            
            StorageBloatSandbox sandbox = new StorageBloatSandbox(address(usdt));
            usdt.transfer(address(sandbox), 100000 * 1e18);
            
            uint256 gasUsed = sandbox.measureClaimRank(count);
            emit log_named_uint(string(abi.encodePacked("Gas used for claimRank with ", vm.toString(count), " directs")), gasUsed);
        }
    }

    // ==========================================
    // 2. Directs Scaling (invest under sponsor with N directs)
    // ==========================================

    function test_storage_bloat_invest_scaling() public {
        uint256[5] memory counts = [uint256(10), 50, 100, 150, 199];
        
        for (uint256 idx = 0; idx < counts.length; idx++) {
            uint256 count = counts[idx];
            
            StorageBloatSandbox sandbox = new StorageBloatSandbox(address(usdt));
            usdt.transfer(address(sandbox), 100000 * 1e18);
            
            uint256 gasUsed = sandbox.measureNewInvest(count);
            emit log_named_uint(string(abi.encodePacked("Gas used for new invest under sponsor with ", vm.toString(count), " directs")), gasUsed);
        }
    }

    // ==========================================
    // 3. Investments Scaling (withdraw with N investments)
    // ==========================================

    function test_storage_bloat_withdraw_investments_scaling() public {
        uint256[4] memory counts = [uint256(1), 10, 50, 100];
        
        for (uint256 idx = 0; idx < counts.length; idx++) {
            uint256 count = counts[idx];
            
            StorageBloatSandbox sandbox = new StorageBloatSandbox(address(usdt));
            usdt.transfer(address(sandbox), 100000 * 1e18);
            
            uint256 gasUsed = sandbox.measureWithdraw(count);
            emit log_named_uint(string(abi.encodePacked("Gas used for withdraw with ", vm.toString(count), " investments")), gasUsed);
        }
    }

    // ==========================================
    // 4. Pending Direct Bonuses Scaling
    // ==========================================

    function test_storage_bloat_pending_bonuses_scaling() public {
        uint256[4] memory counts = [uint256(5), 25, 50, 100];
        
        for (uint256 idx = 0; idx < counts.length; idx++) {
            uint256 count = counts[idx];
            
            StorageBloatSandbox sandbox = new StorageBloatSandbox(address(usdt));
            usdt.transfer(address(sandbox), 100000 * 1e18);
            
            uint256 gasUsed = sandbox.measurePendingBonusProcessing(count);
            emit log_named_uint(string(abi.encodePacked("Gas used to process ", vm.toString(count), " pending direct bonuses")), gasUsed);
        }
    }
}

// [ignoring loop detection]
contract StorageBloatSandbox is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address sponsor = address(0xAAAA);

    constructor(address _usdt) {
        usdt = MockUSDT(_usdt);
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

    function _setupSponsor() internal {
        usdt.mint(sponsor, 100000 * 1e18);
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(500 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();
    }

    function measureClaimRank(uint256 directCount) external returns (uint256) {
        _setupSponsor();
        
        for (uint256 i = 0; i < directCount; i++) {
            address referee = address(uint160(0x5000 + i));
            usdt.mint(referee, 200 * 1e18);
            vm.startPrank(referee, referee);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, sponsor, 0);
            vm.stopPrank();
            rollBlock();
        }

        // Fast forward 30 days to accumulate salary
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(sponsor, sponsor);
        uint256 gasStart = gasleft();
        try systemContract.claimRank() {} catch {}
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();
        
        return gasUsed;
    }

    // [ignoring loop detection]
    function measureNewInvest(uint256 directCount) external returns (uint256) {
        _setupSponsor();
        
        for (uint256 i = 0; i < directCount; i++) {
            address referee = address(uint160(0x5000 + i));
            usdt.mint(referee, 200 * 1e18);
            vm.startPrank(referee, referee);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, sponsor, 0);
            vm.stopPrank();
            rollBlock();
        }

        address testReferee = address(0xBBBB);
        usdt.mint(testReferee, 200 * 1e18);
        vm.startPrank(testReferee, testReferee);
        usdt.approve(address(systemContract), type(uint256).max);
        
        uint256 gasStart = gasleft();
        systemContract.invest(100 * 1e18, sponsor, 0);
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();
        
        return gasUsed;
    }

    // [ignoring loop detection]
    function measureWithdraw(uint256 investmentCount) external returns (uint256) {
        address user = address(0xCCCC);
        usdt.mint(user, 100000 * 1e18);
        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        
        for (uint256 i = 0; i < investmentCount; i++) {
            systemContract.invest(100 * 1e18, ORIGIN, 0);
            rollBlock();
        }
        vm.stopPrank();

        // Fast forward 3 days and warp cooling period
        vm.warp(block.timestamp + 4 days);
        rollBlock();

        vm.startPrank(user, user);
        uint256 gasStart = gasleft();
        systemContract.withdraw();
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();
        
        return gasUsed;
    }

    // [ignoring loop detection]
    function measurePendingBonusProcessing(uint256 pendingCount) external returns (uint256) {
        _setupSponsor();
        
        // Populate pendingDirectBonuses array
        for (uint256 i = 0; i < pendingCount; i++) {
            address referee = address(uint160(0x5000 + i));
            usdt.mint(referee, 200 * 1e18);
            vm.startPrank(referee, referee);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(100 * 1e18, sponsor, 0);
            vm.stopPrank();
            rollBlock();
        }

        // Fast forward unlock time (12 hours)
        vm.warp(block.timestamp + 13 hours);

        // Call withdraw, which triggers _realizePendingDirectBonus
        vm.startPrank(sponsor, sponsor);
        uint256 gasStart = gasleft();
        try systemContract.withdraw() {} catch {}
        uint256 gasUsed = gasStart - gasleft();
        vm.stopPrank();
        
        return gasUsed;
    }
}
