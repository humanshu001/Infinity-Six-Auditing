// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

// =============================================================================
// BaseFork.t.sol -- the SINGLE shared harness for the Infinity-Six audit suite.
// =============================================================================
//
// What this file does
// -------------------
// 1. Forks BSC mainnet (`vm.createSelectFork`) using the `BSC_RPC_URL` env var
//    (or a public node default). An optional `BSC_BLOCK_NUMBER` env var pins the
//    fork to a specific block so test runs are reproducible.
//
// 2. Wires the LIVE deployed Infinity-Six contracts:
//        - `i6` token   0xd2e052c7faE5DDeD7A7B2CdDd27B5d75D18A1593
//        - system       0x51A36b17b5dbD013C632dCb411F71E935392fe5e
//        - DAO multisig 0x4EA9802681Fb877DE5407974E63F197EE754032f
//        - USDT/i6 pair 0x13D55200c298Ff1caE3136BE0dd889626DEAC782
//        - PancakeRouter 0x10ED43C718714eb63d5aA57B78B54704E256024E
//        - BSC-USD       0x55d398326f99059fF775485246999027B3197955
//    These addresses come from `i6systemcontract-values.md` / `i6token-values.md`.
//
// 3. After the fork is selected, `_verifyMainnetState()` re-reads several
//    on-chain values (`buyingEnabled`, `liquidityPair`, `systemContract`,
//    `totalSupply`, `maxDownlineDepth`, `launchTime`) and asserts they match
//    the documented mainnet snapshot. This is the "fork sanity check" that
//    guarantees the test is actually running against BSC mainnet and not a
//    stale local cache.
//
// 4. Exposes a single shared layer of helpers used by every audit-suite test:
//        - `_deployFreshSystem()` clones the i6 token + system into the fork
//          with a fresh USDT/i6 pair seeded against the real PancakeSwap
//          factory. Required for tests that need clean MLM state (the live
//          system has ORIGIN + existing investors that cannot be reset).
//        - `_dealUsdt`, `_fundAndApprove`  -- fund test wallets with BSC-USD.
//        - `_rollBlock`, `_advanceTime`     -- BSC-paced time/block helpers.
//        - `_invest`, `_withdraw`, `_withdrawAndSell` -- action helpers.
//        - `_buildDownlineChain` -- build an N-long referral chain ending in
//          ORIGIN_FRESH (used by depth / gas tests).
//        - `_userTotalDeposits`, `_userIsBoosted`, `_userIsCapped`, ...
//          -- typed getters wrapping the 27-element `users()` tuple.
//
// =============================================================================
// Analysis -- is the original BaseFork.t.sol correct?
// -----------------------------------------------------------------------------
//
// The previous BaseFork.t.sol was CORRECT in its core wiring -- it forked BSC
// via `vm.createSelectFork`, pinned the right contract addresses, labelled
// them for traces, and asserted `buyingEnabled == false` / `liquidityPair ==
// PAIR` / `systemContract == SYSTEM` / `maxDownlineDepth == 1000` /
// `launchTime > 0`. Those checks confirm the fork is live BSC, not a blank
// EVM, and that the on-chain configuration matches the documented snapshot.
//
// Issues identified and addressed in this rewrite:
//
//   (a) NO BLOCK PIN. `vm.createSelectFork(rpc)` without a block number uses
//       whatever the RPC reports as `latest`. That means re-running the same
//       test on a different day produces different results because the fork
//       advances. FIXED by reading optional `BSC_BLOCK_NUMBER` env var and
//       pinning when set.
//
//   (b) MINIMAL INTERFACES. The original interfaces exposed only ~15
//       functions, enough for a sanity check but not enough to drive an
//       invest/withdraw flow, read `users()`, or rescue tokens. FIXED by
//       importing the concrete contracts directly so every public function
//       and the full `users()` tuple are available.
//
//   (c) NO HELPERS. The original file ended at the verification check; every
//       test had to re-implement funding, time advance, pair seeding, and
//       fresh deployment. FIXED by adding the helper layer above.
//
//   (d) NO FRESH-DEPLOY PATH. Many invariant / economic tests need a clean
//       MLM tree that is impossible to create on the live contract (ORIGIN
//       already exists, existing users have invested, `launchTime` has
//       already moved). FIXED with `_deployFreshSystem()` which clones the
//       contracts into the fork and seeds a real PancakeSwap-V2 pair.
//
//   (e) SOLIDITY VERSION. The original used `pragma solidity ^0.8.24` while
//       the actual contracts use `^0.8.34`. Compile worked because Foundry
//       picks the highest required version, but the pragma should match the
//       contracts being tested. Updated to `^0.8.34`.
//
// Conclusion: BaseFork.t.sol IS forking BSC mainnet correctly. The
// `_verifyMainnetState()` block is the on-chain sanity check that proves it.
// The improvements above turn it from "fork-correct but bare" into a fully
// usable shared harness.
// =============================================================================

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

