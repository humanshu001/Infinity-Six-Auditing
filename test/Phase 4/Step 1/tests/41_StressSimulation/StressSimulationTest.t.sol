// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

/// =============================================================================
/// 41_StressSimulation -- 10,000-user economic stress + death-spiral run
/// =============================================================================
///
/// Goal
/// ----
/// Drive the protocol with a realistic load (10k users * $100 each = ~$1M USDT
/// inflow) and watch what happens to:
///   * pool reserves (USDT + i6),
///   * spot price (`getSpotPrice()` reads),
///   * i6 total supply (mint inflation),
///   * USDT pulled out vs USDT deposited.
///
/// Three scenarios are exercised:
///   A. BEST   -- deep liquidity (10M / 10M). 10k invest then 10k withdraw+dump.
///                 Expected: price stays near 1 USDT/i6 throughout.
///   B. WORST  -- thin liquidity (100k / 100k). Same 10k load. Expected: price
///                 swings dramatically; pool partially drained.
///   C. DEATH SPIRAL -- thin pool + withdraws batched into 10 waves so each
///                 wave mints i6 against the previous wave's depressed spot
///                 price. Logs reserves + supply per wave so the spiral is
///                 visible as numbers, not a claim.
///
/// Tree shape
/// ----------
/// MAX_DIRECTS = 200 in the system contract, so 10k cannot all sit under one
/// sponsor. Plumbing:
///   layer 0  ORIGIN_FRESH (hardcoded constant)
///   layer 1  50 sponsors under ORIGIN
///   layer 2  10,000 end users, 200 per L1 sponsor (fills MAX_DIRECTS)
/// 10,050 total invests. INVEST_AMT = 100 USDT each (= MIN_INVESTMENT).
///
/// Why mocks
/// ---------
/// 10k users on the real BSC fork hits historical-state pruning on the public
/// RPC (USDT contract state at deep slots is evicted). The mocks here:
///   * StressMockUSDT  -- OZ ERC20 with public mint.
///   * StressMockPair  -- holds real balances, exposes reserves, has a
///                        router-only `release` so the router can push the
///                        output token out on swaps and set reserves directly.
///   * StressMockRouter -- PancakeSwap V2 math with the standard 0.25% fee.
///                        `swapExactTokensForTokens`, `addLiquidity`, `quote`,
///                        `getAmountsOut`, `factory()` and `getPair()` are
///                        implemented exactly as the system contract uses them.
///
/// Real constant-product math is preserved, so the price trajectory matches
/// what would happen on real PancakeSwap under the same trades.
///
/// Run commands
/// ------------
/// Full 10k run (long):
///     forge test --match-path 'test/Phase 4/Step 1/tests/41_StressSimulation/*.sol' -vv
/// Smoke (1k users):
///     STRESS_USERS=1000 forge test --match-path 'test/Phase 4/Step 1/tests/41_StressSimulation/*.sol' -vv
/// =============================================================================

contract StressMockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}
    function mintFor(address to, uint256 amount) external { _mint(to, amount); }
}

contract StressMockPair {
    address public token0;
    address public token1;
    uint112 internal _r0;
    uint112 internal _r1;
    address public router;

    constructor(address _t0, address _t1, address _router) {
        token0 = _t0;
        token1 = _t1;
        router = _router;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_r0, _r1, uint32(block.timestamp));
    }

    function sync() external {
        _r0 = uint112(IERC20(token0).balanceOf(address(this)));
        _r1 = uint112(IERC20(token1).balanceOf(address(this)));
    }

    function release(address to, address tok, uint256 amt) external {
        require(msg.sender == router, "pair: only router");
        IERC20(tok).transfer(to, amt);
    }

    function setReserves(uint112 r0, uint112 r1) external {
        require(msg.sender == router, "pair: only router");
        _r0 = r0;
        _r1 = r1;
    }
}

