# Infinity Six Token Contract – Comprehensive Analysis and Documentation

This document provides a line-by-line and section-by-section breakdown of the `InfinitySixToken` (`i6token.sol`) smart contract. It explains all variables, modifiers, functions, validation checks, and security mechanisms.

---

## 1. File Headers and Inheritance

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
```

- **SPDX-License-Identifier**: Declares the MIT License.
- **pragma solidity ^0.8.34**: Specifies the compiler version.
- **Imports**:
  - `ERC20.sol`: Core ERC20 standard implementation from OpenZeppelin.
  - `ERC20Burnable.sol`: Adds token burning capabilities.
  - `Ownable.sol`: Standard contract owner permissions. Note: in the deployed BSC mainnet instance, ownership is renounced.

---

## 2. Custom Error Declarations

```solidity
error Err_BuyingRestricted();
error Err_SameBlockTransferNotAllowed();
error Err_NoContractCallsAllowed();
error Err_UnlockTooEarly();
error Err_NotSystemContract();
error Err_NotDAO();
error Err_ZeroAddress();
error Err_CooldownActive();
```

Gas-efficient custom errors replace standard revert strings:
- `Err_BuyingRestricted()`: Triggered when trying to buy from the liquidity pair before buying is enabled.
- `Err_SameBlockTransferNotAllowed()`: Thrown when an account attempts multiple transfers in a single block.
- `Err_NoContractCallsAllowed()`: Reverts transactions originating from other smart contracts (non-EOA calls).
- `Err_UnlockTooEarly()`: Thrown if buying is enabled before the 180-day time lock.
- `Err_NotSystemContract()`: Thrown when a non-system contract address invokes the `mint` function.
- `Err_NotDAO()`: Thrown when a non-DAO address invokes functions restricted to the DAO Multisig controller.
- `Err_ZeroAddress()`: Reverts if `address(0)` is provided as a configuration address.
- `Err_CooldownActive()`: Thrown when an account attempts to receive tokens more than once in the same block.

---

## 3. Contract Declaration and State Variables

```solidity
contract InfinitySixToken is ERC20, ERC20Burnable, Ownable {

    address public systemContract;
    address public DAOMultisigController;

    address public liquidityPair;

    bool    public buyingEnabled;
    uint256 public immutable deployTime;
    uint256 public constant BUY_UNLOCK_DELAY = 180 days;

    mapping(address => uint256) public lastTxBlock;
    mapping(address => uint256) public lastReceiveBlock; 

    mapping(address => bool) public isWhitelisted;
```

- `systemContract`: Address of the platform contract (`InfinitySixSystem`) authorized to mint tokens.
- `DAOMultisigController`: DAO multisig wallet address handling administration.
- `liquidityPair`: UniswapV2/PancakeSwap pair address.
- `buyingEnabled`: Flag indicating if public buying is active.
- `deployTime`: Constructor-registered timestamp of contract deployment.
- `BUY_UNLOCK_DELAY`: Constant time-lock parameter of 180 days (15,552,000 seconds).
- `lastTxBlock`: Records the block number of each sender's last transaction.
- `lastReceiveBlock`: Records the block number of each receiver's last transaction.
- `isWhitelisted`: Mapping mapping whitelisted accounts to boolean values to bypass all restrictions.

---

## 4. Event Declarations

```solidity
    event BuyingEnabled(uint256 timestamp);
    event SystemContractSet(address indexed system);
    event LiquidityPairSet(address indexed pair);
    event WhitelistUpdated(address indexed account, bool status);
    event DAOControllerUpdated(address indexed newController);
```

- `BuyingEnabled`: Triggered when public buying is enabled.
- `SystemContractSet`: Triggered when the system contract address changes.
- `LiquidityPairSet`: Triggered when the liquidity pair is configured.
- `WhitelistUpdated`: Triggered when a whitelist status changes.
- `DAOControllerUpdated`: Triggered when the DAO multisig controller migrates to a new address.

---

## 5. Modifiers

```solidity
    modifier onlySystem() {
        if (msg.sender != systemContract) revert Err_NotSystemContract();
        _;
    }

    modifier onlyDAO() {
        if (msg.sender != DAOMultisigController) revert Err_NotDAO();
        _;
    }
```

- `onlySystem()`: RESTRICTS function access exclusively to the system contract.
- `onlyDAO()`: RESTRICTS function access exclusively to the DAO Multisig Controller.

---

## 6. Constructor

```solidity
    constructor(
        address _dao,
        uint256 _initialLiquiditySupply
    ) ERC20("Infinity Six", "i6") Ownable(msg.sender) {
        if (_dao == address(0)) revert Err_ZeroAddress();

        DAOMultisigController = _dao;
        deployTime = block.timestamp;

        if (_initialLiquiditySupply > 0) {
            _mint(msg.sender, _initialLiquiditySupply);
        }

        isWhitelisted[msg.sender] = true;
        isWhitelisted[_dao] = true;
        isWhitelisted[address(this)] = true;
        isWhitelisted[address(0xdead)] = true;
    }
```

- Instantiates the ERC20 token name `"Infinity Six"` and symbol `"i6"`.
- Establishes owner permissions.
- Ensures `_dao` is valid, setting `DAOMultisigController`.
- Records deployment timestamp.
- Mints the initial supply of tokens to the deployer.
- Whitelists critical addresses: deployer, DAO, token contract itself, and the burn address (`0xdead`).

---

## 7. Overridden Internal Hook: `_update`

The `_update` function is overridden to enforce security checks on every token transfer.

```solidity
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            
            if (!isWhitelisted[from]) {
                if (lastTxBlock[from] == block.number) revert Err_SameBlockTransferNotAllowed();
            }

            if (!isWhitelisted[to]) {
                if (lastReceiveBlock[to] == block.number) revert Err_CooldownActive();
            }

            if (!isWhitelisted[from] && !isWhitelisted[to]) {
                if (tx.origin != msg.sender) revert Err_NoContractCallsAllowed();
            }

            if (from == liquidityPair && liquidityPair != address(0)) {
                if (!buyingEnabled && to != systemContract) {
                    revert Err_BuyingRestricted();
                }
            }

            if (!isWhitelisted[from]) {
                lastTxBlock[from] = block.number;
            }
            if (!isWhitelisted[to]) {
                lastReceiveBlock[to] = block.number;
            }
        }
        
        super._update(from, to, amount);
    }
