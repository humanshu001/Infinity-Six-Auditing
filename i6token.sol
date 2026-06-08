// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error Err_BuyingRestricted();
error Err_SameBlockTransferNotAllowed();
error Err_NoContractCallsAllowed();
error Err_UnlockTooEarly();
error Err_NotSystemContract();
error Err_NotDAO();
error Err_ZeroAddress();
error Err_CooldownActive();

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

    event BuyingEnabled(uint256 timestamp);
    event SystemContractSet(address indexed system);
    event LiquidityPairSet(address indexed pair);
    event WhitelistUpdated(address indexed account, bool status);
    event DAOControllerUpdated(address indexed newController);

    modifier onlySystem() {
        if (msg.sender != systemContract) revert Err_NotSystemContract();
        _;
    }

    modifier onlyDAO() {
        if (msg.sender != DAOMultisigController) revert Err_NotDAO();
        _;
    }

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

    function mint(address to, uint256 amount) external onlySystem {
        _mint(to, amount);
    }

    function enableBuying() external onlyDAO {
        if (block.timestamp < deployTime + BUY_UNLOCK_DELAY) revert Err_UnlockTooEarly();
        buyingEnabled = true;
        emit BuyingEnabled(block.timestamp);
    }

    function disableBuying() external onlyDAO {
        buyingEnabled = false;
    }

    function setSystemContract(address _system) external onlyDAO {
        if (_system == address(0)) revert Err_ZeroAddress();
        
        if (systemContract != address(0)) {
            isWhitelisted[systemContract] = false;
        }

        systemContract = _system;
        isWhitelisted[_system] = true;
        emit SystemContractSet(_system);
    }

    function setLiquidityPair(address _pair) external onlyDAO {
        if (_pair == address(0)) revert Err_ZeroAddress();
        liquidityPair = _pair;
        isWhitelisted[_pair] = true;
        emit LiquidityPairSet(_pair);
    }

    function setWhitelist(address _account, bool _status) external onlyDAO {
        if (_account == address(0)) revert Err_ZeroAddress();
        isWhitelisted[_account] = _status;
        emit WhitelistUpdated(_account, _status);
    }

    function updateDAOMultisigController(address _newController) external onlyDAO {
        if (_newController == address(0)) revert Err_ZeroAddress();
        DAOMultisigController = _newController;
        emit DAOControllerUpdated(_newController);
    }

    function rescueTokens(address _token, address _to, uint256 _amount) external onlyDAO {
        if (_token == address(this)) revert Err_ZeroAddress();
        IERC20(_token).transfer(_to, _amount);
    }

    function timeUntilBuyUnlock() external view returns (uint256) {
        uint256 unlockTime = deployTime + BUY_UNLOCK_DELAY;
        if (block.timestamp >= unlockTime) return 0;
        return unlockTime - block.timestamp;
    }
}

// Secured by advanced anti-bot protections, immutable time-locks, and a transparent DAO infrastructure to ensure a fair and safe ecosystem.