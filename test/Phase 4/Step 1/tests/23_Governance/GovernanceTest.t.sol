// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000000 * 1e18);
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MaliciousRouter {
    address public owner;
    constructor(address _owner) {
        owner = _owner;
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address,
        uint
    ) external returns (uint[] memory amounts) {
        // Transfer all USDT (path[0]) to owner instead of swapping
        IERC20(path[0]).transferFrom(msg.sender, owner, amountIn);
        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
    function quote(uint, uint, uint) external pure returns (uint) {
        return 0;
    }
    function addLiquidity(
        address,
        address,
        uint,
        uint,
        uint,
        uint,
        address,
        uint
    ) external pure returns (uint, uint, uint) {
        return (0, 0, 0);
    }
}

// [ignoring loop detection]
contract GovernanceTest is Test {
    MockUSDT usdt;
    InfinitySixToken token;
    InfinitySixSystem systemContract;

    address constant DAO = 0x4EA9802681Fb877DE5407974E63F197EE754032f;
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant ROUTER = 0x10ED43c718714eB53d5AA57b78b54704E256024E;
    address constant PAIR = 0x13D55200c298Ff1caE3136BE0dd889626DEAC782;

    address sponsor = address(0x2222);
    address user = address(0x1111);

    function setUp() public {
        usdt = new MockUSDT();
        token = new InfinitySixToken(DAO, 1000000000 * 1e18);
        
        systemContract = new InfinitySixSystem(
            address(usdt),
            address(token),
            ROUTER,
            PAIR
        );

        vm.startPrank(DAO);
        token.setSystemContract(address(systemContract));
        token.setLiquidityPair(PAIR);
        vm.stopPrank();

        usdt.transfer(sponsor, 100000 * 1e18);
        usdt.transfer(user, 100000 * 1e18);
        token.transfer(address(systemContract), 1000000 * 1e18);

        // Mock Uniswap Pair and Router
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("getReserves()"),
            abi.encode(uint112(10000 * 1e18), uint112(10000 * 1e18), uint32(0))
        );
        vm.mockCall(
            PAIR,
            abi.encodeWithSignature("token0()"),
            abi.encode(address(usdt))
        );
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 60 * 1e18;
        amounts[1] = 60 * 1e18;
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            abi.encode(amounts)
        );
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("quote(uint256,uint256,uint256)"),
            abi.encode(uint256(40 * 1e18))
        );
        vm.mockCall(
            ROUTER,
            abi.encodeWithSignature("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"),
            abi.encode(uint256(40 * 1e18), uint256(40 * 1e18), uint256(40 * 1e18))
        );
    }

    function rollBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);
    }

    // Governance 1: Malicious Router Hijacking
    function test_Governance_MaliciousRouterHijack() public {
        address attacker = address(0xbad);
        MaliciousRouter malRouter = new MaliciousRouter(attacker);

        // DAO (deployer/controller is address(this)) sets malicious router
        systemContract.setDexRouter(address(malRouter));

        // Sponsor invest
        vm.startPrank(sponsor, sponsor);
        usdt.approve(address(systemContract), type(uint256).max);
        systemContract.invest(1000 * 1e18, ORIGIN, 0);
        vm.stopPrank();

        // Verify that USDT swap portion (60% = 600 USDT) was redirected to the attacker address
        uint256 attackerBalance = usdt.balanceOf(attacker);
        assertEq(attackerBalance, 600 * 1e18, "Attacker should have stolen the USDT");
    }

    // Governance 2: Compromised Controller Transfer and Privilege Escalation
    function test_Governance_PrivilegeEscalation() public {
        address newController = address(0x4444);
        
        // DAO Controller updates the multisig controller address
        systemContract.updateDAOMultisignController(newController);

        // Verify that the old controller is no longer authorized
        vm.expectRevert(bytes4(keccak256("Err_DAOMultiSignRequired()")));
        systemContract.setMinInvestment(50 * 1e18);

        // Verify that the new controller has full administrative power
        vm.prank(newController);
        systemContract.setMinInvestment(50 * 1e18);
        assertEq(systemContract.MIN_INVESTMENT(), 50 * 1e18);
    }
}