```

### Flow and Logic Checkpoints:
1. **Minting and Burning**: Bypassed if either `from` or `to` is `address(0)`.
2. **Same-Block Send Prevention**: Reverts with `Err_SameBlockTransferNotAllowed` if a non-whitelisted sender makes multiple transfers in the same block.
3. **Same-Block Receive Prevention**: Reverts with `Err_CooldownActive` if a non-whitelisted recipient receives tokens multiple times in the same block.
4. **Contract Interaction Blocking**: Ensures EOA origin (`tx.origin == msg.sender`) if neither sender nor recipient is whitelisted. Reverts with `Err_NoContractCallsAllowed` otherwise.
5. **Liquidity Buy Restrictions**: Reverts with `Err_BuyingRestricted` if there's a purchase from the liquidity pair before `buyingEnabled` is true, unless the receiver is the system contract.
6. **Block Index Recording**: Non-whitelisted senders and receivers have their transaction block tracking maps updated before calling parent implementation.

---

## 8. Administrative and DAO Functions

- **`mint(address to, uint256 amount)`**: Allows `systemContract` to mint reward tokens.
- **`enableBuying()`**: Enforces a 180-day lock from `deployTime` and sets `buyingEnabled = true`.
- **`disableBuying()`**: Sets `buyingEnabled = false`.
- **`setSystemContract(address _system)`**: Configures the system contract address and whitelists it.
- **`setLiquidityPair(address _pair)`**: Configures the liquidity pair address and whitelists it.
- **`setWhitelist(address _account, bool _status)`**: Sets whitelist access for the target address.
- **`updateDAOMultisigController(address _newController)`**: Transfers admin controls to the new DAO address.
- **`rescueTokens(address _token, address _to, uint256 _amount)`**: Rescues standard ERC20 tokens. Restricts rescuing the `i6` token itself.

---

## 9. Helper / View Functions

- **`timeUntilBuyUnlock()`**: Returns the remaining seconds until the `BUY_UNLOCK_DELAY` lock expires.

---

## 10. Clear Working Explanation in English

The `InfinitySixToken` contract defines a standard ERC20 token named "Infinity Six" with the symbol "i6". It operates under a strict security infrastructure managed by a DAO Multisig controller, with a dedicated system contract handle allowed to mint new tokens.

### Initialization and Deployment
When deployed, the contract establishes a DAO Multisig controller and mints an initial supply to the deployer. It sets an immutable deployment time used to calculate the 180-day purchase lock. The deployer, the DAO address, the contract itself, and the burn address (`0xdead`) are whitelisted to bypass all transfer restrictions.

### Same-Block and Cooldown Protection
Every standard transfer triggers verification checks inside the internal `_update` hook. Non-whitelisted accounts are restricted to one send operation and one receive operation per block. If an address attempts to execute a second transaction or receive tokens twice in the same block, the contract reverts.

### Smart Contract and Bot Protections
To prevent automated interactions (like high-frequency trading bots, flash loans, and sandwich attacks), the contract checks if either the sender or the receiver is whitelisted. If neither is whitelisted, the transaction must originate from an externally owned account (EOA). If the transaction is executed from a smart contract, it is rejected.

### DEX Buy Time-Lock
Public trading is restricted when the contract is launched. Anyone trying to purchase the token from the PancakeSwap/Uniswap liquidity pair will trigger a revert. The DAO can enable public buying only after the 180-day lock period has expired. The main system contract is exempt from this rule to allow auto-liquidity swaps during deposits.

### System Integration and Rewards
The system contract has permission to call the `mint` function to generate new tokens as users request withdrawals. Additionally, the DAO can adjust the system contract address, register the liquidity pair, whitelist accounts, or rescue accidentally sent tokens (except the `i6` token itself).

---

## 11. Mutable Parameters and Administrative Variables

The following state variables and settings are mutable and can be modified by authorized addresses:

- **systemContract** (adjustable via `setSystemContract` by the DAO Controller): Defines which contract has permission to mint new `i6` tokens.
- **DAOMultisigController** (adjustable via `updateDAOMultisigController` by the DAO Controller): Defines the admin multisig address that manages the token contract configuration.
- **liquidityPair** (adjustable via `setLiquidityPair` by the DAO Controller): Defines the UniswapV2/PancakeSwap pair address for the token.
- **buyingEnabled** (adjustable via `enableBuying` and `disableBuying` by the DAO Controller): Enables or disables public purchasing of the token from the liquidity pair (subject to a 180-day lock from deployment to enable).
- **isWhitelisted** (adjustable via `setWhitelist` by the DAO Controller): Configures which accounts are exempted from anti-bot and same-block protections.

