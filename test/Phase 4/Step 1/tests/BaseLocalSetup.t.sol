// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InfinitySixSystem} from "i6systemcontract.sol";
import {InfinitySixToken} from "i6token.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}
    function mintFor(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPair {
    address public token0;
    address public token1;
    uint112 public reserve0 = 1_000_000 * 1e18;
    uint112 public reserve1 = 1_000_000 * 1e18;

    constructor(address t0, address t1) {
        token0 = t0;
        token1 = t1;
    }
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }
    function sync() external {}
}

contract MockRouter {
    address public mockFactory;
    constructor() {
        mockFactory = address(this);
    }

    function factory() external view returns (address) {
        return mockFactory;
    }

    function getPair(address, address) external view returns (address) {
        return address(this);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address,
        uint
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

contract BaseLocalSetup is Test {
    address internal constant ORIGIN_LIVE = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    uint256 internal constant WAD = 1e18;

    MockUSDT   internal mockUsdt;
    MockRouter internal mockRouter;
    MockPair   internal mockPair;
    InfinitySixToken  internal localToken;
    InfinitySixSystem internal localSystem;
    address internal localDao;

    // Standard variable names matching BaseForkSetup
    address internal USDT;
    address internal SYSTEM;
    address internal TOKEN;

    address internal attacker;
    address internal attacker2;
    address internal attacker3;
    address internal whale;
    address internal randomUser;

    uint256 internal currentBlock;
    uint256 internal currentTimestamp;

    function setUp() public virtual {
        currentBlock = block.number;
        currentTimestamp = block.timestamp;

        attacker   = makeAddr("attacker");
        attacker2  = makeAddr("attacker2");
        attacker3  = makeAddr("attacker3");
        whale      = makeAddr("whale");
        randomUser = makeAddr("randomUser");

        _deployLocal();
    }

    function _deployLocal() internal {
        localDao   = makeAddr("localDao");
        mockUsdt   = new MockUSDT();
        mockRouter = new MockRouter();

        localToken = new InfinitySixToken(localDao, 10_000_000 * WAD);
        mockPair   = new MockPair(address(mockUsdt), address(localToken));

        localSystem = new InfinitySixSystem(
            address(mockUsdt),
            address(localToken),
            address(mockRouter),
            address(mockPair)
        );
        localSystem.updateDAOMultisignController(localDao);

        vm.startPrank(localDao);
        localToken.setSystemContract(address(localSystem));
        localToken.setLiquidityPair(address(mockPair));
        vm.stopPrank();

        // Assign standard variables
        USDT = address(mockUsdt);
        SYSTEM = address(localSystem);
        TOKEN = address(localToken);

        // Bypass the 3-day withdrawal gate by warping
        currentTimestamp += 3 days + 1;
        vm.warp(currentTimestamp);
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
}
