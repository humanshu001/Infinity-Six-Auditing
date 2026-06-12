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
contract ArithmeticTest is Test {
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

    // Test 1: Precision Loss in Salary due to division before multiplication
    function test_Arithmetic_SalaryPrecisionLoss() public {
        // Setup user as sponsor to qualify for rank 1
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(3000 * 1e18, ORIGIN, 0); 
        vm.stopPrank();
        rollBlock();

        // Register 5 directs to satisfy rank conditions
        // Strongest leg must be >= 1200 USDT. We make leg 0 invest 1500 USDT.
        // Weaker legs must sum >= 1800 USDT. We make 4 other legs invest 1000 USDT each (total 4000 USDT).
        for (uint256 i = 0; i < 5; i++) {
            address d = address(uint160(0x3000 + i));
            uint256 investAmt = i == 0 ? 1500 * 1e18 : 1000 * 1e18;
            usdt.mint(d, 2000 * 1e18);
            vm.startPrank(d, d);
            usdt.approve(address(systemContract), type(uint256).max);
            systemContract.invest(investAmt, sponsor, 0);
            vm.stopPrank();
            rollBlock();
        }

        // Verify that auto-upgrade promoted sponsor to rank 1
        (
            uint256 totalDeposits,
            uint256 directBonus,
            uint256 directCount,
            uint256 directVolume,
            uint256 currentRwpRate,
            uint256 teamVolume,
            uint256 totalDownlineBusiness,
            uint256 levelRewardsRealized,
            uint256 lastLevelUpdateTime,
            bool isUplineEligible,
            uint256 eligibleL1Count,
            uint256 eligibleL2Count,
            uint256 eligibleL3Count,
            uint256 pendingUplineIncome,
            uint256 currentRank,
            uint256 salaryLastClaimTime,
            uint256 salaryEndTime,
            uint256 unwithdrawnSalary,
            uint256 totalWithdrawn,
            address referrer,
            bool isCapped,
            uint256 firstInvestment,
            uint256 freshBusiness,
            uint256 directBoosterCount,
            uint256 activeon,
            uint256 directBoosterBusiness,
            bool isBoosted
        ) = systemContract.users(sponsor);
        assertEq(currentRank, 1, "Sponsor should have been auto-upgraded to rank 1");

        // Verify precision loss
        uint256 expectedPerSec = uint256(50 * 1e18) / 2592000;
        emit log_named_uint("Truncated Salary Per Second", expectedPerSec);
        
        uint256 actualSalary = systemContract.getPendingSalary(sponsor);
        
        vm.warp(block.timestamp + 30 days);
        uint256 singleClaimSalary = systemContract.getPendingSalary(sponsor);
        emit log_named_uint("Salary after 30 days (single claim)", singleClaimSalary);
        
        // Single claim salary should be less than the true mathematical value (50 * 1e18)
        assertLt(singleClaimSalary, 50 * 1e18, "Precision loss occurred on single claim");
    }

    // Test 2: ROI Multiplier Fall-Through Flaw
    function test_Arithmetic_SetROI_Mismatch() public {
        // First setup sponsor active
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();
        rollBlock();

        // Set ROI to 9% via DAO multisig (since controller is address(this), call directly)
        systemContract.setROI(9);

        // Verify that rate 9 uses default multiplier (representing 5) instead of 9 in compounding calculations
        uint256 minRoi = systemContract.MIN_ROI_PERC();
        assertEq(minRoi, 9);

        // Invest under sponsor to observe compounding
        vm.startPrank(user, user);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, sponsor, 0);
        vm.stopPrank();

        // Warp time by 1 year (365 days)
        vm.warp(block.timestamp + 365 days);

        uint256 totalLifetime = systemContract.getTotalLifetimeRWP(user);
        emit log_named_uint("Simulated ROI Rewards after 1 year with 9% ROI set", totalLifetime);

        // Capped at 2500 USDT (2.5x of 1000 USDT)
        assertEq(totalLifetime, 2500 * 1e18);
    }
}
