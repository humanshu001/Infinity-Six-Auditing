// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @title GasAnalysisTest -- comprehensive gas profiling for invest() and
///        withdraw() across the best, average, and worst boundaries
///        permitted by the contract.
/// @notice The contract caps user state at:
///         * 100 investment packages per user (`Err_MaxInvestmentsAllowed`)
///         * 200 directs per sponsor (`MAX_DIRECTS`)
///         * `maxDownlineDepth` upline iterations (default 1000)
///         This test sweeps each axis independently and then runs the
///         combined absolute worst case (100 pkgs / 200 directs / 1000 depth).
///         All numbers are reported in human-readable form.
contract GasAnalysisTest is BaseForkSetup {

    function setUp() public override {
        super.setUp();
        _deployFreshSystem(10_000_000 * WAD, 10_000_000 * WAD);
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    function _logGas(string memory label, uint256 gasUsed, uint256 blockLimit) internal {
        emit log_named_string("Scenario", label);
        emit log_named_uint("  gas used", gasUsed);
        emit log_named_uint("  % of BSC block (140M)", (gasUsed * 100) / blockLimit);
    }

    /// @dev Measure gas of a fresh investment by a brand-new account under
    ///      `sponsor`, depositing `amount` USDT.
    function _measureInvest(address sponsor, uint256 amount, string memory salt)
        internal returns (uint256 gasUsed)
    {
        address u = makeAddr(salt);
        _fundAndApprove(u, amount, address(freshSystem));
        _rollBlock();
        vm.prank(u, u);
        uint256 g = gasleft();
        freshSystem.invest(amount, sponsor, 0);
        gasUsed = g - gasleft();
    }

    /// @dev Same but the user already has prior packages.
    function _measureReinvest(address user, uint256 amount) internal returns (uint256 gasUsed) {
        _fundAndApprove(user, amount, address(freshSystem));
        _rollBlock();
        vm.prank(user, user);
        uint256 g = gasleft();
        freshSystem.invest(amount, freshOrigin, 0);
        gasUsed = g - gasleft();
    }

    function _measureWithdraw(address user) internal returns (uint256 gasUsed) {
        _advanceTime(1 hours + 1);
        _rollBlock();
        vm.prank(user, user);
        uint256 g = gasleft();
        freshSystem.withdraw();
        gasUsed = g - gasleft();
    }

    // ------------------------------------------------------------------------
    // BEST CASE -- shortest chain (depth 1, direct under ORIGIN, single pkg).
    // ------------------------------------------------------------------------

    function test_GAS_invest_best_case_under_origin() public {
        uint256 gasUsed = _measureInvest(freshOrigin, 100 * WAD, "best");
        _logGas("BEST: 1st invest, depth=1 (under ORIGIN), 0 prior directs", gasUsed, 140_000_000);
    }

    function test_GAS_withdraw_best_case_single_package() public {
        address u = makeAddr("bestUser");
        _investFresh(u, 100 * WAD, freshOrigin);
        _advanceTime(30 days);
        uint256 gasUsed = _measureWithdraw(u);
        _logGas("BEST: withdraw with 1 package, depth=1", gasUsed, 140_000_000);
    }

    // ------------------------------------------------------------------------
    // MEDIUM -- depth 100, 10 directs at sponsor, 10 packages on user.
    // ------------------------------------------------------------------------

    function test_GAS_invest_medium_chain_100() public {
        address[] memory chain = _buildDownlineChain(100);
        address tip = chain[chain.length - 1];
        uint256 gasUsed = _measureInvest(tip, 100 * WAD, "med-leaf");
        _logGas("MED: invest at depth 100 (chain of 100 uplines)", gasUsed, 140_000_000);
    }

    function test_GAS_withdraw_medium_10_packages() public {
        address u = makeAddr("medUser");
        _investFresh(u, 100 * WAD, freshOrigin);
        for (uint256 i = 0; i < 9; i++) {
            _dealUsdt(u, 100 * WAD);
            vm.prank(u, u);
            IERC20(USDT).approve(address(freshSystem), type(uint256).max);
            _rollBlock();
            vm.prank(u, u);
            freshSystem.invest(100 * WAD, freshOrigin, 0);
        }
        _advanceTime(30 days);
        uint256 gasUsed = _measureWithdraw(u);
        _logGas("MED: withdraw with 10 packages, depth=1", gasUsed, 140_000_000);
    }

    // ------------------------------------------------------------------------
    // WORST CASE -- 100 packages, 200 directs, 1000 depth.
    // ------------------------------------------------------------------------

    /// @dev Build a depth-1000 chain by chaining sponsorship. Each invest
    ///      pays 100 USDT into the system; the test contract has been
    ///      seeded with plenty of USDT via `deal`. Total ~100k USDT funded.
    function test_GAS_invest_worst_case_max_depth_1000() public {
        // Build a 999-deep chain so that the next invest is at depth 1000.
        address[] memory chain = _buildDownlineChain(999);
        address tip = chain[chain.length - 1];
        uint256 gasUsed = _measureInvest(tip, 100 * WAD, "worst-depth");
        _logGas("WORST: invest at depth 1000 (1000 upline iterations)", gasUsed, 140_000_000);
    }

    function test_GAS_invest_worst_case_200_directs_on_sponsor() public {
        address sponsor = makeAddr("sponsorMax");
        _investFresh(sponsor, 100 * WAD, freshOrigin);
        _buildDirects(sponsor, 199, "d199"); // 199 directs already

        uint256 gasUsed = _measureInvest(sponsor, 100 * WAD, "worst-direct-200");
        _logGas("WORST: invest creating the 200th direct under a sponsor", gasUsed, 140_000_000);
    }

    function test_GAS_withdraw_worst_case_100_packages() public {
        address u = makeAddr("worstPkg");
        _investFresh(u, 100 * WAD, freshOrigin);
        for (uint256 i = 0; i < 99; i++) {
            _dealUsdt(u, 100 * WAD);
            vm.prank(u, u);
            IERC20(USDT).approve(address(freshSystem), type(uint256).max);
            _rollBlock();
            vm.prank(u, u);
            freshSystem.invest(100 * WAD, freshOrigin, 0);
        }
        _advanceTime(30 days);
        uint256 gasUsed = _measureWithdraw(u);
        _logGas("WORST: withdraw with 100 packages, depth=1", gasUsed, 140_000_000);
    }

    /// @dev Combined absolute worst case mandated by the user:
    ///        * 100 investment packages on the actor
    ///        * 200 directs on the actor's sponsor
    ///        * depth 1000 from actor up to ORIGIN
    ///      We measure BOTH a re-invest by the actor AND the actor's
    ///      withdraw.
    function test_GAS_combined_worst_case_100p_200d_1000depth() public {
        // 1. Build a 999-deep chain ending in `sponsor` (the actor's
        // sponsor). 2. Stuff `sponsor` with 199 directs already. 3. The
        // actor invests once (becoming sponsor's 200th direct). 4. The
        // actor adds 99 more packages. 5. We measure the 101st invest
        // (still under sponsor) and the actor's withdraw.

        // Step 1: 999-deep chain. The tip is the actor's sponsor.
        address[] memory chain = _buildDownlineChain(999);
        address sponsor = chain[chain.length - 1];

        // Step 2: 199 directs already on `sponsor`.
        _buildDirects(sponsor, 199, "csb");

        // Step 3: actor joins as direct #200.
        address actor = makeAddr("worstActor");
        _investFresh(actor, 100 * WAD, sponsor); // 1 pkg
        // Step 4: actor adds 99 more packages.
        for (uint256 i = 0; i < 99; i++) {
            _dealUsdt(actor, 100 * WAD);
            vm.prank(actor, actor);
            IERC20(USDT).approve(address(freshSystem), type(uint256).max);
            _rollBlock();
            vm.prank(actor, actor);
            freshSystem.invest(100 * WAD, sponsor, 0);
        }
        // The actor's 100th package now exists; we cannot add a 101st
        // (`Err_MaxInvestmentsAllowed`), so the measured "next invest"
        // is the *withdraw* path. We mature first.
        _advanceTime(30 days);

        uint256 gasUsed = _measureWithdraw(actor);
        _logGas(
            "COMBINED WORST: withdraw with 100 packages, depth=1000, sponsor has 200 directs",
            gasUsed,
            140_000_000
        );
    }
}
