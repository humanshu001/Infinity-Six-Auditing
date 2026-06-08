// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/InfinitySix.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ── Mocks (Adjusted for Mainnet Simulation) ──
contract MockUSDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockProjectToken is ERC20, IMintableBurnableERC20 {
    address public minter;
    constructor() ERC20("Infinity Six", "i6") { minter = msg.sender; }
    function setMinter(address _m) external { minter = _m; }
    function mint(address to, uint256 amount) external override { _mint(to, amount); }
    function burn(uint256 amount) external override { _burn(msg.sender, amount); }
}

contract MockRouter is IUniswapV2Router02 {
    MockProjectToken public projectToken;
    function setProjectToken(address _pt) external { projectToken = MockProjectToken(_pt); }

    function swapExactTokensForTokens(
        uint256 amountIn, uint256, address[] calldata, address to, uint256
    ) external override returns (uint256[] memory amounts) {
        // Mock swap rate: ~1.14 USDT per i6
        uint256 amountOut = (amountIn * 100000) / 114049; 
        projectToken.mint(to, amountOut);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function addLiquidity(
        address, address, uint256 amountADesired, uint256 amountBDesired,
        uint256, uint256, address, uint256
    ) external pure override returns (uint256, uint256, uint256) {
        return (amountADesired, amountBDesired, 1000);
    }
    function quote(uint256 amountA, uint256, uint256) external pure override returns (uint256) {
        return (amountA * 100000) / 114049;
    }
}

contract MockPair is IUniswapV2Pair {
    address public override token0;
    address public token1addr;
    uint112 private _r0;
    uint112 private _r1;

    constructor(address _t0, address _t1) {
        token0 = _t0;
        token1addr = _t1;
    }
    function getReserves() external view override returns (uint112, uint112, uint32) {
        return (_r0, _r1, uint32(block.timestamp));
    }
    function setReserves(uint112 r0, uint112 r1) external { _r0 = r0; _r1 = r1; }
    function price0CumulativeLast() external pure override returns (uint256) { return 0; }
    function price1CumulativeLast() external pure override returns (uint256) { return 0; }
}

contract UserReader {
    function totalDeposits(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (v,,,,,,,,,,,,,,,,,,,,,,,,,,) = s.users(u);
    }
    function referrer(InfinitySixSystem s, address u) external view returns (address r) {
        (,,,,,,,,,,,,,,,,,,,r,,,,,,,) = s.users(u);
    }
    function teamVolume(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (,,,,,v,,,,,,,,,,,,,,,,,,,,,) = s.users(u);
    }
    function currentRank(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (,,,,,,,,,,,,,,v,,,,,,,,,,,,) = s.users(u);
    }
    function unwithdrawnSalary(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (,,,,,,,,,,,,,,,,,v,,,,,,,,,) = s.users(u);
    }
    function currentRwpRate(InfinitySixSystem s, address u) external view returns (uint256 v) {
        (,,,,v,,,,,,,,,,,,,,,,,,,,,,) = s.users(u);
    }
    function isCapped(InfinitySixSystem s, address u) external view returns (bool v) {
        (,,,,,,,,,,,,,,,,,,,,v,,,,,,) = s.users(u);
    }
}

abstract contract SimulationSetup is Test {
    InfinitySixSystem public sys;
    MockUSDT public usdt;
    MockProjectToken public ptk;
    MockRouter public router;
    MockPair public pair;

    // Based on the contract code, ORIGIN bypasses caps
    address constant ORIGIN = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address public DAO; // 0x4EA9802681Fb877DE5407974E63F197EE754032f on mainnet, we use local deployer
    
    address[] public simUsers;

    function setUp() public virtual {
        DAO = address(this); // DAOMultisigController will be initialized to msg.sender

        usdt = new MockUSDT();
        ptk = new MockProjectToken();
        router = new MockRouter();
        pair = new MockPair(address(usdt), address(ptk));
        router.setProjectToken(address(ptk));

        // Sync with discovered live state
        // Reserve USDT (token0): 485,277.20
        // Reserve i6 (token1): 425,497.55
        pair.setReserves(uint112(485277.20 ether), uint112(425497.55 ether));

        sys = new InfinitySixSystem(
            address(usdt), address(ptk), address(router), address(pair)
        );
        ptk.setMinter(address(sys));

        _simulateMainnetTree();
    }

    function _simulateMainnetTree() internal {
        uint256 WAD = 1e18;
        address currentSponsor = ORIGIN;
        
        // Ensure ORIGIN exists internally (normally seeded or assumed)
        // If the contract enforces ORIGIN exists, we don't need to register it.
        // Let's create 15 users to simulate tree depth and width.
        for (uint i = 1; i <= 15; i++) {
            address u = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            vm.label(u, string(abi.encodePacked("User", vm.toString(i))));
            simUsers.push(u);
            usdt.mint(u, 100_000 * WAD);
            
            vm.startPrank(u, u);
            usdt.approve(address(sys), type(uint256).max);
            
            // Randomize investment amounts between 100 and 1500 USDT
            uint256 amount = (100 + (i * 100)) * WAD;
            if (amount > 1500 * WAD) amount = 1500 * WAD;
            
            sys.invest(amount, currentSponsor, 0);
            vm.stopPrank();
            
            // Every 3 users, branch off to simulate width and depth
            if (i % 3 == 0) {
                currentSponsor = u;
            }
        }

        // Fast forward 15 days to simulate aged accounts with pending ROI and unlocked withdrawals
        vm.warp(block.timestamp + 15 days);
        vm.roll(block.number + (15 days / 3)); // ~3s blocks on BSC
    }
}
