// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "../../../Phase 3/SimulationSetup.t.sol";

// ── proxy contract for EIP-1167 minimal proxy test ──
contract MinimalProxy {
    address public implementation;
    constructor(address _impl) { implementation = _impl; }
    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

// ── multicall wrapper ──
contract MulticallInvestor {
    function multicallInvest(
        InfinitySixSystem sys, IERC20 usdt, uint256 amount, address referrer
    ) external {
        usdt.approve(address(sys), type(uint256).max);
        sys.invest(amount, referrer, 0);
    }
}

// ── EIP-4337-style account abstraction mock ──
contract SmartWallet {
    address public owner;
    constructor(address _owner) { owner = _owner; }
    function execute(address target, bytes calldata data) external returns (bytes memory) {
        require(msg.sender == owner, "not owner");
        (bool success, bytes memory result) = target.call(data);
        require(success, "call failed");
        return result;
    }
    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }
}

contract InvestExtrasTest is SimulationSetup {
    uint256 constant WAD = 1e18;
    uint256 constant MIN_INVEST = 100 * WAD;

    address alice;

    function setUp() public override {
        super.setUp();
        alice = makeAddr("alice");
        usdt.mint(alice, 500_000 * WAD);
        vm.prank(alice, alice);
        usdt.approve(address(sys), type(uint256).max);
    }

    // ── proxy contract invest ──
    function test_invest_proxy_contract_reverts() public {
        MinimalProxy proxy = new MinimalProxy(address(sys));
        usdt.mint(address(proxy), 10_000 * WAD);
        // calling through proxy means tx.origin != msg.sender
        vm.expectRevert();
        (bool success,) = address(proxy).call(
            abi.encodeWithSelector(
                InfinitySixSystem.invest.selector,
                MIN_INVEST, ORIGIN, 0
            )
        );
        // if it didn't revert at low level, the inner call reverted
        // either way, proxy invest should not succeed
    }

    // ── multicall invest ──
    function test_invest_multicall_reverts() public {
        MulticallInvestor mc = new MulticallInvestor();
        usdt.mint(address(mc), 10_000 * WAD);
        vm.expectRevert(Err_NoContractCallsAllowed.selector);
        mc.multicallInvest(sys, usdt, MIN_INVEST, ORIGIN);
    }

    // ── EIP-4337 wallet invest ──
    function test_invest_smart_wallet_reverts() public {
        SmartWallet wallet = new SmartWallet(alice);
        usdt.mint(address(wallet), 10_000 * WAD);

        vm.prank(address(wallet), address(wallet));
        wallet.approveToken(address(usdt), address(sys), type(uint256).max);

        // alice calls wallet.execute which calls sys.invest
        // tx.origin = alice, msg.sender = wallet contract
        // inside sys.invest: tx.origin(alice) != msg.sender(wallet) -> revert
        bytes memory investCall = abi.encodeWithSelector(
            InfinitySixSystem.invest.selector,
            MIN_INVEST, ORIGIN, 0
        );
        vm.prank(alice, alice);
        vm.expectRevert("call failed");
        wallet.execute(address(sys), investCall);
    }
}
