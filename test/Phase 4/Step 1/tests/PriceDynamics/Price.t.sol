// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

/// @dev Minimal PancakeSwap/Uniswap V2 interfaces needed by the harness.
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
}

interface IV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function sync() external;
}

/// @title PriceDynamicsHarness
/// @notice Base harness for all i6 price-dynamics / death-spiral tests.
///
/// IMPORTANT: This MUST run on a BSC mainnet fork (set BSC_RPC_URL). The death
/// spiral is an EMERGENT property of the AMM bonding curve and only appears
/// when pool reserves actually move with each buy/sell. Static mocks (as used
/// in the 18_DoS suite) freeze reserves and would hide the spiral entirely.
///
/// Mechanics modelled, matching the deployed contracts:
///   invest($X):
///     - 60% of X is swapped USDT -> i6 on the pool  => price UP, pool i6 down
///     - 40% of X is added as liquidity to 0xdead    => LP locked forever
///     - surplus i6 received from the swap is BURNED  => supply down
///   withdraw():
///     - 100% of the USD reward value is MINTED as i6 at the current spot price
///     - a 5% fee is taken, remainder is sent to the user
///     - the user then SELLS that i6 into the pool    => price DOWN, supply up
abstract contract PriceDynamicsHarness is Test {
    // ----- Live BSC mainnet addresses (from i6*-values.md) -----
    address constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955; // BSC-USD, 18 decimals
    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;

    uint256 constant WAD = 1e18;

    InfinitySixToken internal token;
    InfinitySixSystem internal system;
    IV2Router internal router;
    IV2Pair internal pair;
    address internal pairAddr;

    uint256 internal currentBlock;
    uint256 internal currentTimestamp;

    // In-test solvency ledger (off-chain accounting, USD = 1e18 scale).
    uint256 internal totalUsdDepositedIn; // USDT pulled into the system on invests
    uint256 internal totalUsdRealizedOut; // USDT users actually received by selling minted i6

    // ------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------

    function _forkAndDeploy(uint256 seedUsdtReserve, uint256 seedI6Reserve) internal {
        // Fork BSC. Requires `BSC_RPC_URL` in the environment / foundry config.
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.binance.org"));
        vm.createSelectFork(rpc);
        currentBlock = block.number;
        currentTimestamp = block.timestamp;

        router = IV2Router(PANCAKE_ROUTER);

        // Deploy the token with the DAO controller and an initial liquidity supply
        // held by this test contract (the deployer) for pool seeding.
        token = new InfinitySixToken(DAO, seedI6Reserve * 2);

        // Deploy the system. The pair does not exist yet, so create it first via
        // the real Pancake factory so getSpotPrice()/swaps hit a real curve.
        IV2Factory factory = IV2Factory(router.factory());
        pairAddr = factory.getPair(USDT, address(token));
        if (pairAddr == address(0)) {
            pairAddr = factory.createPair(USDT, address(token));
        }
        pair = IV2Pair(pairAddr);

        system = new InfinitySixSystem(USDT, address(token), PANCAKE_ROUTER, pairAddr);

        // Wire the token: the system must be the only minter, and the pair must
        // be registered. Whitelisting follows from setSystemContract/setLiquidityPair.
        vm.startPrank(DAO);
        token.setSystemContract(address(system));
        token.setLiquidityPair(pairAddr);
        vm.stopPrank();

        // Seed the pool with realistic reserves so spot price maps to the live
        // value (~1.2625 USDT per i6). Caller chooses the reserves.
        _seedPool(seedUsdtReserve, seedI6Reserve);
    }

    /// @dev Adds initial liquidity to the i6/USDT pair from this test contract.
    function _seedPool(uint256 usdtAmount, uint256 i6Amount) internal {
        _dealUsdt(address(this), usdtAmount);
        // token: this contract received seedI6Reserve*2 at construction.
        IERC20(USDT).approve(PANCAKE_ROUTER, type(uint256).max);
        token.approve(PANCAKE_ROUTER, type(uint256).max);

        router.addLiquidity(
            USDT,
            address(token),
            usdtAmount,
            i6Amount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // ------------------------------------------------------------------
    // Funding helpers (BSC-USD has no public mint, so we use vm.deal-style
    // balance writes via stdstore on the live token storage).
    // ------------------------------------------------------------------

    function _dealUsdt(address to, uint256 amount) internal {
        // BSC-USD stores balances in slot 1 (mapping(address=>uint256)).
        // Use the cheat-code deal which handles ERC20 balance + totalSupply.
        deal(USDT, to, IERC20(USDT).balanceOf(to) + amount, true);
    }

    function _fundAndApprove(address user, uint256 usdtAmount) internal {
        _dealUsdt(user, usdtAmount);
        vm.startPrank(user, user);
        IERC20(USDT).approve(address(system), type(uint256).max);
        token.approve(PANCAKE_ROUTER, type(uint256).max); // so the user can sell minted i6
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Action helpers
    // ------------------------------------------------------------------

    function _rollBlock() internal {
        currentBlock++;
        vm.roll(currentBlock);
        currentTimestamp += 12;
        vm.warp(currentTimestamp);
    }

    function _advanceTime(uint256 secondsForward) internal {
        currentTimestamp += secondsForward;
        vm.warp(currentTimestamp);
    }

    /// @dev Perform an invest as `user`, tracking USD deposited in.
    function _invest(address user, uint256 usdtAmount, address sponsor) internal {
        _rollBlock();
        vm.prank(user, user);
        system.invest(usdtAmount, sponsor, 0);
        totalUsdDepositedIn += usdtAmount;
    }

    /// @dev Withdraw as `user`, then immediately sell all i6 received into the
    ///      pool so the dump pressure is realised on the curve. Returns USDT out.
    function _withdrawAndSell(address user) internal returns (uint256 usdtReceived) {
        // Honour the 1h cooldown + 3-day launch gate before calling.
        uint256 i6Before = token.balanceOf(user);
        _rollBlock();
        vm.prank(user, user);
        system.withdraw();
        uint256 i6Got = token.balanceOf(user) - i6Before;

        if (i6Got == 0) return 0;

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = USDT;

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        _rollBlock();
        vm.startPrank(user, user);
        router.swapExactTokensForTokens(i6Got, 0, path, user, block.timestamp);
        vm.stopPrank();
        usdtReceived = IERC20(USDT).balanceOf(user) - usdtBefore;
        totalUsdRealizedOut += usdtReceived;
    }

    // ------------------------------------------------------------------
    // Price / state reading
    // ------------------------------------------------------------------

    /// @return price USDT per i6, scaled to 1e18.
    function _spotPrice() internal view returns (uint256 price) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (uint256 rU, uint256 rT) = pair.token0() == USDT
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
        if (rT == 0) return 0;
        price = (rU * WAD) / rT;
    }

    function _reserves() internal view returns (uint256 usdtReserve, uint256 i6Reserve) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (usdtReserve, i6Reserve) = pair.token0() == USDT
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));
    }

    /// @dev System solvency: USDT held by the contract vs USD users could still
    ///      try to extract. Negative-ish (out > in) signals the loss regime.
    function _logState(string memory tag, uint256 round) internal {
        (uint256 rU, uint256 rI) = _reserves();
        emit log_string("----------------------------------------");
        emit log_named_string("tag", tag);
        emit log_named_uint("round", round);
        emit log_named_uint("spotPrice (USDT per i6, 1e18)", _spotPrice());
        emit log_named_uint("poolUsdtReserve", rU);
        emit log_named_uint("poolI6Reserve", rI);
        emit log_named_uint("i6 totalSupply", token.totalSupply());
        emit log_named_uint("usdDepositedIn (cumulative)", totalUsdDepositedIn);
        emit log_named_uint("usdRealizedOut (cumulative)", totalUsdRealizedOut);
    }

    /// @dev One CSV row per call, prefixed CSV| for easy grep -> plot.
    function _csvRow(uint256 round) internal {
        (uint256 rU, uint256 rI) = _reserves();
        emit log_string(
            string(
                abi.encodePacked(
                    "CSV|",
                    vm.toString(round), "|",
                    vm.toString(_spotPrice()), "|",
                    vm.toString(rU), "|",
                    vm.toString(rI), "|",
                    vm.toString(token.totalSupply()), "|",
                    vm.toString(totalUsdDepositedIn), "|",
                    vm.toString(totalUsdRealizedOut)
                )
            )
        );
    }

    function _newUser(uint256 id) internal pure returns (address) {
        return address(uint160(0xD0000000 + id));
    }
}