contract StressMockRouter {
    address public immutable usdt;
    address public immutable i6;
    StressMockPair public pair;
    address public mockFactory;

    constructor(address _usdt, address _i6) {
        usdt = _usdt;
        i6 = _i6;
        mockFactory = address(this);
    }

    function setPair(address _pair) external { pair = StressMockPair(_pair); }

    function factory() external view returns (address) { return mockFactory; }

    function getPair(address, address) external view returns (address) { return address(pair); }

    function _amountOut(uint256 amountIn, uint256 rIn, uint256 rOut) internal pure returns (uint256) {
        uint256 amtInFee = amountIn * 9975;
        return (amtInFee * rOut) / (rIn * 10000 + amtInFee);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        (uint112 r0, uint112 r1,) = pair.getReserves();
        bool inIsT0 = path[0] == pair.token0();
        (uint256 rIn, uint256 rOut) = inIsT0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        amounts[1] = _amountOut(amountIn, rIn, rOut);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(pair), amountIn);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        bool inIsT0 = path[0] == pair.token0();
        (uint256 rIn, uint256 rOut) = inIsT0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 out = _amountOut(amountIn, rIn, rOut);
        require(out >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        pair.release(to, path[1], out);

        if (inIsT0) {
            pair.setReserves(uint112(rIn + amountIn), uint112(rOut - out));
        } else {
            pair.setReserves(uint112(rOut - out), uint112(rIn + amountIn));
        }

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = out;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return (amountA * reserveB) / reserveA;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external returns (uint256, uint256, uint256) {
        IERC20(tokenA).transferFrom(msg.sender, address(pair), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(pair), amountBDesired);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        bool aIsT0 = tokenA == pair.token0();
        (uint112 newR0, uint112 newR1) = aIsT0
            ? (uint112(uint256(r0) + amountADesired), uint112(uint256(r1) + amountBDesired))
            : (uint112(uint256(r0) + amountBDesired), uint112(uint256(r1) + amountADesired));
        pair.setReserves(newR0, newR1);

        return (amountADesired, amountBDesired, 1);
    }
}

contract StressSimulationTest is Test {

    // ----- Constants -----
    uint256 internal constant WAD = 1e18;
    address internal constant ORIGIN_HARDCODED = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    // ----- Tree constants -----
    uint256 internal constant SPONSORS_PER_LAYER = 50;
    uint256 internal constant USERS_PER_SPONSOR  = 200;
    uint256 internal constant INVEST_AMT         = 100 * WAD;
    uint256 internal constant DEATH_WAVES        = 10;

    // ----- BSC-style block pacing -----
    uint256 internal currentBlock;
    uint256 internal currentTimestamp;

    // ----- Runtime config -----
    uint256 internal nUsers;
    uint256 internal snapshotInterval;

    // ----- Mock infra (rebuilt per scenario) -----
    StressMockUSDT    internal mUsdt;
    StressMockRouter  internal mRouter;
    StressMockPair    internal mPair;
    InfinitySixToken  internal mToken;
    InfinitySixSystem internal mSystem;
    address           internal mDao;
    address           internal mOrigin;

    // ----- Tree storage -----
    address[] internal layerOneSponsors;
    address[] internal endUsers;

    // ----- Accumulators -----
    uint256 internal totalUsdtIn;
    uint256 internal totalUsdtOut;
    uint256 internal totalI6Minted;

    function setUp() public {
        // Start far enough into "the future" that launchTime + 3 days fits.
        currentTimestamp = 1_900_000_000; // ~2030
        currentBlock     = 50_000_000;
        vm.warp(currentTimestamp);
        vm.roll(currentBlock);

        nUsers = vm.envOr("STRESS_USERS", uint256(SPONSORS_PER_LAYER * USERS_PER_SPONSOR));
        snapshotInterval = nUsers >= DEATH_WAVES ? nUsers / DEATH_WAVES : 1;
    }

    function _rollBlock() internal {
        currentBlock += 1;
        vm.roll(currentBlock);
        currentTimestamp += 3;
        vm.warp(currentTimestamp);
    }

    function _advanceTime(uint256 secs) internal {
        currentTimestamp += secs;
        vm.warp(currentTimestamp);
        uint256 blocks = secs / 3;
        if (blocks > 0) {
            currentBlock += blocks;
            vm.roll(currentBlock);
        }
    }

    // =================================================================
    // Mock-stack deploy (sized for the scenario)
    // =================================================================
    function _deployStressStack(uint256 seedUsdt, uint256 seedI6) internal {
        mDao = makeAddr("mDao");
        mOrigin = ORIGIN_HARDCODED; // hardcoded constant inside the system

        mUsdt   = new StressMockUSDT();
        mRouter = new StressMockRouter(address(mUsdt), address(0)); // i6 unset; set after token deploy

        // Mint initial i6 supply to this test contract so we can seed the pair.
        // InfinitySixToken constructor: (_dao, initialSupply) -> initialSupply
        // minted to msg.sender; isWhitelisted[msg.sender] = true.
        mToken = new InfinitySixToken(mDao, seedI6 * 2);

        // mock pair: token0 = USDT, token1 = i6
        mPair = new StressMockPair(address(mUsdt), address(mToken), address(mRouter));
        mRouter.setPair(address(mPair));

        mSystem = new InfinitySixSystem(
            address(mUsdt),
            address(mToken),
            address(mRouter),
            address(mPair)
        );
        mSystem.updateDAOMultisignController(mDao);

        // DAO wires the token.
        vm.startPrank(mDao);
        mToken.setSystemContract(address(mSystem));
        mToken.setLiquidityPair(address(mPair));
        vm.stopPrank();

        // Seed the pair: USDT minted to this contract, i6 already held.
        mUsdt.mintFor(address(this), seedUsdt);
        IERC20(address(mUsdt)).transfer(address(mPair), seedUsdt);
        IERC20(address(mToken)).transfer(address(mPair), seedI6);
        mPair.sync();

        // System constructor seeds ORIGIN with 50,000 USDT deposit. The system
        // also enforces a 3-day launch gate before withdraw; advance past it.
        _advanceTime(3 days + 1);

        // Reset accumulators.
        totalUsdtIn = 0;
        totalUsdtOut = 0;
        totalI6Minted = 0;
    }

    // =================================================================
    // Action helpers (mock-stack versions)
    // =================================================================
    function _stressFund(address user, uint256 amt) internal {
        mUsdt.mintFor(user, amt);
        vm.prank(user, user);
        IERC20(address(mUsdt)).approve(address(mSystem), type(uint256).max);
    }

    function _stressInvest(address user, uint256 amt, address sponsor) internal {
        _stressFund(user, amt);
        _rollBlock();
        vm.prank(user, user);
        mSystem.invest(amt, sponsor, 0);
    }

    /// Withdraw, then immediately sell the minted i6 via the mock router.
    function _stressWithdrawAndSell(address user) internal returns (uint256 usdtOut) {
        // 1h cooldown after every withdraw. Use 1h+1s for safety.
        _advanceTime(1 hours + 1);
        _rollBlock();

        uint256 i6Before = mToken.balanceOf(user);
        vm.prank(user, user);
        try mSystem.withdraw() {
            // OK
        } catch {
            return 0;
        }
        uint256 i6Got = mToken.balanceOf(user) - i6Before;
        if (i6Got == 0) return 0;

        // Approve and sell on the mock router.
        vm.startPrank(user, user);
        mToken.approve(address(mRouter), type(uint256).max);
        vm.stopPrank();

        address[] memory path = new address[](2);
        path[0] = address(mToken);
        path[1] = address(mUsdt);

        uint256 usdtBefore = IERC20(address(mUsdt)).balanceOf(user);
        _rollBlock();
        vm.prank(user, user);
        mRouter.swapExactTokensForTokens(i6Got, 0, path, user, block.timestamp);
        usdtOut = IERC20(address(mUsdt)).balanceOf(user) - usdtBefore;
    }

    // =================================================================
    // TEST A -- BEST CASE
    // =================================================================
    function test_BEST_case_deep_liquidity_stable_run() public {
        emit log("==========================================================");
        emit log("BEST CASE: 5.9532M USDT / 4.15237M i6 seed (10x live), 10k users");
        emit log("==========================================================");

        _deployStressStack(5_953_200 * WAD, 4_152_370 * WAD);
        _logPoolState("seed");
        _emitCsv("BEST", 0);

        _runInvestPhase("BEST");
        _logPoolState("post-invest");
        _emitCsv("BEST", 9999);

        _advanceTime(30 days);
        emit log("--- 30 days matured ---");

        _runWithdrawSellPhase("BEST");
        _logPoolState("post-withdraw+sell");
        _emitCsv("BEST", 19999);

        _logFinalAccounting("BEST");
    }

    // =================================================================
    // TEST B -- WORST CASE
    // =================================================================
    // =================================================================
    // TEST AVERAGE -- middle ground (3x live pool depth)
    // =================================================================
    function test_AVERAGE_case_mid_liquidity_general_scenario() public {
        emit log("==========================================================");
        emit log("AVERAGE CASE: 1.78596M USDT / 1.24571M i6 seed (3x live), 10k users");
        emit log("==========================================================");

        _deployStressStack(1_785_960 * WAD, 1_245_711 * WAD);
        _logPoolState("seed");
        _emitCsv("AVG", 0);

        _runInvestPhase("AVG");
        _logPoolState("post-invest");
        _emitCsv("AVG", 9999);

        _advanceTime(30 days);
        emit log("--- 30 days matured ---");

        _runWithdrawSellPhase("AVG");
        _logPoolState("post-withdraw+sell");
        _emitCsv("AVG", 19999);

        _logFinalAccounting("AVERAGE");
    }

    function test_WORST_case_thin_liquidity_stress() public {
        emit log("==========================================================");
        emit log("WORST CASE: 595,320 USDT / 415,237 i6 seed (LIVE), 10k users");
        emit log("==========================================================");

        _deployStressStack(595_320 * WAD, 415_237 * WAD);
        _logPoolState("seed");
        _emitCsv("WORST", 0);

        _runInvestPhase("WORST");
        _logPoolState("post-invest");
        _emitCsv("WORST", 9999);

        _advanceTime(30 days);
        emit log("--- 30 days matured ---");

        _runWithdrawSellPhase("WORST");
        _logPoolState("post-withdraw+sell");
        _emitCsv("WORST", 19999);

        _logFinalAccounting("WORST");
    }

    // =================================================================
    // TEST C -- DEATH SPIRAL
    // =================================================================
    function test_DEATH_SPIRAL_progressive_drain() public {
        emit log("==========================================================");
        emit log("DEATH SPIRAL: 595,320 USDT / 415,237 i6 LIVE seed, 10 waves");
        emit log("==========================================================");

        _deployStressStack(595_320 * WAD, 415_237 * WAD);
        _logPoolState("seed");
        _emitCsv("DEATH", 0);

        _runInvestPhase("DEATH");
        _advanceTime(30 days);
        _logPoolState("post-invest + 30d");
        _emitCsv("DEATH", 1);

        uint256 perWave = endUsers.length / DEATH_WAVES;
        emit log_named_uint("per-wave size", perWave);

        for (uint256 w = 0; w < DEATH_WAVES; w++) {
            uint256 start = w * perWave;
            uint256 end   = start + perWave;

            uint256 supplyBefore = mToken.totalSupply();
            uint256 waveUsdtOut;

            for (uint256 i = start; i < end; i++) {
                waveUsdtOut += _stressWithdrawAndSell(endUsers[i]);
            }

            uint256 mintedThisWave = mToken.totalSupply() - supplyBefore;
            totalI6Minted += mintedThisWave;
            totalUsdtOut  += waveUsdtOut;

            emit log("----------------------------------------------------------");
            emit log_named_uint("WAVE", w + 1);
            emit log_named_uint("  i6 minted to withdrawers (wei)", mintedThisWave);
            emit log_named_uint("  USDT pulled out of pool   (wei)", waveUsdtOut);
            _logPoolState(string.concat("end of wave ", vm.toString(w + 1)));
            emit log(string.concat(
                "WAVECSV,DEATH,", vm.toString(w + 1),
                ",", vm.toString(mintedThisWave),
                ",", vm.toString(waveUsdtOut)
            ));
            _emitCsv("DEATH", 100 + w + 1);
        }

        _logFinalAccounting("DEATH SPIRAL");
        _logSpiralVerdict();
    }

    // =================================================================
    // Phase helpers
    // =================================================================
    function _runInvestPhase(string memory scenario) internal {
        emit log_named_uint("invest phase: nUsers", nUsers);

        layerOneSponsors = new address[](SPONSORS_PER_LAYER);
        for (uint256 i = 0; i < SPONSORS_PER_LAYER; i++) {
            address s = makeAddr(string.concat("L1-", vm.toString(i)));
            layerOneSponsors[i] = s;
            _stressInvest(s, INVEST_AMT, mOrigin);
            totalUsdtIn += INVEST_AMT;
        }

        endUsers = new address[](nUsers);
        for (uint256 i = 0; i < nUsers; i++) {
            address u = makeAddr(string.concat("U-", vm.toString(i)));
            endUsers[i] = u;
            address sponsor = layerOneSponsors[i / USERS_PER_SPONSOR];
            _stressInvest(u, INVEST_AMT, sponsor);
            totalUsdtIn += INVEST_AMT;

            if (i != 0 && i % snapshotInterval == 0) {
                _logPoolState(string.concat("invest@", vm.toString(i)));
                _emitCsv(scenario, i);
            }
        }
    }

    function _runWithdrawSellPhase(string memory scenario) internal {
        emit log_named_uint("withdraw+sell phase: users", endUsers.length);
        for (uint256 i = 0; i < endUsers.length; i++) {
            uint256 supplyBefore = mToken.totalSupply();
            uint256 usdtOut = _stressWithdrawAndSell(endUsers[i]);
            totalUsdtOut  += usdtOut;
            totalI6Minted += (mToken.totalSupply() - supplyBefore);

            if (i != 0 && i % snapshotInterval == 0) {
                _logPoolState(string.concat("withdraw@", vm.toString(i)));
                _emitCsv(scenario, 10000 + i);
            }
        }
    }

    function _emitCsv(string memory scenario, uint256 step) internal {
        (uint112 r0, uint112 r1,) = mPair.getReserves();
        address t0 = mPair.token0();
        (uint256 ruSdt, uint256 rI6) = t0 == address(mUsdt)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
        uint256 spot = rI6 == 0 ? 0 : (ruSdt * WAD) / rI6;
        uint256 supply = mToken.totalSupply();
        emit log(string.concat(
            "CSV,", scenario,
            ",", vm.toString(step),
            ",", vm.toString(ruSdt),
            ",", vm.toString(rI6),
            ",", vm.toString(spot),
            ",", vm.toString(supply)
        ));
    }

    // =================================================================
    // Snapshot helpers
    // =================================================================
    function _logPoolState(string memory label) internal {
        (uint112 r0, uint112 r1,) = mPair.getReserves();
        address t0 = mPair.token0();
        (uint256 ruSdt, uint256 rI6) = t0 == address(mUsdt)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        uint256 spot = rI6 == 0 ? 0 : (ruSdt * WAD) / rI6;

        emit log_named_string("STATE", label);
        emit log_named_uint("  reserveUSDT (wei)",       ruSdt);
        emit log_named_uint("  reserveI6   (wei)",       rI6);
        emit log_named_uint("  spotPrice USDT/i6 (wad)", spot);
        emit log_named_uint("  i6 totalSupply (wei)",    mToken.totalSupply());
    }

    function _logFinalAccounting(string memory label) internal {
        (uint112 r0, uint112 r1,) = mPair.getReserves();
        address t0 = mPair.token0();
        (uint256 ruSdt, uint256 rI6) = t0 == address(mUsdt)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        emit log("==========================================================");
        emit log_named_string("FINAL ACCOUNTING", label);
        emit log_named_uint("  total USDT invested by users (wei)", totalUsdtIn);
        emit log_named_uint("  total USDT extracted via sells (wei)", totalUsdtOut);
        emit log_named_uint("  total i6 minted to withdrawers (wei)", totalI6Minted);
        emit log_named_uint("  system USDT balance (wei)",   IERC20(address(mUsdt)).balanceOf(address(mSystem)));
        emit log_named_uint("  pool USDT reserve (wei)",     ruSdt);
        emit log_named_uint("  pool i6   reserve (wei)",     rI6);
        emit log_named_uint("  spot USDT/i6 (wad)",          rI6 == 0 ? 0 : (ruSdt * WAD) / rI6);
        emit log_named_uint("  i6 totalSupply (wei)",        mToken.totalSupply());
        if (totalUsdtIn != 0) {
            emit log_named_uint("  payback ratio (out/in permille)", (totalUsdtOut * 1000) / totalUsdtIn);
        }
        emit log("==========================================================");
    }

    function _logSpiralVerdict() internal {
        (uint112 r0, uint112 r1,) = mPair.getReserves();
        address t0 = mPair.token0();
        (uint256 ruSdt, uint256 rI6) = t0 == address(mUsdt)
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        uint256 spot = rI6 == 0 ? 0 : (ruSdt * WAD) / rI6;
        uint256 supply = mToken.totalSupply();

        emit log("---- DEATH SPIRAL VERDICT ----");
        if (ruSdt < 1_000 * WAD) emit log("  pool USDT reserve below 1k -- pool effectively drained");
        if (rI6 > 100_000_000 * WAD) emit log("  pool i6 reserve above 100M -- dump side saturated");
        if (spot != 0 && spot < WAD / 100) emit log("  spot below 0.01 USDT/i6 -- 100x+ collapse");
        if (supply > 100_000_000 * WAD) emit log("  i6 totalSupply above 100M -- mint inflation visible");
        emit log_named_uint("  final spot (wad)",   spot);
        emit log_named_uint("  final supply (wei)", supply);
        emit log_named_uint("  USDT pulled vs deposited (permille)",
            totalUsdtIn == 0 ? 0 : (totalUsdtOut * 1000) / totalUsdtIn);
    }
}
