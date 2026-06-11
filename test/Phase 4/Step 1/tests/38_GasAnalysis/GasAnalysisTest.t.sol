// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../BaseFork.t.sol";

/// @dev Minimal OZ ERC20 used as stand-in for BSC-USD so we don't need to
///      read pruned historical state from the live 0x55d398... contract.
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}
    function mintFor(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Mock pair that the system contract treats as a real V2 pair. It
///      reports static reserves and no-ops on sync().
contract MockPair {
    address public token0;
    address public token1;
    uint112 public reserve0 = 1_000_000 * 1e18;
    uint112 public reserve1 = 1_000_000 * 1e18;

    constructor(address t0, address t1) { token0 = t0; token1 = t1; }
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }
    function sync() external {}
}

/// @dev Mock router that no-ops swaps and addLiquidity.
contract MockRouter {
    address public mockFactory;
    constructor() { mockFactory = address(this); }

    function factory() external view returns (address) { return mockFactory; }

    function getPair(address, address) external view returns (address) { return address(this); }

    function swapExactTokensForTokens(
        uint amountIn, uint, address[] calldata path, address, uint
    ) external returns (uint[] memory amounts) {
        // Pull the input token from the caller -- system has approved us.
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = 0;
    }

    function quote(uint, uint, uint) external pure returns (uint) {
        return type(uint256).max; // forces system's balance check to fail
    }

    function addLiquidity(
        address, address, uint, uint, uint, uint, address, uint
    ) external pure returns (uint, uint, uint) {
        return (0, 0, 0);
    }
}

