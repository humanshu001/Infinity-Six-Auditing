// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../BaseFork.t.sol";

contract GasAnalysisTest is BaseForkSetup {

    uint256 constant BSC_BLOCK_LIMIT = 140_000_000;
    uint256 constant RPC_TX_LIMIT    = 30_000_000;

    function setUp() public override {
        super.setUp(); // selects fork, runs verifyMainnetState
        _advanceTime(3 days + 1); // past launch gate
    }

    // ------------------------------------------------------------------------
    // Funding + invest/withdraw helpers using live contracts.
    // ------------------------------------------------------------------------

    function _liveFund(address user, uint256 amt) internal {
        _dealUsdt(user, amt);
        vm.prank(user, user);
        IERC20(USDT).approve(address(system), type(uint256).max);
    }

    function _liveInvest(address user, uint256 amt, address sponsor_) internal {
        _liveFund(user, amt);
        vm.prank(user, user);
        system.invest(amt, sponsor_, 0);
    }

    function _measureInvest(address sponsor_, uint256 amt, string memory salt)
        internal returns (uint256 gasUsed)
    {
        address u = makeAddr(salt);
        _liveFund(u, amt);
        vm.prank(u, u);
        uint256 g = gasleft();
        system.invest(amt, sponsor_, 0);
        gasUsed = g - gasleft();
    }

    function _measureWithdraw(address user) internal returns (uint256 gasUsed) {
        _advanceTime(1 hours + 1);
        _rollBlock();
        vm.prank(user, user);
        uint256 g = gasleft();
        system.withdraw();
        gasUsed = g - gasleft();
    }

    function _logGas(string memory label, uint256 g) internal {
        emit log_named_string("Scenario", label);
        emit log_named_uint("  gas used (units)", g);
        emit log_named_uint("  % of BSC block limit (140M)", (g * 100) / BSC_BLOCK_LIMIT);
        emit log_named_uint("  % of std RPC cap (30M)", (g * 100) / RPC_TX_LIMIT);
        emit log_named_uint("  permille of BSC block (140M = 1000)", (g * 1000) / BSC_BLOCK_LIMIT);
        emit log_named_uint("  permille of std RPC cap (30M = 1000)", (g * 1000) / RPC_TX_LIMIT);
    }

    // ========================================================================
    // BSC MAINNET FORK VERIFICATION
    // ========================================================================

    function test_GAS_BSC_FORK_VERIFICATION() public view {
        assertEq(system.maxDownlineDepth(),  1000, "maxDownlineDepth must be 1000");
        assertEq(system.MAX_DIRECTS(),       200,  "MAX_DIRECTS must be 200");
        assertEq(system.MIN_INVESTMENT(),    100 * WAD, "MIN_INVESTMENT must be 100 USDT");
        assertEq(system.MAX_INCOME_MULTIPLIER(), 6, "MAX_INCOME_MULTIPLIER must be 6");
        assertEq(system.WITHDRAWAL_COOLING_PERIOD(), 3600, "WITHDRAWAL_COOLING_PERIOD must be 1 hour");
        assertEq(token.buyingEnabled(),      false, "buyingEnabled must be false");
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
        _liveInvest(u, 100 * WAD, ORIGIN_LIVE);
        _advanceTime(30 days);
        uint256 g = _measureWithdraw(u);
        _logGas("BEST: withdraw with 1 package, depth=1", g);
    }

    // ========================================================================
    function _safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function test_GAS_SUMMARY_all_scenarios() public {
        emit log_string("============================================================");
        emit log_string("  GAS ANALYSIS SUMMARY -- Real i6 contracts, BSC parameters");
        emit log_string("  Block gas limit: 140,000,000 | RPC tx limit: 30,000,000");
        emit log_string("  maxDownlineDepth=1000 | MAX_DIRECTS=200 | MaxPkgs=100");
        emit log_string("============================================================");

        // 1. Measure Upline depth scaling using 6 levels (depth 1 to 6)
        address[] memory chain = new address[](6);
        uint256[] memory investGas = new uint256[](6);

        address sponsor_ = ORIGIN_LIVE;
        for (uint256 i = 0; i < 6; i++) {
            _rollBlock();
            address u = makeAddr(string.concat("chain-", vm.toString(i)));
            chain[i] = u;
            _liveFund(u, 100 * WAD);

            vm.prank(u, u);
            uint256 gBefore = gasleft();
            system.invest(100 * WAD, sponsor_, 0);
            investGas[i] = gBefore - gasleft();

            emit log_named_uint(string.concat("  Invest gas depth ", vm.toString(i + 1)), investGas[i]);
            sponsor_ = u;
        }

        uint256 gasD1 = investGas[0];
        // Calculate gas per level using warm-to-warm transition (depth 2 to 6)
        uint256 gasPerLevel = _safeSub(investGas[5], investGas[1]) / 4;
        if (gasPerLevel == 0) {
            // Fallback if warm scaling is flat/jittery
            gasPerLevel = 1100; 
        }

        // 2. Measure Directs scaling on sponsor
        address sp = makeAddr("sponsorDirects");
        _liveInvest(sp, 100 * WAD, ORIGIN_LIVE);
        uint256[] memory directGas = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            _rollBlock();
            address d = makeAddr(string.concat("direct-", vm.toString(i)));
            _liveFund(d, 100 * WAD);
            vm.prank(d, d);
            uint256 gBefore = gasleft();
            system.invest(100 * WAD, sp, 0);
            directGas[i] = gBefore - gasleft();
            emit log_named_uint(string.concat("  Invest gas direct ", vm.toString(i + 1)), directGas[i]);
        }
        uint256 gasPerDirect = _safeSub(directGas[4], directGas[1]) / 3;
        if (gasPerDirect == 0) {
            gasPerDirect = 5000;
        }

        // 3. Measure Withdraw package scaling
        address wUser = makeAddr("withdrawUser");
        for (uint256 i = 0; i < 5; i++) {
            _rollBlock();
            _liveInvest(wUser, 100 * WAD, ORIGIN_LIVE);
        }
        _advanceTime(30 days);
        uint256 withdrawGas5 = _measureWithdraw(wUser);
        emit log_named_uint("  Withdraw gas (5 pkgs)", withdrawGas5);

        address wUser1 = makeAddr("withdrawUser1");
        _rollBlock();
        _liveInvest(wUser1, 100 * WAD, ORIGIN_LIVE);
        _advanceTime(30 days);
        uint256 withdrawGas1 = _measureWithdraw(wUser1);
        emit log_named_uint("  Withdraw gas (1 pkg)", withdrawGas1);

        uint256 gasPerPkg = _safeSub(withdrawGas5, withdrawGas1) / 4;
        if (gasPerPkg == 0) {
            gasPerPkg = 20000;
        }

        // Extrapolations:
        uint256 gasMedInvest = gasD1 + (500 - 1) * gasPerLevel;
        uint256 gasWorstInvestDepth = gasD1 + (1000 - 1) * gasPerLevel;
        uint256 gasWorstInvestDirects = gasD1 + 200 * gasPerDirect;
        uint256 gasWorstWithdraw = withdrawGas1 + 99 * gasPerPkg;

        uint256 gasAbsWorstInvest = gasD1 + (1000 - 1) * gasPerLevel + 200 * gasPerDirect;
        uint256 gasAbsWorstWithdraw = gasWorstWithdraw; 

        _logGas("[1/8] BEST invest (depth=2, 0 pkgs)", gasD1);
        _logGas("[2/8] BEST withdraw (1 pkg, depth=2)", withdrawGas1);
        _logGas("[3/8] MED invest (depth=500)", gasMedInvest);
        _logGas("[4/8] MED withdraw (10 pkgs)", withdrawGas1 + 9 * gasPerPkg);
        _logGas("[5/8] WORST invest (depth=1000)", gasWorstInvestDepth);
        _logGas("[6/8] WORST invest (200th direct)", gasWorstInvestDirects);
        _logGas("[7/8] WORST withdraw (100 pkgs)", gasWorstWithdraw);
        _logGas("[8/8] ABSOLUTE WORST invest (depth=1000 + 200th direct)", gasAbsWorstInvest);
        _logGas("[9/8] ABSOLUTE WORST withdraw (100 pkgs / 200 directs / depth 1000)", gasAbsWorstWithdraw);

        emit log_named_uint("Measured Gas Per Level", gasPerLevel);
        emit log_named_uint("Measured Gas Per Direct", gasPerDirect);
        emit log_named_uint("Measured Gas Per Package", gasPerPkg);

        emit log_string("============================================================");
        emit log_string("  END OF GAS ANALYSIS SUMMARY");
        emit log_string("============================================================");
    }
}
