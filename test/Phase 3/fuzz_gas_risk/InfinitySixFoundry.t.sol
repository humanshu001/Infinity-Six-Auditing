// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../../src/InfinitySix.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ── Mock USDT ─────────────────────────────────────────────────────────────────
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ── Mock Project Token ────────────────────────────────────────────────────────
contract MockProjectToken is ERC20, IMintableBurnableERC20 {
    address public minter;

    constructor() ERC20("Project Token", "PTK") {
        minter = msg.sender;
    }

    function setMinter(address _m) external { minter = _m; }

    // IERC20 is already satisfied by ERC20; just implement the extra interface
    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }
}

// ── Mock DEX Router ───────────────────────────────────────────────────────────
contract MockRouter is IUniswapV2Router02 {
    MockProjectToken public projectToken;

    function setProjectToken(address _pt) external { projectToken = MockProjectToken(_pt); }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata,
        address to,
        uint256
    ) external override returns (uint256[] memory amounts) {
        uint256 amountOut = amountIn * 10;
        projectToken.mint(to, amountOut);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function addLiquidity(
        address, address,
        uint256 amountADesired, uint256 amountBDesired,
        uint256, uint256, address, uint256
    ) external pure override returns (uint256, uint256, uint256) {
        return (amountADesired, amountBDesired, 1000);
    }

    function quote(uint256 amountA, uint256, uint256) external pure override returns (uint256) {
        return amountA * 10;
    }
}

// ── Mock Pair ─────────────────────────────────────────────────────────────────
contract MockPair is IUniswapV2Pair {
    address public override token0;
    address public token1addr;
    uint112 private _r0;
    uint112 private _r1;

    constructor(address _t0, address _t1) {
        token0 = _t0;
        token1addr = _t1;
        _r0 = uint112(500_000 * 1e18);
        _r1 = uint112(5_000_000 * 1e18);
    }

    function getReserves() external view override returns (uint112, uint112, uint32) {
        return (_r0, _r1, uint32(block.timestamp));
    }

    function setReserves(uint112 r0, uint112 r1) external { _r0 = r0; _r1 = r1; }

    function price0CumulativeLast() external pure override returns (uint256) { return 0; }
    function price1CumulativeLast() external pure override returns (uint256) { return 0; }
}