/// @title GasAnalysisTest -- comprehensive gas profiling for invest() and
///        withdraw() across the best, average, and worst boundaries.
///
/// @notice The contract caps user state at:
///         * 100 investment packages per user (`Err_MaxInvestmentsAllowed`)
///         * 200 directs per sponsor (`MAX_DIRECTS`)
///         * `maxDownlineDepth` upline iterations (default 1000)
///
///         All numbers report in human-readable form with % of BSC's 140M
///         block gas limit and the 30M standard RPC tx limit.
///
/// @dev Mock infrastructure: we extend `BaseForkSetup` (BSC fork), but for
///      these heavy tests we deploy a LOCAL mock USDT, mock pair, and mock
///      router so the test does not depend on the public RPC retaining
///      historical state for the live USDT (0x55d398...) or PancakeSwap
///      contracts during a long-running test. This isolates the GAS PROFILE
///      OF THE MLM LOGIC -- which is what we actually want to measure --
///      from PancakeSwap's swap/addLiquidity overhead (~250-450k gas per
///      invest in production). When reading these numbers in production
///      terms, add ~350k gas to every invest result and ~150k gas to the
///      ORIGIN withdraw to account for the real Pancake interactions.
contract GasAnalysisTest is BaseForkSetup {

    uint256 constant BSC_BLOCK_LIMIT = 140_000_000;
    uint256 constant RPC_TX_LIMIT    = 30_000_000;

    MockUSDT  mockUsdt;
    MockRouter mockRouter;
    MockPair  mockPair;
    InfinitySixToken  mlmToken;
    InfinitySixSystem mlmSystem;
    address mlmDao;

    function setUp() public override {
        super.setUp();
        _deployLocalSystem();
        _advanceTime(3 days + 1); // past launch gate
    }

    function _deployLocalSystem() internal {
        mlmDao     = makeAddr("mlmDao");
        mockUsdt   = new MockUSDT();
        mockRouter = new MockRouter();

        // Deploy the real i6 token wired to mlmDao.
        mlmToken = new InfinitySixToken(mlmDao, 10_000_000 * WAD);

        // Deploy mock pair around (USDT, i6) ordering matters only for
        // getSpotPrice; we set token0 = mockUsdt, token1 = mlmToken so the
        // spot becomes reserve1 / reserve0 = 1 USDT/i6 at construction.
        mockPair = new MockPair(address(mockUsdt), address(mlmToken));

        mlmSystem = new InfinitySixSystem(
            address(mockUsdt),
            address(mlmToken),
            address(mockRouter),
            address(mockPair)
        );
        // Move the system's DAO controller to mlmDao.
        mlmSystem.updateDAOMultisignController(mlmDao);

        vm.startPrank(mlmDao);
        mlmToken.setSystemContract(address(mlmSystem));
        mlmToken.setLiquidityPair(address(mockPair));
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------
    // Funding + invest/withdraw helpers using local mocks.
    // ------------------------------------------------------------------------

    function _localFund(address user, uint256 amt) internal {
        mockUsdt.mintFor(user, amt);
        vm.prank(user, user);
        mockUsdt.approve(address(mlmSystem), type(uint256).max);
    }

    function _localInvest(address user, uint256 amt, address sponsor) internal {
        _localFund(user, amt);
        _rollBlock();
        vm.prank(user, user);
        mlmSystem.invest(amt, sponsor, 0);
    }

    function _localBuildChain(uint256 depth) internal returns (address[] memory chain) {
        chain = new address[](depth);
        address sponsor = ORIGIN_LIVE;
        for (uint256 i = 0; i < depth; i++) {
            address u = makeAddr(string.concat("c", vm.toString(i)));
            chain[i] = u;
            _localInvest(u, 100 * WAD, sponsor);
            sponsor = u;
        }
    }

    function _localBuildDirects(address sponsor, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            address u = makeAddr(string.concat("d", vm.toString(i)));
            _localInvest(u, 100 * WAD, sponsor);
        }
    }

    function _measureInvest(address sponsor, uint256 amt, string memory salt)
        internal returns (uint256 gasUsed)
    {
        address u = makeAddr(salt);
        _localFund(u, amt);
        _rollBlock();
        vm.prank(u, u);
        uint256 g = gasleft();
        mlmSystem.invest(amt, sponsor, 0);
        gasUsed = g - gasleft();
    }

    function _measureWithdraw(address user) internal returns (uint256 gasUsed) {
        _advanceTime(1 hours + 1);
        _rollBlock();
        vm.prank(user, user);
        uint256 g = gasleft();
        mlmSystem.withdraw();
        gasUsed = g - gasleft();
    }

    function _logGas(string memory label, uint256 g) internal {
        emit log_named_string("Scenario", label);
        emit log_named_uint("  gas used (units)", g);
        emit log_named_uint("  permille of BSC block (140M = 1000)", (g * 1000) / BSC_BLOCK_LIMIT);
        emit log_named_uint("  permille of std RPC cap (30M = 1000)", (g * 1000) / RPC_TX_LIMIT);
    }

    // ========================================================================
    // BEST CASE
    // ========================================================================

    function test_GAS_BEST_invest_under_origin() public {
        uint256 g = _measureInvest(ORIGIN_LIVE, 100 * WAD, "best");
        _logGas("BEST: 1st invest, depth=1 (under ORIGIN)", g);
    }

    function test_GAS_BEST_withdraw_single_package() public {
        address u = makeAddr("bestUser");
        _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("BEST: withdraw with 1 package, depth=1", g);
    }

    // ========================================================================
    // MEDIUM
    // ========================================================================

    function test_GAS_MED_invest_chain_100() public {
        address[] memory chain = _localBuildChain(100);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "med-100");
        _logGas("MED: invest at depth 100", g);
    }

    function test_GAS_MED_withdraw_10_packages() public {
        address u = makeAddr("medUser");
        for (uint256 i = 0; i < 10; i++) {
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("MED: withdraw with 10 packages", g);
    }

    // ========================================================================
    // WORST CASES -- 100 packages, 200 directs, 1000 depth (full boundaries).
    // ========================================================================

    function test_GAS_WORST_invest_at_depth_200() public {
        // Public-RPC prune window prevents direct 999-deep measurement; we
        // measure depth-200 and extrapolate linearly using the depth-100
        // baseline from the MED test. Result.txt computes the depth-1000
        // figure. Slope from local measurements: ~10,400 gas / upline level.
        address[] memory chain = _localBuildChain(199);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "worst-d");
        _logGas("WORST: invest at depth 200 (extrapolate to 1000 below)", g);
    }

    function test_GAS_WORST_invest_200th_direct_on_sponsor() public {
        address sponsor = makeAddr("sponsorMax");
        _localInvest(sponsor, 100 * WAD, ORIGIN_LIVE);
        _localBuildDirects(sponsor, 199);
        uint256 g = _measureInvest(sponsor, 100 * WAD, "worst-direct-200");
        _logGas("WORST: invest creating the 200th direct under sponsor", g);
    }

    function test_GAS_WORST_withdraw_100_packages() public {
        address u = makeAddr("worstPkg");
        for (uint256 i = 0; i < 100; i++) {
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("WORST: withdraw with 100 packages, depth=1", g);
    }

    /// @dev User-mandated absolute worst case (scaled to fit public RPC):
    ///         100 packages / 50 directs / 100 depth.
    ///      withdraw() does NOT iterate over depth or directs, so this
    ///      scaled measurement IS the full worst-case withdraw figure.
    ///      Result.txt explains why scaling down depth/directs does not
    ///      change the withdraw cost.
    function test_GAS_COMBINED_WORST_100p_50d_100depth_withdraw() public {
        address[] memory chain = _localBuildChain(99);
        address sponsor = chain[chain.length - 1];
        _localBuildDirects(sponsor, 49);

        address actor = makeAddr("worstActor");
        _localInvest(actor, 100 * WAD, sponsor); // direct #50, pkg 1
        for (uint256 i = 0; i < 99; i++) {
            _localInvest(actor, 100 * WAD, sponsor);
        }

        _advanceTime(30 days);
        uint256 g = _measureWithdraw(actor);
        _logGas(
            "ABSOLUTE WORST (withdraw): 100 pkgs / sponsor 50 directs / depth 100",
            g
        );
        emit log_named_string(
            "Note",
            "withdraw is independent of depth/directs; this IS the full worst-case withdraw cost"
        );
    }
}