// ----- PancakeSwap V2 interfaces (subset used by the harness) ----------------

interface IV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IV2Router {
    function factory() external view returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
}

interface IV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sync() external;
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

// =============================================================================
// BaseForkSetup
// =============================================================================

contract BaseForkSetup is Test {

    // ----- LIVE BSC MAINNET ADDRESSES (i6*-values.md) ------------------------

    address constant TOKEN  = 0xd2e052c7faE5DDeD7A7B2CdDd27B5d75D18A1593;
    address constant SYSTEM = 0x51A36b17b5dbD013C632dCb411F71E935392fe5e;
    address constant DAO    = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant PAIR   = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant USDT   = 0x55d398326f99059fF775485246999027B3197955;

    // Hardcoded constants in the system contract.
    address constant ORIGIN_LIVE = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    uint256 constant WAD = 1e18;

    // ----- LIVE CONTRACT HANDLES (concrete types) ---------------------------

    InfinitySixToken  internal token;
    InfinitySixSystem internal system;
    IV2Router         internal router;
    IV2Pair           internal livePair;

    // ----- FRESH-DEPLOY HANDLES (populated by _deployFreshSystem) -----------

    InfinitySixToken  internal freshToken;
    InfinitySixSystem internal freshSystem;
    IV2Pair           internal freshPair;
    address           internal freshPairAddr;
    address           internal freshDao;        // mock DAO controller for fresh deploy
    address           internal freshOrigin;     // first investor in fresh system, treated as ORIGIN

    // ----- TEST WALLETS -----------------------------------------------------

    address attacker;
    address attacker2;
    address attacker3;
    address whale;
    address randomUser;

    uint256 snapshotId;

    // BSC block pacing (3s blocks).
    uint256 internal currentBlock;
    uint256 internal currentTimestamp;

    // ------------------------------------------------------------------------
    // setUp
    // ------------------------------------------------------------------------

    function setUp() public virtual {
        // Reproducibility: pin to BSC_BLOCK_NUMBER when set, else use latest.
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-rpc.publicnode.com"));
        uint256 pinnedBlock = vm.envOr("BSC_BLOCK_NUMBER", uint256(0));
        if (pinnedBlock != 0) {
            vm.createSelectFork(rpc, pinnedBlock);
        } else {
            vm.createSelectFork(rpc);
        }

        token  = InfinitySixToken(TOKEN);
        system = InfinitySixSystem(SYSTEM);
        router = IV2Router(ROUTER);
        livePair = IV2Pair(PAIR);

        attacker   = makeAddr("attacker");
        attacker2  = makeAddr("attacker2");
        attacker3  = makeAddr("attacker3");
        whale      = makeAddr("whale");
        randomUser = makeAddr("randomUser");

        vm.label(TOKEN,  "InfinitySixToken");
        vm.label(SYSTEM, "InfinitySixSystem");
        vm.label(DAO,    "DAO");
        vm.label(PAIR,   "LiquidityPair");
        vm.label(ROUTER, "PancakeRouter");
        vm.label(USDT,   "USDT");
        vm.label(ORIGIN_LIVE, "ORIGIN");

        vm.label(attacker,   "Attacker");
        vm.label(attacker2,  "Attacker2");
        vm.label(attacker3,  "Attacker3");
        vm.label(whale,      "Whale");
        vm.label(randomUser, "RandomUser");

        currentBlock = block.number;
        currentTimestamp = block.timestamp;

        snapshotId = vm.snapshotState();

        _verifyMainnetState();
    }

    function resetForkState() internal {
        vm.revertToState(snapshotId);
        snapshotId = vm.snapshotState();
    }

    /// @dev Asserts that the fork is the live BSC chain by re-reading the
    ///      documented mainnet values. If any assert fails, the fork is not
    ///      pointing at BSC mainnet (wrong RPC, wrong chain id, etc.).
    function _verifyMainnetState() internal view {
        assertEq(token.buyingEnabled(),       false, "buyingEnabled must be false on mainnet");
        assertEq(token.liquidityPair(),       PAIR,  "liquidityPair mismatch vs mainnet");
        assertEq(token.systemContract(),      SYSTEM, "systemContract mismatch vs mainnet");
        assertGt(token.totalSupply(),         0,     "token totalSupply should be > 0");
        assertEq(system.maxDownlineDepth(),   1000,  "maxDownlineDepth mismatch vs mainnet");
        assertGt(system.launchTime(),         0,     "launchTime should be set");
        assertEq(token.DAOMultisigController(), DAO, "token DAO controller mismatch");
        assertEq(system.DAOMultisigController(), DAO, "system DAO controller mismatch");
    }

    // ========================================================================
    // FUND HELPERS -- BSC-USD has no public faucet, use `deal` cheatcode.
    // ========================================================================

    /// @dev Lazy whale that funds via a single `deal` then dispenses to all
    ///      other actors. This minimises the number of public-RPC storage
    ///      lookups required during heavy tests (one deal call across the
    ///      whole test, not one per investor).
    function _ensureWhaleFunded(uint256 minAmount) internal {
        uint256 bal = IERC20(USDT).balanceOf(whale);
        if (bal < minAmount) {
            deal(USDT, whale, minAmount + bal, true);
        }
    }

    function _dealUsdt(address to, uint256 amount) internal {
        // Re-route deals through the whale to minimise direct `deal` calls.
        _ensureWhaleFunded(amount);
        vm.prank(whale, whale);
        IERC20(USDT).transfer(to, amount);
    }

    function _fundAndApprove(address user, uint256 usdtAmount, address spender) internal {
        _dealUsdt(user, usdtAmount);
        vm.prank(user, user);
        IERC20(USDT).approve(spender, type(uint256).max);
    }

    // ========================================================================
    // TIME / BLOCK HELPERS -- mimic BSC's 3-second blocks.
    // ========================================================================

    function _rollBlock() internal {
        currentBlock += 1;
        vm.roll(currentBlock);
        currentTimestamp += 3;
        vm.warp(currentTimestamp);
    }

    function _advanceTime(uint256 secs) internal {
        currentTimestamp += secs;
        vm.warp(currentTimestamp);
        // Advance block proportionally (1 block per 3s).
        uint256 blocks = secs / 3;
        if (blocks > 0) {
            currentBlock += blocks;
            vm.roll(currentBlock);
        }
    }

    // ========================================================================
    // FRESH SYSTEM DEPLOY -- needed for any test that wants a clean MLM tree.
    // ========================================================================

    /// @notice Clones token+system into the fork and seeds a fresh USDT/i6
    ///         pair against the real PancakeSwap V2 factory. The seeded pool
    ///         starts at roughly 1 USDT per i6 unless overridden.
    function _deployFreshSystem() internal {
        _deployFreshSystem(1_000_000 * WAD, 1_000_000 * WAD);
    }

    function _deployFreshSystem(uint256 seedUsdt, uint256 seedI6) internal {
        freshDao = makeAddr("freshDAO");
        vm.label(freshDao, "FreshDAO");

        // Deployer = this test contract. Initial supply (2x seed) so the test
        // contract can fund the pool seeding.
        freshToken = new InfinitySixToken(freshDao, seedI6 * 2);

        IV2Factory factory = IV2Factory(router.factory());
        freshPairAddr = factory.getPair(USDT, address(freshToken));
        if (freshPairAddr == address(0)) {
            freshPairAddr = factory.createPair(USDT, address(freshToken));
        }
        freshPair = IV2Pair(freshPairAddr);
        vm.label(freshPairAddr, "FreshPair");

        freshSystem = new InfinitySixSystem(USDT, address(freshToken), ROUTER, freshPairAddr);
        vm.label(address(freshToken),  "FreshToken");
        vm.label(address(freshSystem), "FreshSystem");

        // The system contract sets DAOMultisigController = msg.sender in its
        // constructor (= this test contract). Migrate to the test DAO so the
        // rest of the harness can prank `freshDao` for any DAO action.
        freshSystem.updateDAOMultisignController(freshDao);

        // DAO must wire up the token.
        vm.startPrank(freshDao);
        freshToken.setSystemContract(address(freshSystem));
        freshToken.setLiquidityPair(freshPairAddr);
        vm.stopPrank();

        // Seed the fresh USDT/i6 pair so getSpotPrice() has reserves.
        _seedFreshPool(seedUsdt, seedI6);

        // The fresh system's launchTime = block.timestamp of deploy. Advance
        // past the 3-day post-launch withdrawal gate so withdraw() is callable.
        _advanceTime(3 days + 1);

        // The fresh system's ORIGIN_MEMBER_ID is the same hardcoded address
        // as the live system (it is a `constant`). We need it active in the
        // fresh state too; the constructor seeded it with 50,000 USDT
        // genesis deposit, so it is already "active".
        freshOrigin = ORIGIN_LIVE;
    }

    function _seedFreshPool(uint256 usdtAmount, uint256 i6Amount) internal {
        _dealUsdt(address(this), usdtAmount);
        IERC20(USDT).approve(ROUTER, type(uint256).max);
        freshToken.approve(ROUTER, type(uint256).max);
        router.addLiquidity(
            USDT,
            address(freshToken),
            usdtAmount,
            i6Amount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // ========================================================================
    // ACTION HELPERS (fresh system) -- live system can be driven the same
    // way by calling system.invest()/withdraw() directly with vm.prank.
    // ========================================================================

    /// @dev Invest into the fresh system. Same-block lock applies, so we roll
    ///      a block before each call.
    function _investFresh(address user, uint256 usdt, address sponsor) internal {
        _fundAndApprove(user, usdt, address(freshSystem));
        _rollBlock();
        vm.prank(user, user);
        freshSystem.invest(usdt, sponsor, 0);
    }

    /// @dev Withdraw from the fresh system. The user must have an active
    ///      position and the 1h cooldown / 3-day launch gate must have passed.
    function _withdrawFresh(address user) internal {
        _rollBlock();
        vm.prank(user, user);
        freshSystem.withdraw();
    }

    /// @dev Withdraw then immediately dump the minted i6 into the pool.
    function _withdrawAndSellFresh(address user) internal returns (uint256 usdtOut) {
        uint256 i6Before = freshToken.balanceOf(user);
        _withdrawFresh(user);
        uint256 i6Got = freshToken.balanceOf(user) - i6Before;
        if (i6Got == 0) return 0;

        vm.startPrank(user, user);
        freshToken.approve(ROUTER, type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = address(freshToken);
        path[1] = USDT;
        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        _rollBlock();
        router.swapExactTokensForTokens(i6Got, 0, path, user, block.timestamp);
        usdtOut = IERC20(USDT).balanceOf(user) - usdtBefore;
        vm.stopPrank();
    }

    // ========================================================================
    // TREE BUILDERS (fresh system)
    // ========================================================================

    /// @notice Build a referral chain of `depth` accounts where account[i]
    ///         is sponsored by account[i-1] and account[0] is sponsored by
    ///         ORIGIN. Each account invests `MIN_INVESTMENT` (100 USDT).
    function _buildDownlineChain(uint256 depth) internal returns (address[] memory chain) {
        chain = new address[](depth);
        uint256 minInvestment = 100 * WAD;
        address sponsor = freshOrigin;
        for (uint256 i = 0; i < depth; i++) {
            address u = makeAddr(string.concat("chain-", vm.toString(i)));
            chain[i] = u;
            _investFresh(u, minInvestment, sponsor);
            sponsor = u;
        }
    }

    /// @notice Sponsor `n` direct referrals under `sponsor`, each investing
    ///         `MIN_INVESTMENT`. `sponsor` must already be active.
    function _buildDirects(address sponsor, uint256 n, string memory label)
        internal
        returns (address[] memory directs)
    {
        directs = new address[](n);
        uint256 minInvestment = 100 * WAD;
        for (uint256 i = 0; i < n; i++) {
            address u = makeAddr(string.concat(label, "-", vm.toString(i)));
            directs[i] = u;
            _investFresh(u, minInvestment, sponsor);
        }
    }

    // ========================================================================
    // TYPED VIEW HELPERS -- the `users()` autogenerated getter returns a
    // 27-element tuple. These wrappers expose just the fields tests need.
    // ========================================================================

    function _userTotalDeposits(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (v,,,,,,,,,,,,,,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userDirectBonus(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (, v,,,,,,,,,,,,,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userDirectCount(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,, v,,,,,,,,,,,,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userTotalDownlineBusiness(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,,,,,, v,,,,,,,,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userIsUplineEligible(InfinitySixSystem sys, address u) internal view returns (bool v) {
        (,,,,,,,,, v,,,,,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userPendingUplineIncome(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,,,,,,,,,,,,, v,,,,,,,,,,,,,) = sys.users(u);
    }

    function _userCurrentRank(InfinitySixSystem sys, address u) internal view returns (uint8 v) {
        (,,,,,,,,,,,,,, v,,,,,,,,,,,,) = sys.users(u);
    }

    function _userUnwithdrawnSalary(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,,,,,,,,,,,,,,,,, v,,,,,,,,,) = sys.users(u);
    }

    function _userTotalWithdrawn(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,,,,,,,,,,,,,,,,,, v,,,,,,,,) = sys.users(u);
    }

    function _userIsCapped(InfinitySixSystem sys, address u) internal view returns (bool v) {
        (,,,,,,,,,,,,,,,,,,,, v,,,,,,) = sys.users(u);
    }

    function _userFreshBusiness(InfinitySixSystem sys, address u) internal view returns (uint256 v) {
        (,,,,,,,,,,,,,,,,,,,,,, v,,,,) = sys.users(u);
    }

    function _userIsBoosted(InfinitySixSystem sys, address u) internal view returns (bool v) {
        (,,,,,,,,,,,,,,,,,,,,,,,,,, v) = sys.users(u);
    }

    // ------------------------------------------------------------------------
    // Pretty-print helpers used by every test's result printer.
    // ------------------------------------------------------------------------

    function _logHeader(string memory title) internal pure {
        // forge-std's console2 already mostly does this; here we keep it
        // dependency-free with emit log so result.txt grep stays simple.
    }

    function _toUsdt(uint256 wad) internal pure returns (string memory) {
        return string.concat(_toFixed(wad, 18), " USDT");
    }

    function _toI6(uint256 wad) internal pure returns (string memory) {
        return string.concat(_toFixed(wad, 18), " i6");
    }

    function _toFixed(uint256 x, uint8 decimals) internal pure returns (string memory) {
        uint256 unit = 10 ** decimals;
        uint256 whole = x / unit;
        uint256 frac  = x % unit;
        return string.concat(vm.toString(whole), ".", _pad(vm.toString(frac), decimals));
    }

    function _pad(string memory s, uint256 length) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length >= length) return s;
        bytes memory pad = new bytes(length - b.length);
        for (uint256 i = 0; i < pad.length; i++) pad[i] = "0";
        return string.concat(string(pad), s);
    }
}