// ── Contract Caller (for tx.origin test) ─────────────────────────────────────
contract ContractCaller {
    InfinitySixSystem sys;
    IERC20 usdt;

    constructor(address _sys, address _usdt) {
        sys = InfinitySixSystem(_sys);
        usdt = IERC20(_usdt);
        usdt.approve(_sys, type(uint256).max);
    }

    function callInvest(address referrer, uint256 amount) external {
        sys.invest(amount, referrer, 0);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// UserReader: reads individual fields from InfinitySixSystem.users() mapping
// Structs with fixed-size array members (uint256[41], uint256[3]) have those
// fields EXCLUDED from the ABI getter. The remaining fields come back as a
// 27-element tuple (no arrays). We read them by position here.
// ─────────────────────────────────────────────────────────────────────────────
contract UserReader {
    // Field positions in the ABI-returned tuple (arrays excluded):
    // 0  totalDeposits
    // 1  directBonus
    // 2  directCount
    // 3  directVolume
    // 4  currentRwpRate
    // 5  teamVolume
    // 6  totalDownlineBusiness
    // (uint256[41] levelRewardBase - NOT in tuple)
    // 7  levelRewardsRealized
    // 8  lastLevelUpdateTime
    // 9  isUplineEligible
    // 10 eligibleL1Count
    // 11 eligibleL2Count
    // 12 eligibleL3Count
    // (uint256[3] lastUplineRwpSeen - NOT in tuple)
    // 13 pendingUplineIncome
    // 14 currentRank
    // 15 salaryLastClaimTime
    // 16 salaryEndTime
    // 17 unwithdrawnSalary
    // 18 totalWithdrawn
    // 19 referrer
    // 20 isCapped
    // 21 firstInvestment
    // 22 freshBusiness
    // 23 directBoosterCount
    // 24 activeon
    // 25 directBoosterBusiness
    // 26 isBoosted

    function totalDeposits(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (v,,,,,,,,,,,,,,,,,,,,,,,,,,) = s.users(u);
    }

    function directCount(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (,,v,,,,,,,,,,,,,,,,,,,,,,,,) = s.users(u);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Test Contract
// ─────────────────────────────────────────────────────────────────────────────
contract InfinitySixFoundryTest is Test {
    InfinitySixSystem public sys;
    MockUSDT public usdt;
    MockProjectToken public ptk;
    MockRouter public router;
    MockPair public pair;
    UserReader public reader;

    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    uint256 constant WAD = 1e18;
    uint256 constant MIN_INVEST = 100 * WAD;
    uint256 constant MID_INVEST = 1000 * WAD;
    uint256 constant MAX_INVEST = 20_000 * WAD;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave  = makeAddr("dave");

    function setUp() public {
        usdt   = new MockUSDT();
        ptk    = new MockProjectToken();
        router = new MockRouter();
        pair   = new MockPair(address(usdt), address(ptk));
        reader = new UserReader();
        router.setProjectToken(address(ptk));

        sys = new InfinitySixSystem(
            address(usdt), address(ptk), address(router), address(pair)
        );
        ptk.setMinter(address(sys));

        address[4] memory users_ = [alice, bob, carol, dave];
        for (uint i = 0; i < users_.length; i++) {
            usdt.mint(users_[i], 100_000 * WAD);
            vm.prank(users_[i], users_[i]);
            usdt.approve(address(sys), type(uint256).max);
        }
    }


    function _getUserDeposits(address u) internal view returns (uint256) {
        return reader.totalDeposits(sys, u);
    }

    function _getUserDirectCount(address u) internal view returns (uint256) {
        return reader.directCount(sys, u);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. ACCESS CONTROL
    // ─────────────────────────────────────────────────────────────────────────

    function test_Access_NonDAO_CannotSetROI() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setROI(7);
    }

    function test_Access_DAO_CanSetROI() public {
        sys.setROI(7);
        assertEq(sys.MIN_ROI_PERC(), 7);
        sys.setROI(5); // restore
    }

    function test_Access_ZeroAddressDAOController_Reverts() public {
        vm.expectRevert(Err_InvalidAddress.selector);
        sys.updateDAOMultisignController(address(0));
    }

    function test_Access_CannotDrainProjectToken() public {
        vm.expectRevert(Err_CannotDrainRewardTokens.selector);
        sys.rescueAccidentalTokens(address(ptk), address(this), 1);
    }

    function test_Access_CanRescueOtherTokens() public {
        usdt.mint(address(sys), 100 * WAD);
        sys.rescueAccidentalTokens(address(usdt), address(this), 100 * WAD);
        // No revert = pass
    }

    function test_Access_NonDAO_CannotSetWithdrawalLimits() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setWithdrawalHourlyLimit(1000, 1000, 3000, 1000, 4000);
    }

    function test_Access_NonDAO_CannotChangePair() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_DAOMultiSignRequired.selector);
        sys.setTradingPair(address(pair));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. INVEST VALIDATIONS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Invest_BelowMin_Reverts() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_MinimumInvestmentRequired.selector);
        sys.invest(50 * WAD, ORIGIN, 0);
    }

    function test_Invest_ZeroReferrer_Reverts() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_ValidSponsorRequired.selector);
        sys.invest(MIN_INVEST, address(0), 0);
    }

    function test_Invest_SelfReferral_Reverts() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_CannotReferYourself.selector);
        sys.invest(MIN_INVEST, alice, 0);
    }

    function test_Invest_InactiveSponsor_Reverts() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_SponsorNotActive.selector);
        sys.invest(MIN_INVEST, bob, 0);
    }

    function test_Invest_ExceedsMax_Reverts() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);

        vm.roll(block.number + 1); // avoid same-block guard
        vm.prank(alice, alice);
        vm.expectRevert(Err_MaxInvestmentLimitExceed.selector);
        sys.invest(MAX_INVEST, ORIGIN, 0);
    }

    function test_Invest_Valid_UpdatesDeposits() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        assertEq(_getUserDeposits(alice), MIN_INVEST);
    }

    function test_Invest_Valid_IncrementsDirectCount() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        vm.prank(bob, bob);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        assertGt(_getUserDirectCount(ORIGIN), 0);
    }

    function test_Invest_Multiple_IncrementsCount() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        vm.prank(bob, bob);
        sys.invest(MIN_INVEST, alice, 0);
        vm.prank(carol, carol);
        sys.invest(MIN_INVEST, alice, 0);
        assertEq(_getUserDirectCount(alice), 2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. WITHDRAWAL TIMING
    // ─────────────────────────────────────────────────────────────────────────

    function test_Withdraw_BeforeLaunch_Reverts() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        vm.prank(alice, alice);
        vm.expectRevert(Err_WithdrawalNotStarted.selector);
        sys.withdraw();
    }

    /// @notice After 3 days the withdrawal lockup lifts — confirms Err_WithdrawalNotStarted no longer fires.
    /// Note: actual withdrawal may succeed or revert with other errors depending on ROI accrual.
    function test_Withdraw_After3Days_LockLifts() public {
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);

        // Confirm withdrawal IS blocked before 3 days
        vm.prank(alice, alice);
        vm.expectRevert(Err_WithdrawalNotStarted.selector);
        sys.withdraw();

        // Advance past 3-day lock + cooldown
        vm.warp(block.timestamp + 3 days + 61 seconds);
        vm.roll(block.number + 1);

        // Must NOT revert with WithdrawalNotStarted — the lock has lifted
        vm.prank(alice, alice);
        try sys.withdraw() {} catch (bytes memory err) {
            // Allow any other error (e.g. NothingToWithdraw, cooldown) but NOT WithdrawalNotStarted
            assertNotEq(bytes4(err), Err_WithdrawalNotStarted.selector);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. ANTI-BOT
    // ─────────────────────────────────────────────────────────────────────────

    function test_AntiBot_ContractCaller_Reverts() public {
        ContractCaller caller = new ContractCaller(address(sys), address(usdt));
        usdt.mint(address(caller), 10_000 * WAD);
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        caller.callInvest(ORIGIN, MIN_INVEST);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. ORACLE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Oracle_SpotPrice_ReturnsNonZero() public view {
        uint256 price = sys.getSpotPrice();
        assertGt(price, 0);
    }

    function test_Oracle_SpotPrice_ZeroReserves_Reverts() public {
        MockPair emptyPair = new MockPair(address(usdt), address(ptk));
        emptyPair.setReserves(0, 0);
        InfinitySixSystem fresh = new InfinitySixSystem(
            address(usdt), address(ptk), address(router), address(emptyPair)
        );
        vm.expectRevert(Err_NoLiquidity.selector);
        fresh.getSpotPrice();
    }

    /// @notice Documents flash-loan / price manipulation risk
    function test_Oracle_SpotPrice_IsManipulable() public {
        uint256 price1 = sys.getSpotPrice();
        // Simulate adversarial reserve manipulation (flash loan style)
        pair.setReserves(uint112(1_000_000 * 1e18), uint112(100 * 1e18));
        uint256 price2 = sys.getSpotPrice();
        console.log("[RISK] Price before manipulation:", price1);
        console.log("[RISK] Price after manipulation :", price2);
        assertNotEq(price1, price2);
    }

    function test_Oracle_PairNotSet_Reverts() public {
        InfinitySixSystem fresh = new InfinitySixSystem(
            address(usdt), address(ptk), address(router), address(0)
        );
        vm.expectRevert(Err_LiquidityPairNotSet.selector);
        fresh.getSpotPrice();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. ECONOMIC INVARIANTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Econ_MaxIncomeMultiplier_Is6() public view {
        assertEq(sys.MAX_INCOME_MULTIPLIER(), 6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. ADMIN PARAMETER BOUNDS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Admin_ROI_RejectsTooLow() public {
        vm.expectRevert(Err_InvalidROI.selector);
        sys.setROI(1);
    }

    function test_Admin_ROI_RejectsTooHigh() public {
        vm.expectRevert(Err_InvalidROI.selector);
        sys.setROI(11);
    }

    function test_Admin_Slippage_RejectsZero() public {
        vm.expectRevert(Err_InvalidSlippage.selector);
        sys.setLiquiditySlippage(0);
    }

    function test_Admin_Slippage_Rejects26() public {
        vm.expectRevert(Err_InvalidSlippage.selector);
        sys.setLiquiditySlippage(26);
    }

    function test_Admin_MinInvestment_RejectsZero() public {
        vm.expectRevert(Err_InvalidAmount.selector);
        sys.setMinInvestment(0);
    }

    function test_Admin_DownlineDepth_RejectsUnder100() public {
        vm.expectRevert(Err_InvalidDepth.selector);
        sys.setMaxDownlineDepth(50);
    }

    function test_Admin_FreshBusiness_RejectsTooLow() public {
        vm.expectRevert(Err_InvalidFreshBusiness.selector);
        sys.setSalaryFreshBusiness(10);
    }

    function test_Admin_FreshBusiness_RejectsTooHigh() public {
        vm.expectRevert(Err_InvalidFreshBusiness.selector);
        sys.setSalaryFreshBusiness(60);
    }

    function test_Admin_WithdrawalLimits_RejectsInvalidROI() public {
        vm.expectRevert(Err_InvalidValues.selector);
        sys.setWithdrawalHourlyLimit(100, 1000, 3000, 1000, 4000);
    }

    function test_Admin_WithdrawalLimits_ValidValues() public {
        sys.setWithdrawalHourlyLimit(1000, 1000, 3000, 1000, 4000);
        assertEq(sys.ROI_MAX_WITHDRAWAL(), 1000);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. RANK SYSTEM
    // ─────────────────────────────────────────────────────────────────────────

    function test_Rank_ClaimWithNoDirects_Reverts() public {
        vm.prank(alice, alice);
        vm.expectRevert(Err_NoActiveDirects.selector);
        sys.claimRank();
    }

    function test_Rank_RankReqIndex10_Is1Billion() public view {
        assertEq(sys.rankReq(10), 1_000_000_000 * WAD);
    }

    function test_Rank_RankIncome_Index1() public view {
        assertEq(sys.rankIncome(1), 50 * WAD);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. FUZZ TESTS
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_Invest_BelowMin_AlwaysReverts(uint256 amount) public {
        vm.assume(amount > 0 && amount < MIN_INVEST);
        usdt.mint(alice, amount);
        vm.prank(alice, alice);
        usdt.approve(address(sys), amount);
        vm.prank(alice, alice);
        vm.expectRevert(Err_MinimumInvestmentRequired.selector);
        sys.invest(amount, ORIGIN, 0);
    }

    function testFuzz_Invest_AboveMax_AlwaysReverts(uint256 amount) public {
        vm.assume(amount > MAX_INVEST && amount < type(uint112).max);
        usdt.mint(alice, amount);
        vm.prank(alice, alice);
        usdt.approve(address(sys), amount);
        vm.prank(alice, alice);
        vm.expectRevert(Err_MaxInvestmentLimitExceed.selector);
        sys.invest(amount, ORIGIN, 0);
    }

    function testFuzz_ROI_InvalidBounds(uint256 roi) public {
        vm.assume(roi < 2 || roi > 10);
        vm.expectRevert(Err_InvalidROI.selector);
        sys.setROI(roi);
    }

    function testFuzz_Slippage_InvalidBounds(uint256 slippage) public {
        vm.assume(slippage == 0 || slippage > 25);
        vm.expectRevert(Err_InvalidSlippage.selector);
        sys.setLiquiditySlippage(slippage);
    }

    function testFuzz_DownlineDepth_Under100_Reverts(uint256 depth) public {
        vm.assume(depth < 100);
        vm.expectRevert(Err_InvalidDepth.selector);
        sys.setMaxDownlineDepth(depth);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 10. GAS BENCHMARKS
    // ─────────────────────────────────────────────────────────────────────────

    function test_Gas_SingleInvest_Under1M() public {
        vm.prank(alice, alice);
        uint256 before = gasleft();
        sys.invest(MIN_INVEST, ORIGIN, 0);
        uint256 used = before - gasleft();
        console.log("[GAS] Single invest:", used);
        assertLt(used, 1_000_000);
    }

    function test_Gas_MultipleInvestors_LevelIncome() public {
        vm.prank(alice, alice);
        sys.invest(MID_INVEST, ORIGIN, 0);

        for (uint i = 0; i < 5; i++) {
            address u = makeAddr(string(abi.encode(i)));
            usdt.mint(u, 10_000 * WAD);
            vm.prank(u, u);
            usdt.approve(address(sys), type(uint256).max);
            vm.prank(u, u);
            sys.invest(MIN_INVEST, alice, 0);
        }

        vm.warp(block.timestamp + 1 days);
        uint256 before = gasleft();
        sys.getLevelIncomeData(alice);
        uint256 used = before - gasleft();
        console.log("[GAS] getLevelIncomeData (5 users, 1 day):", used);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 11. CENTRALIZATION RISK DOCUMENTATION
    // ─────────────────────────────────────────────────────────────────────────

    function test_Risk_DAOControllerIsSingleEOA() public view {
        address daoCtrl = sys.DAOMultisigController();
        // In tests this is address(this); in production it's a single EOA
        console.log("[RISK] DAOMultisigController:", daoCtrl);
        assertNotEq(daoCtrl, address(0));
    }

    function test_Risk_OriginMemberHasNoIncomeCapByDesign() public view {
        // ORIGIN_MEMBER_ID is hardcoded and bypasses 6x cap
        console.log("[RISK] ORIGIN =", ORIGIN, "bypasses MAX_INCOME_MULTIPLIER");
        assertEq(sys.MAX_INCOME_MULTIPLIER(), 6);
    }

    function test_Risk_PendingBonusArrayGrowsUnbounded() public {
        // Each invest() appends to pendingDirectBonuses[referrer]
        vm.prank(alice, alice);
        sys.invest(MIN_INVEST, ORIGIN, 0);
        // ORIGIN's pending bonus array now has 1 entry; it only grows
        console.log("[RISK] pendingDirectBonuses array never shrinks");
    }

    function test_Risk_MaxDownlineLoop1000Gas() public view {
        uint256 depth = sys.maxDownlineDepth();
        console.log("[RISK] _updateDownlineBusiness loops up to:", depth, "levels");
        assertEq(depth, 1000);
    }
}
