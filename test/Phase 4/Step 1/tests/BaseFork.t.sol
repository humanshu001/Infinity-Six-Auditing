// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IInfinitySixToken {
    function totalSupply() external view returns(uint256);
    function buyingEnabled() external view returns(bool);
    function liquidityPair() external view returns(address);
    function systemContract() external view returns(address);
    function balanceOf(address) external view returns(uint256);
    function isWhitelisted(address) external view returns(bool);

    function DAOMultisigController()
        external
        view
        returns(address);

    function setSystemContract(address)
        external;

    function setLiquidityPair(address)
        external;

    function setWhitelist(
        address,
        bool
    ) external;

    function updateDAOMultisigController(
        address
    ) external;

    function disableBuying()
        external;

    function enableBuying()
        external;

    function mint(
        address,
        uint256
    ) external;
}
interface IInfinitySixSystem {

    function launchTime()
        external
        view
        returns(uint256);

    function maxDownlineDepth()
        external
        view
        returns(uint256);

    function getSpotPrice()
        external
        view
        returns(uint256);

    function DAOMultisigController()
        external
        view
        returns(address);

    function setROI(uint256)
        external;

    function setTradingPair(address)
        external;

    function setDexRouter(address)
        external;

    function setMaxDownlineDepth(
        uint256
    ) external;
}

contract BaseForkSetup is Test {

    // =========================
    // LIVE MAINNET ADDRESSES
    // =========================

    address constant TOKEN =
        0xd2e052c7faE5DDeD7A7B2CdDd27B5d75D18A1593;

    address constant SYSTEM =
        0x51A36b17b5dbD013C632dCb411F71E935392fe5e;

    address constant DAO =
        0x4EA9802681Fb877DE5407974E63F197EE754032f;

    address constant PAIR =
        0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address constant ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address constant USDT =
        0x55d398326f99059fF775485246999027B3197955;

    // =========================
    // CONTRACT INSTANCES
    // =========================

    IInfinitySixToken token;
    IInfinitySixSystem system;

    // =========================
    // ATTACKER WALLETS
    // =========================

    address attacker;
    address attacker2;
    address attacker3;

    address whale;
    address randomUser;

    uint256 snapshotId;

    function setUp() public virtual {

        vm.createSelectFork(
            vm.envOr("BSC_RPC_URL", string("https://bsc-rpc.publicnode.com"))
        );

        token = IInfinitySixToken(TOKEN);
        system = IInfinitySixSystem(SYSTEM);

        attacker = makeAddr("attacker");
        attacker2 = makeAddr("attacker2");
        attacker3 = makeAddr("attacker3");

        whale = makeAddr("whale");
        randomUser = makeAddr("randomUser");

        vm.label(TOKEN, "InfinitySixToken");
        vm.label(SYSTEM, "InfinitySixSystem");
        vm.label(DAO, "DAO");
        vm.label(PAIR, "LiquidityPair");
        vm.label(ROUTER, "PancakeRouter");
        vm.label(USDT, "USDT");

        vm.label(attacker, "Attacker");
        vm.label(attacker2, "Attacker2");
        vm.label(attacker3, "Attacker3");

        snapshotId = vm.snapshotState();

        _verifyMainnetState();
    }

    function resetForkState() internal {
        vm.revertToState(snapshotId);
        snapshotId = vm.snapshotState();
    }

    function _verifyMainnetState() internal view {

        assertEq(
            token.buyingEnabled(),
            false,
            "Buying should be disabled"
        );

        assertEq(
            token.liquidityPair(),
            PAIR,
            "Pair mismatch"
        );

        assertEq(
            token.systemContract(),
            SYSTEM,
            "System mismatch"
        );

        assertGt(
            token.totalSupply(),
            0,
            "Supply should exist"
        );

        assertEq(
            system.maxDownlineDepth(),
            1000,
            "Depth mismatch"
        );

        assertGt(
            system.launchTime(),
            0,
            "Launch time invalid"
        );
    }
}