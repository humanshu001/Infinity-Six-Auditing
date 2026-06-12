// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../BaseFork.t.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}
    function mintFor(address to, uint256 amount) external { _mint(to, amount); }
}

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

contract MockRouter {
    address public mockFactory;
    constructor() { mockFactory = address(this); }

    function factory() external view returns (address) { return mockFactory; }

    function getPair(address, address) external view returns (address) { return address(this); }

    function swapExactTokensForTokens(
        uint amountIn, uint, address[] calldata path, address, uint
    ) external returns (uint[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = 0;
    }

    function quote(uint, uint, uint) external pure returns (uint) {
        return type(uint256).max;
    }

    function addLiquidity(
        address, address, uint, uint, uint, uint, address, uint
    ) external pure returns (uint, uint, uint) {
        return (0, 0, 0);
    }
}

contract GasAnalysisTest is BaseForkSetup {

    uint256 constant BSC_BLOCK_LIMIT = 140_000_000;
    uint256 constant RPC_TX_LIMIT    = 30_000_000;

    MockUSDT   mockUsdt;
    MockRouter mockRouter;
    MockPair   mockPair;
    InfinitySixToken  mlmToken;
    InfinitySixSystem mlmSystem;
    address mlmDao;

    function setUp() public override {
        super.setUp(); // selects fork, runs verifyMainnetState
        _deployLocalSystem();
        _advanceTimeLocal(3 days + 1); // past launch gate (warps timestamp only)
    }

    function _deployLocalSystem() internal {
        mlmDao     = makeAddr("mlmDao");
        mockUsdt   = new MockUSDT();
        mockRouter = new MockRouter();

        mlmToken = new InfinitySixToken(mlmDao, 10_000_000 * WAD);

        mockPair = new MockPair(address(mockUsdt), address(mlmToken));

        mlmSystem = new InfinitySixSystem(
            address(mockUsdt),
            address(mlmToken),
            address(mockRouter),
            address(mockPair)
        );
        mlmSystem.updateDAOMultisignController(mlmDao);

        vm.startPrank(mlmDao);
        mlmToken.setSystemContract(address(mlmSystem));
        mlmToken.setLiquidityPair(address(mockPair));
        vm.stopPrank();
    }

    // Custom time advancement that only warps the timestamp and does not roll block number.
    // This prevents the EVM from moving too far ahead of the RPC's current state root.
    function _advanceTimeLocal(uint256 secs) internal {
        currentTimestamp += secs;
        vm.warp(currentTimestamp);
    }

    // ------------------------------------------------------------------------
    // Funding + invest/withdraw helpers using local mocks.
    // ------------------------------------------------------------------------

    function _localFund(address user, uint256 amt) internal {
        // Pre-populate the user's account state in the local EVM trie with 1 wei.
        // This stops the EVM from querying the RPC to see if the address has code/state.
        vm.deal(user, 1);
        mockUsdt.mintFor(user, amt);
        vm.prank(user, user);
        mockUsdt.approve(address(mlmSystem), type(uint256).max);
    }

    function _localInvest(address user, uint256 amt, address sponsor_) internal {
        _localFund(user, amt);
        // Do not roll block here to keep block number constant for different users
        vm.prank(user, user);
        mlmSystem.invest(amt, sponsor_, 0);
    }

    // Helper to cache an address locally before using it as a sponsor/recipient to prevent RPC lookups
    function _cacheAddress(address addr) internal {
        vm.deal(addr, 1);
    }

    function _localBuildChain(uint256 depth, string memory prefix) internal returns (address[] memory chain) {
        chain = new address[](depth);
        address sponsor_ = ORIGIN_LIVE;
        _cacheAddress(sponsor_);
        for (uint256 i = 0; i < depth; i++) {
            address u = makeAddr(string.concat(prefix, vm.toString(i)));
            chain[i] = u;
            _localInvest(u, 100 * WAD, sponsor_);
            sponsor_ = u;
        }
    }

    function _localBuildChain(uint256 depth) internal returns (address[] memory) {
        return _localBuildChain(depth, "c");
    }

    function _localBuildDirects(address sponsor_, uint256 n, string memory prefix) internal {
        _cacheAddress(sponsor_);
        for (uint256 i = 0; i < n; i++) {
            address u = makeAddr(string.concat(prefix, vm.toString(i)));
            _localInvest(u, 100 * WAD, sponsor_);
        }
    }

    function _localBuildDirects(address sponsor_, uint256 n) internal {
        _localBuildDirects(sponsor_, n, "d");
    }

    function _measureInvest(address sponsor_, uint256 amt, string memory salt)
        internal returns (uint256 gasUsed)
    {
        address u = makeAddr(salt);
        _localFund(u, amt);
        _cacheAddress(sponsor_);
        vm.prank(u, u);
        uint256 g = gasleft();
        mlmSystem.invest(amt, sponsor_, 0);
        gasUsed = g - gasleft();
    }

    function _measureWithdraw(address user) internal returns (uint256 gasUsed) {
        _advanceTimeLocal(1 hours + 1);
        _rollBlock();
        _cacheAddress(user);
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
    // BSC MAINNET FORK VERIFICATION
    // ========================================================================

    function test_GAS_BSC_FORK_VERIFICATION() public view {
        assertEq(mlmSystem.maxDownlineDepth(),  1000, "maxDownlineDepth must be 1000");
        assertEq(mlmSystem.MAX_DIRECTS(),       200,  "MAX_DIRECTS must be 200");
        assertEq(mlmSystem.MIN_INVESTMENT(),    100 * WAD, "MIN_INVESTMENT must be 100 USDT");
        assertEq(mlmSystem.MAX_INCOME_MULTIPLIER(), 6, "MAX_INCOME_MULTIPLIER must be 6");
        assertEq(mlmSystem.WITHDRAWAL_COOLING_PERIOD(), 3600, "WITHDRAWAL_COOLING_PERIOD must be 1 hour");
        assertEq(mlmToken.buyingEnabled(),      false, "buyingEnabled must be false");
    }

    // ========================================================================
    // BEST CASE -- minimal state, depth=1
    // ========================================================================

    function test_GAS_BEST_invest_under_origin() public {
        uint256 g = _measureInvest(ORIGIN_LIVE, 100 * WAD, "best");
        _logGas("BEST: 1st invest, depth=1 (under ORIGIN)", g);
    }

    function test_GAS_BEST_withdraw_single_package() public {
        address u = makeAddr("bestUser");
        _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        _advanceTimeLocal(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("BEST: withdraw with 1 package, depth=1", g);
    }

    // ========================================================================
    // MEDIUM -- moderate conditions
    // ========================================================================

    function test_GAS_MED_invest_chain_500() public {
        address[] memory chain = _localBuildChain(499);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "med-500");
        _logGas("MED: invest at depth 500", g);
    }

    function test_GAS_MED_withdraw_10_packages() public {
        address u = makeAddr("medUser");
        for (uint256 i = 0; i < 10; i++) {
            _rollBlock(); // same user needs block rolling
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTimeLocal(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("MED: withdraw with 10 packages", g);
    }

    // ========================================================================
    // WORST CASES -- all three boundaries at contract maximums
    // ========================================================================

    function test_GAS_WORST_invest_at_depth_1000() public {
        address[] memory chain = _localBuildChain(999);
        uint256 g = _measureInvest(chain[chain.length - 1], 100 * WAD, "worst-depth-1000");
        _logGas("WORST: invest at depth 1000 (FULL maxDownlineDepth)", g);
    }

    function test_GAS_WORST_invest_200th_direct_on_sponsor() public {
        address sponsor_ = makeAddr("sponsorMax");
        _localInvest(sponsor_, 100 * WAD, ORIGIN_LIVE);
        _localBuildDirects(sponsor_, 199);
        uint256 g = _measureInvest(sponsor_, 100 * WAD, "worst-direct-200");
        _logGas("WORST: invest creating the 200th direct under sponsor", g);
    }

    function test_GAS_WORST_withdraw_100_packages() public {
        address u = makeAddr("worstPkg");
        for (uint256 i = 0; i < 100; i++) {
            _rollBlock(); // same user needs block rolling
            _localInvest(u, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTimeLocal(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("WORST: withdraw with 100 packages, depth=1", g);
    }

    // ========================================================================
    // ABSOLUTE WORST -- all three maxes combined
    // ========================================================================

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
        _logGas("ABSOLUTE WORST INVEST: depth 1000 + 200th direct on sponsor", g);
    }

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
        _localInvest(actor, 100 * WAD, deepSponsor);

        // Fill remaining 99 packages
        for (uint256 i = 0; i < 99; i++) {
            _rollBlock(); // same user needs block rolling
            _localInvest(actor, 100 * WAD, deepSponsor);
        }

        _advanceTimeLocal(30 days);
        uint256 g = _measureWithdraw(actor);
        _logGas("ABSOLUTE WORST WITHDRAW: 100 pkgs / 200 directs on sponsor / depth 1000", g);
    }

    // ========================================================================
    // SUMMARY TABLE -- all scenarios in a single test for one-shot output
    // ========================================================================

    function test_GAS_SUMMARY_all_scenarios() public {
        emit log_string("============================================================");
        emit log_string("  GAS ANALYSIS SUMMARY -- Real i6 contracts, BSC parameters");
        emit log_string("  Block gas limit: 140,000,000 | RPC tx limit: 30,000,000");
        emit log_string("  maxDownlineDepth=1000 | MAX_DIRECTS=200 | MaxPkgs=100");
        emit log_string("============================================================");

        address baseSponsor = makeAddr("s-base-sponsor");
        _localInvest(baseSponsor, 100 * WAD, ORIGIN_LIVE);

        // --- BEST: invest depth 1 ---
        uint256 g1 = _measureInvest(baseSponsor, 100 * WAD, "s-best-inv");
        _logGas("[1/8] BEST invest (depth=2, 0 pkgs)", g1);

        // --- BEST: withdraw 1 pkg ---
        {
            address u = makeAddr("s-best-wd");
            _localInvest(u, 100 * WAD, baseSponsor);
            _advanceTimeLocal(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[2/8] BEST withdraw (1 pkg, depth=2)", g);
        }

        // --- MED: invest depth 500 ---
        {
            address[] memory chain500 = _localBuildChain(499, "s5-");
            uint256 g = _measureInvest(chain500[chain500.length - 1], 100 * WAD, "s-med-500");
            _logGas("[3/8] MED invest (depth=500)", g);
        }

        // --- MED: withdraw 10 pkgs ---
        {
            address u = makeAddr("s-med-wd");
            for (uint256 i = 0; i < 10; i++) {
                _rollBlock(); // same user needs block rolling
                _localInvest(u, 100 * WAD, baseSponsor);
            }
            _advanceTimeLocal(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[4/8] MED withdraw (10 pkgs)", g);
        }

        // --- WORST: invest depth 1000 ---
        {
            address[] memory chain1k = _localBuildChain(999, "s1k-");
            uint256 g = _measureInvest(chain1k[chain1k.length - 1], 100 * WAD, "s-worst-1k");
            _logGas("[5/8] WORST invest (depth=1000)", g);
        }

        // --- WORST: 200th direct ---
        {
            address sp = makeAddr("s-sp200");
            _localInvest(sp, 100 * WAD, baseSponsor);
            _localBuildDirects(sp, 199, "s-d200-");
            uint256 g = _measureInvest(sp, 100 * WAD, "s-direct-200");
            _logGas("[6/8] WORST invest (200th direct)", g);
        }

        // --- WORST: withdraw 100 pkgs ---
        {
            address u = makeAddr("s-worst-wd100");
            for (uint256 i = 0; i < 100; i++) {
                _rollBlock(); // same user needs block rolling
                _localInvest(u, 100 * WAD, baseSponsor);
            }
            _advanceTimeLocal(30 days);
            uint256 g = _measureWithdraw(u);
            _logGas("[7/8] WORST withdraw (100 pkgs)", g);
        }

        // --- ABSOLUTE WORST: invest depth 1000 + 200 directs ---
        {
            address[] memory chainAW = _localBuildChain(999, "saw-");
            address deepSp = chainAW[chainAW.length - 1];
            _localBuildDirects(deepSp, 199, "s-aw-");
            uint256 g = _measureInvest(deepSp, 100 * WAD, "s-abs-worst");
            _logGas("[8/8] ABSOLUTE WORST invest (depth=1000 + 200th direct)", g);
        }

        emit log_string("============================================================");
        emit log_string("  END OF GAS ANALYSIS SUMMARY");
        emit log_string("============================================================");
    }
}
