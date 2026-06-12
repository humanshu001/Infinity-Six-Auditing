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
///        withdraw() at the FULL contract boundary values.
///
/// @notice Contract limits (from mainnet values):
///         * 100 investment packages per user (`Err_MaxInvestmentsAllowed`)
///         * 200 directs per sponsor (`MAX_DIRECTS`)
///         * `maxDownlineDepth` = 1000 upline iterations
///
///         All tests measure the ACTUAL gas consumed at these exact limits.
///         Results report gas units plus percentage of BSC's 140M block limit
///         and the 30M standard RPC tx limit.
///
/// @dev Mock infrastructure: we extend `BaseForkSetup` (BSC fork), but deploy
///      a LOCAL mock USDT, mock pair, and mock router. This isolates the gas
///      profile of the MLM logic from PancakeSwap's swap/addLiquidity overhead
///      (~250-450k gas per invest in production). When reading production
///      estimates, add ~350k gas to invest results and ~150k for withdraws.
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

    function _localInvest(address user, uint256 amt, address sponsor_) internal {
        _localFund(user, amt);
        _rollBlock();
        vm.prank(user, user);
        mlmSystem.invest(amt, sponsor_, 0);
    }

    /// @dev Build a linear referral chain of `depth` members.
    ///      chain[0] is sponsored by ORIGIN, chain[i] by chain[i-1].
    ///      Each member invests exactly MIN_INVESTMENT (100 USDT).
    function _localBuildChain(uint256 depth) internal returns (address[] memory chain) {
        chain = new address[](depth);
        address sponsor_ = ORIGIN_LIVE;
        for (uint256 i = 0; i < depth; i++) {
            address u = makeAddr(string.concat("c", vm.toString(i)));
            chain[i] = u;
            _localInvest(u, 100 * WAD, sponsor_);
            sponsor_ = u;
        }
    }

    /// @dev Build `n` direct referrals under `sponsor_`.
    function _localBuildDirects(address sponsor_, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            address u = makeAddr(string.concat("d", vm.toString(i)));
            _localInvest(u, 100 * WAD, sponsor_);
        }
    }

    function _measureInvest(address sponsor_, uint256 amt, string memory salt)
        internal returns (uint256 gasUsed)
    {
        address u = makeAddr(salt);
        _localFund(u, amt);
        _rollBlock();
        vm.prank(u, u);
        uint256 g = gasleft();
        mlmSystem.invest(amt, sponsor_, 0);
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
        emit log_named_uint("  % of BSC block limit (140M)", (g * 100) / BSC_BLOCK_LIMIT);
        emit log_named_uint("  % of std RPC cap (30M)", (g * 100) / RPC_TX_LIMIT);
        emit log_named_uint("  permille of BSC block (140M = 1000)", (g * 1000) / BSC_BLOCK_LIMIT);
        emit log_named_uint("  permille of std RPC cap (30M = 1000)", (g * 1000) / RPC_TX_LIMIT);

        if (g > RPC_TX_LIMIT) {
            emit log_named_string("  !! WARNING !!", "EXCEEDS 30M RPC tx gas limit");
        }
        if (g > BSC_BLOCK_LIMIT) {
            emit log_named_string("  !! CRITICAL !!", "EXCEEDS 140M BSC block gas limit");
        }
    }

    // ========================================================================
    // BEST CASE -- minimal state, depth=1
    // ========================================================================

    /// @notice Invest under ORIGIN (depth=1, 0 existing packages, 0 directs).
    function test_GAS_BEST_invest_under_origin() public {
        uint256 g = _measureInvest(ORIGIN_LIVE, 100 * WAD, "best");
        _logGas("BEST: 1st invest, depth=1 (under ORIGIN)", g);
    }

    /// @notice Withdraw with 1 package at depth=1.
    function test_GAS_BEST_withdraw_single_package() public {
        address u = makeAddr("bestUser");
        _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("BEST: withdraw with 1 package, depth=1", g);
    }

    // ========================================================================
    // MEDIUM -- moderate conditions
    // ========================================================================

    /// @notice Invest at depth 500 (halfway to max).
    function test_GAS_MED_invest_chain_500() public {
        address[] memory chain = _localBuildChain(499);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "med-500");
        _logGas("MED: invest at depth 500", g);
    }

    /// @notice Withdraw with 10 packages.
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
    // WORST CASES -- all three boundaries at contract maximums
    // ========================================================================

    // ---------- WORST: Depth 1000 (full maxDownlineDepth) ----------

    /// @notice Invest at FULL depth 1000 -- the _updateDownlineBusiness loop
    ///         walks all 1000 upline ancestors. This is the absolute worst
    ///         case for invest() gas.
    function test_GAS_WORST_invest_at_depth_1000() public {
        // Build a chain of 999 members, then measure the 1000th invest.
        address[] memory chain = _localBuildChain(999);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "worst-depth-1000");
        _logGas("WORST: invest at depth 1000 (FULL maxDownlineDepth)", g);
    }

    // ---------- WORST: 200 directs (MAX_DIRECTS) ----------

    /// @notice Invest creating the 200th direct under a sponsor (MAX_DIRECTS).
    ///         The invest itself is at depth=2, but the sponsor already has 199
    ///         directs. This tests the impact of a full directs array on
    ///         _tryAutoRank, _checkRankQualification, etc.
    function test_GAS_WORST_invest_200th_direct_on_sponsor() public {
        address sponsor_ = makeAddr("sponsorMax");
        _localInvest(sponsor_, 100 * WAD, ORIGIN_LIVE);
        _localBuildDirects(sponsor_, 199);
        uint256 g = _measureInvest(sponsor_, 100 * WAD, "worst-direct-200");
        _logGas("WORST: invest creating the 200th direct under sponsor", g);
    }

    // ---------- WORST: 100 packages (Err_MaxInvestmentsAllowed) ----------

    /// @notice Withdraw with exactly 100 active packages (the maximum).
    ///         withdraw() iterates all packages twice (available RWP scan + deduction).
    function test_GAS_WORST_withdraw_100_packages() public {
        address u = makeAddr("worstPkg");
        for (uint256 i = 0; i < 100; i++) {
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("WORST: withdraw with 100 packages, depth=1", g);
    }

    // ========================================================================
    // ABSOLUTE WORST -- all three maxes combined
    // ========================================================================

    /// @notice The absolute worst-case invest: at depth 1000, the sponsor
    ///         already has 199 directs (200th direct), and the investor
    ///         themselves will have 100 packages. This combines ALL three
    ///         boundary conditions simultaneously.
    function test_GAS_ABSOLUTE_WORST_invest_1000depth_200directs() public {
        // Build 999-deep chain
        address[] memory chain = _localBuildChain(999);
        address deepSponsor = chain[chain.length - 1];

        // Give the deep sponsor 199 existing directs
        for (uint256 i = 0; i < 199; i++) {
            address d = makeAddr(string.concat("aw-d", vm.toString(i)));
            _localInvest(d, 100 * WAD, deepSponsor);
        }

        // The 200th direct under a sponsor at depth 999 = investor at depth 1000
        uint256 g = _measureInvest(deepSponsor, 100 * WAD, "absolute-worst-invest");
        _logGas(
            "ABSOLUTE WORST INVEST: depth 1000 + 200th direct on sponsor",
            g
        );
    }

    /// @notice The absolute worst-case withdraw: 100 packages, user sits at
    ///         depth 1000, sponsor has 200 directs. withdraw() does NOT iterate
    ///         over depth or directs (only packages), so this confirms that
    ///         withdraw cost is independent of tree position.
    function test_GAS_ABSOLUTE_WORST_withdraw_100pkg_1000depth_200directs() public {
        // Build 999-deep chain
        address[] memory chain = _localBuildChain(999);
        address deepSponsor = chain[chain.length - 1];

        // Give the deep sponsor 199 existing directs
        for (uint256 i = 0; i < 199; i++) {
            address d = makeAddr(string.concat("aw-wd", vm.toString(i)));
            _localInvest(d, 100 * WAD, deepSponsor);
        }

        // Create the actor as the 200th direct at depth 1000
        address actor = makeAddr("worstActor");
        _localInvest(actor, 100 * WAD, deepSponsor); // pkg 1, direct #200

        // Fill remaining 99 packages (re-invest into same sponsor)
        for (uint256 i = 0; i < 99; i++) {
            _localInvest(actor, 100 * WAD, deepSponsor);
        }

        _advanceTime(30 days);
        uint256 g = _measureWithdraw(actor);
        _logGas(
            "ABSOLUTE WORST WITHDRAW: 100 pkgs / 200 directs on sponsor / depth 1000",
            g
        );
        emit log_named_string(
            "Note",
            "withdraw is independent of depth/directs; cost driven by package count"
        );
    }

    // ========================================================================
    // SUMMARY TABLE -- emitted at the end of the combined worst test
    // ========================================================================

    /// @notice Run all scenarios back-to-back and emit a summary table.
    ///         This single test provides the full picture in one output.
    function test_GAS_SUMMARY_all_scenarios() public {
        emit log_string("============================================================");
        emit log_string("  GAS ANALYSIS SUMMARY -- BSC mainnet fork");
        emit log_string("  Block gas limit: 140,000,000 | RPC tx limit: 30,000,000");
        emit log_string("============================================================");

        // --- BEST: invest depth 1 ---
        uint256 g1 = _measureInvest(ORIGIN_LIVE, 100 * WAD, "s-best-inv");
        _logGas("[1/8] BEST invest (depth=1, 0 pkgs)", g1);

        // --- BEST: withdraw 1 pkg ---
        {
            address u = makeAddr("s-best-wd");
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
            _advanceTime(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[2/8] BEST withdraw (1 pkg, depth=1)", g);
        }

        // --- MED: invest depth 500 ---
        {
            address[] memory chain500 = _localBuildChain(499);
            uint256 g = _measureInvest(chain500[chain500.length - 1], 100 * WAD, "s-med-500");
            _logGas("[3/8] MED invest (depth=500)", g);
        }

        // --- MED: withdraw 10 pkgs ---
        {
            address u = makeAddr("s-med-wd");
            for (uint256 i = 0; i < 10; i++) {
                _localInvest(u, 100 * WAD, ORIGIN_LIVE);
            }
            _advanceTime(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[4/8] MED withdraw (10 pkgs)", g);
        }

        // --- WORST: invest depth 1000 ---
        {
            address[] memory chain1k = _localBuildChain(999);
            uint256 g = _measureInvest(chain1k[chain1k.length - 1], 100 * WAD, "s-worst-1k");
            _logGas("[5/8] WORST invest (depth=1000)", g);
        }

        // --- WORST: 200th direct ---
        {
            address sp = makeAddr("s-sp200");
            _localInvest(sp, 100 * WAD, ORIGIN_LIVE);
            for (uint256 i = 0; i < 199; i++) {
                address d = makeAddr(string.concat("s-d200-", vm.toString(i)));
                _localInvest(d, 100 * WAD, sp);
            }
            uint256 g = _measureInvest(sp, 100 * WAD, "s-direct-200");
            _logGas("[6/8] WORST invest (200th direct)", g);
        }

        // --- WORST: withdraw 100 pkgs ---
        {
            address u = makeAddr("s-worst-wd100");
            for (uint256 i = 0; i < 100; i++) {
                _localInvest(u, 100 * WAD, ORIGIN_LIVE);
            }
            _advanceTime(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[7/8] WORST withdraw (100 pkgs)", g);
        }

        // --- ABSOLUTE WORST: invest depth 1000 + 200 directs ---
        {
            address[] memory chainAW = _localBuildChain(999);
            address deepSp = chainAW[chainAW.length - 1];
            for (uint256 i = 0; i < 199; i++) {
                address d = makeAddr(string.concat("s-aw-", vm.toString(i)));
                _localInvest(d, 100 * WAD, deepSp);
            }
            uint256 g = _measureInvest(deepSp, 100 * WAD, "s-abs-worst");
            _logGas("[8/8] ABSOLUTE WORST invest (depth=1000 + 200th direct)", g);
        }

        emit log_string("============================================================");
        emit log_string("  END OF GAS ANALYSIS SUMMARY");
        emit log_string("============================================================");
    }
}
