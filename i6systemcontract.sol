// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error Err_DAOMultiSignRequired();
error Err_SameBlockTxnNotAllowed();
error Err_NoContractCallsAllowed();
error Err_MinimumInvestmentRequired();
error Err_LiquidityPairNotSet();
error Err_MaxInvestmentsAllowed();
error Err_MaxInvestmentLimitExceed();
error Err_ValidSponsorRequired();
error Err_CannotReferYourself();
error Err_SponsorNotActive();
error Err_SponsorMaxDirectsReached();
error Err_WithdrawalNotStarted();
error Err_WithdrawalCooldownActive();
error Err_NoActiveInvestmentOrCapped();
error Err_NothingToWithdraw();
error Err_UnableToGetLivePrice();
error Err_UserIsCapped();
error Err_NoActiveDirects();
error Err_NotQualifiedForUpgrade();
error Err_LiquidityPoolEmpty();
error Err_InvalidROI();
error Err_InvalidValues();
error Err_InvalidLevelPercentage();
error Err_InvalidFreshBusiness();
error Err_InvalidDepth();
error Err_InvalidSlippage();
error Err_InvalidAddress();
error Err_InvalidAmount();
error Err_CannotDrainRewardTokens();
error Err_NotAuthorized();
error Err_NoLiquidity();

interface IMintableBurnableERC20 is IERC20 {
    function burn(uint256 amount) external;
    function mint(address to, uint256 amount) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

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

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function token0() external view returns (address);
}

contract InfinitySixSystem is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public usdt;
    IERC20 public projectToken;
    IUniswapV2Router02 public dexRouter;
    address public uniswapPair; 

    address constant ORIGIN_MEMBER_ID = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant GEN_W1 = 0xc1Eb7F0c59499846eA7d9E889DCd89263Dd21026; 
    address constant GEN_W2 = 0x2526c7a2744d7d63980f6A5cF48a670C821345Fc; 
    address constant GEN_W3 = 0x1A1cE4eb714480206586EAD87af132C4D73BA34e; 
    address constant GEN_W4 = 0x20eC5480B375deDC830587f049be3Aa5650F680E; 
    address constant GEN_W5 = 0x80EFEa7E52D95749fb5544f39E7d53f3E485759a; 
    address constant GEN_W6 = 0xA82a34158900fD2e861B4DD73C5Fb2f972C978CC; 
    address constant GEN_W7 = 0x48e16dD50d687dEe67ac441AA0e74A958677E08B; 

    uint256 private constant WAD = 10**18;
    
    uint256 public MIN_INVESTMENT = 100 * WAD; 
    
    uint256 public constant MAX_INVESTMENT = 20000 * WAD;
    uint256 public constant DIRECT_BONUS_RATE = 50; 
    uint256 public constant UPLINE_INCOME_THRESHOLD = 1500 * WAD; 
    uint256 public constant MAX_DIRECTS = 200;
    uint256 public MIN_FRESH_BUSINESS = 25; 
    uint256 public MIN_ROI_PERC = 5; 
    uint256 public MIN_BOOSTER_PERC = 5; 
    
    uint256 public maxDownlineDepth = 1000; 
    uint256 public liquiditySlippage = 5; 
    uint256 public launchTime; 
    
    uint256 public constant ACTIVE_BOOSTER_PERIOD = 7 days; 
    uint256 public constant WITHDRAWAL_COOLING_PERIOD = 60 minutes;
    
    address public DAOMultisigController;
    uint256 public constant MAX_INCOME_MULTIPLIER = 6; 

    uint256 public MAX_L1_PERC = 100;
    uint256 public MAX_L2_PERC = 50;
    uint256 public MAX_L3_PERC = 40;
    uint256 public MAX_L4_PERC = 30;

    uint256 public ROI_MAX_WITHDRAWAL = 1000;
    uint256 public DIRECT_MAX_WITHDRAWAL = 1000;
    uint256 public LEVEL_MAX_WITHDRAWAL = 3000;
    uint256 public UPLINE_INC_MAX_WITHDRAWAL = 1000;
    uint256 public SALARY_MAX_WITHDRAWAL = 4000;

    uint256[11] public rankReq = [
        0, 
        3000 * WAD, 10000 * WAD, 40000 * WAD, 120000 * WAD, 
        500000 * WAD, 2000000 * WAD, 10000000 * WAD, 
        50000000 * WAD, 200000000 * WAD, 1000000000 * WAD
    ];
    uint256[11] public rankIncome = [
        0, 
        50 * WAD, 200 * WAD, 1000 * WAD, 3000 * WAD, 
        10000 * WAD, 40000 * WAD, 200000 * WAD, 
        1000000 * WAD, 4000000 * WAD, 20000000 * WAD
    ];

    struct Investment {
        uint256 amount;
        uint256 compoundedPrincipal;
        uint256 rwpWithdrawn;
        uint256 lastUpdateTime;
        bool isActive; 
        uint256 boostperc;
    }

    struct User {
        uint256 totalDeposits;
        uint256 directBonus; 
        uint256 directCount;
        uint256 directVolume;
        uint256 currentRwpRate;
        uint256 teamVolume; 
        uint256 totalDownlineBusiness; 
        uint256[41] levelRewardBase; 
        uint256 levelRewardsRealized; 
        uint256 lastLevelUpdateTime; 
        bool isUplineEligible;
        uint256 eligibleL1Count; 
        uint256 eligibleL2Count; 
        uint256 eligibleL3Count; 
        uint256[3] lastUplineRwpSeen; 
        uint256 pendingUplineIncome;
        uint8 currentRank;
        uint256 salaryLastClaimTime;
        uint256 salaryEndTime;
        uint256 unwithdrawnSalary;
        uint256 totalWithdrawn;
        address referrer; 
        bool isCapped;
        uint256 firstInvestment;
        uint256 freshBusiness;
        uint256 directBoosterCount;
        uint256 activeon;
        uint256 directBoosterBusiness;
        bool isBoosted; 
    }

    struct PendingBonus {
        uint256 amount;
        uint256 unlockTime;
    }

    struct WithdrawCache {
        uint256 availableRwp;
        uint256 rwp;
        uint256 direct;
        uint256 level;
        uint256 upline;
        uint256 salary;
        uint256 total;
        uint256 dropVol;
        uint256 rate;
        bool capped;
    }

    mapping(address => PendingBonus[]) public pendingDirectBonuses;
    mapping(address => uint256) public pendingBonusStartIndex;

    mapping(address => User) public users;
    mapping(address => Investment[]) public userInvestments; 
    mapping(address => address[]) public userDirects; 
    mapping(address => mapping(address => uint256)) public legSnapshot; 
    
    mapping(address => mapping(address => uint256)) public burnedVolume; 
    mapping(address => mapping(address => uint256)) public maintenanceBurnedVolume;
    mapping(address => uint256) public lastBlockNumber; 
    mapping(address => uint256) public lastWithdrawTime;

    event Invested(address indexed user, uint256 amount, address indexed referrer);
    event Withdrawn(address indexed user, uint256 usdtValue, uint256 tokenAmount);
    event TwapUpdated(uint256 newPrice, uint32 timeElapsed);
    event InvestmentCapped(address indexed user, uint256 packageIndex);
    event RateBoosted(address indexed user, uint256 newRate);
    event RankClaimed(address indexed user, uint8 rank, bool isMaintenance);
    event LiquidityAdded(uint256 usdtAmount, uint256 tokenAmount);

    modifier DAOMultiSignRequired() {
        if (msg.sender != DAOMultisigController) revert Err_DAOMultiSignRequired();
        _;
    }

    constructor(address _usdt, address _projectToken, address _dexRouter, address _uniswapPair) Ownable(msg.sender) {
        usdt = IERC20(_usdt);
        projectToken = IERC20(_projectToken);
        dexRouter = IUniswapV2Router02(_dexRouter);
        uniswapPair = _uniswapPair;
        usdt.approve(address(dexRouter), type(uint256).max);
        projectToken.approve(address(dexRouter), type(uint256).max);

        launchTime = block.timestamp; 
        DAOMultisigController = msg.sender;

        uint256 genesisAmount = 50000 * WAD; 
        users[ORIGIN_MEMBER_ID].totalDeposits = genesisAmount;
        users[ORIGIN_MEMBER_ID].lastLevelUpdateTime = block.timestamp;
        
        userInvestments[ORIGIN_MEMBER_ID].push(Investment({
            amount: genesisAmount,
            compoundedPrincipal: genesisAmount,
            rwpWithdrawn: 0,
            lastUpdateTime: block.timestamp,
            isActive: true,
            boostperc: MIN_BOOSTER_PERC
        }));
        
        emit Invested(ORIGIN_MEMBER_ID, genesisAmount, address(0));
    }

    function perc_calc(uint256 value, uint256 percent) internal pure returns (uint256) {
        return (value * percent) / 100;
    }

    function cappingCalc(uint256 _amount, uint256 _capAmount) internal pure returns (uint256) {
        if(_amount > _capAmount){
            return _capAmount;
        }
        return _amount;
    }

    function invest(uint256 usdtAmount, address referrer, uint256 minTokensOut) external nonReentrant {
        if (block.number <= lastBlockNumber[msg.sender]) revert Err_SameBlockTxnNotAllowed();
        lastBlockNumber[msg.sender] = block.number;
        if (tx.origin != msg.sender) revert Err_NoContractCallsAllowed();
        if (usdtAmount < MIN_INVESTMENT) revert Err_MinimumInvestmentRequired();
        if (uniswapPair == address(0)) revert Err_LiquidityPairNotSet();
        if (userInvestments[msg.sender].length >= 100) revert Err_MaxInvestmentsAllowed();
        
        User storage user = users[msg.sender];
        if (user.totalDeposits + usdtAmount > MAX_INVESTMENT) revert Err_MaxInvestmentLimitExceed();
        
        uint256 oldActiveVolume = 0;
        bool wasCapped = user.isCapped;

        if (referrer == address(0)) revert Err_ValidSponsorRequired();
        if (referrer == msg.sender) revert Err_CannotReferYourself();
        User storage spnDB = users[referrer];
        if (spnDB.totalDeposits == 0) revert Err_SponsorNotActive();

        uint256 selfTotalInvest = user.totalDeposits + usdtAmount; 
        bool isBoosterPeriodActive = (spnDB.activeon + ACTIVE_BOOSTER_PERIOD) > block.timestamp;
        
        if (user.totalDeposits == 0) {
            user.firstInvestment = usdtAmount;
            user.activeon = block.timestamp;
            user.referrer = referrer;
            user.lastLevelUpdateTime = block.timestamp;
            
            if (spnDB.directCount >= MAX_DIRECTS) revert Err_SponsorMaxDirectsReached();
            _realizeLevelIncome(referrer);

            spnDB.directCount += 1;
            
            if(selfTotalInvest >= spnDB.totalDeposits && isBoosterPeriodActive){
                spnDB.directBoosterCount += 1;
            }

            userDirects[referrer].push(msg.sender); 
            _checkAndToggleEligibility(referrer);
            
        } else {
            if (wasCapped) {
                user.isCapped = false;
                user.lastLevelUpdateTime = block.timestamp; 
                for (uint256 i = 0; i < userInvestments[msg.sender].length; i++) {
                    if (userInvestments[msg.sender][i].isActive) {
                        userInvestments[msg.sender][i].lastUpdateTime = block.timestamp;
                        oldActiveVolume += userInvestments[msg.sender][i].amount;
                    }
                }
            } else {
                _updateCompounding(msg.sender);
            }
        }

        user.totalDeposits += usdtAmount;
        _checkAndToggleEligibility(msg.sender);

        if(selfTotalInvest >= spnDB.totalDeposits && isBoosterPeriodActive){
            spnDB.directBoosterBusiness += usdtAmount;
        }

        userInvestments[msg.sender].push(Investment({
            amount: usdtAmount,
            compoundedPrincipal: usdtAmount,
            rwpWithdrawn: 0,
            lastUpdateTime: block.timestamp,
            isActive: true,
            boostperc: 0
        }));

        usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);
        _updateDownlineBusiness(msg.sender, usdtAmount);

        if (user.referrer != address(0)) {
            _realizePendingDirectBonus(user.referrer);

            if (!spnDB.isCapped) {
                uint256 tmpDirectIncome = (usdtAmount * DIRECT_BONUS_RATE) / 1000;
                
                uint256 totalAllIncome = spnDB.directBonus + spnDB.levelRewardsRealized + spnDB.pendingUplineIncome + spnDB.unwithdrawnSalary;
                uint256 existingPending = 0;
                for (uint256 i = pendingBonusStartIndex[user.referrer]; i < pendingDirectBonuses[user.referrer].length; i++) {
                    existingPending += pendingDirectBonuses[user.referrer][i].amount;
                }
                
                uint256 lifetimeProjected = spnDB.totalWithdrawn + totalAllIncome + existingPending;
                uint256 maxTotalAllowed = spnDB.totalDeposits * MAX_INCOME_MULTIPLIER;
                
                if (user.referrer == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeProjected) {
                    uint256 remCapAmount = user.referrer == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeProjected;
                    uint256 finalDirectToPush = tmpDirectIncome > remCapAmount ? remCapAmount : tmpDirectIncome;
                    
                    if (finalDirectToPush > 0) {
                        pendingDirectBonuses[user.referrer].push(PendingBonus({
                            amount: finalDirectToPush,
                            unlockTime: block.timestamp + 12 hours 
                        }));
                    }
                }
            }

            spnDB.directVolume += usdtAmount;
            _checkAndApplyBooster(user.referrer);
        }

        uint256 userRate = user.currentRwpRate == 0 ? MIN_ROI_PERC : user.currentRwpRate;
        _updateUplineStream(msg.sender, usdtAmount, true, userRate, true);
        
        if (oldActiveVolume > 0) {
            _updateUplineStream(msg.sender, oldActiveVolume, true, userRate, false);
        }

        _swapTokenFromPancakev2(usdtAmount, minTokensOut);

        _tryAutoRank(msg.sender);
        if (user.referrer != address(0)) {
            _tryAutoRank(user.referrer);
        }

        emit Invested(msg.sender, usdtAmount, referrer);
    }

    function _realizePendingDirectBonus(address _user) internal {
        User storage u = users[_user];

        uint256 startIndex = pendingBonusStartIndex[_user];
        uint256 length = pendingDirectBonuses[_user].length;
        uint256 totalUnlocked = 0;

        for (uint256 i = startIndex; i < length; i++) {
            if (block.timestamp >= pendingDirectBonuses[_user][i].unlockTime) {
                totalUnlocked += pendingDirectBonuses[_user][i].amount;
                pendingBonusStartIndex[_user] = i + 1; 
            } else {
                break; 
            }
        }

        if (totalUnlocked > 0 && !u.isCapped) {
            uint256 lifetimeCurrent = u.totalWithdrawn + u.directBonus + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary;
            uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
            if (_user == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeCurrent) {
                uint256 remCapAmount = _user == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeCurrent;
                u.directBonus += cappingCalc(totalUnlocked, remCapAmount);
            }
        }
    }

    function getDirectBonusInfo(address _user) external view returns (uint256 availableNow, uint256 pendingLocked) {
        User storage u = users[_user];
        availableNow = u.directBonus;
        
        uint256 startIndex = pendingBonusStartIndex[_user];
        uint256 length = pendingDirectBonuses[_user].length;

        for (uint256 i = startIndex; i < length; i++) {
            if (block.timestamp >= pendingDirectBonuses[_user][i].unlockTime) {
                availableNow += pendingDirectBonuses[_user][i].amount; 
            } else {
                pendingLocked += pendingDirectBonuses[_user][i].amount;
            }
        }
        
        uint256 lifetimeCurrent = u.totalWithdrawn + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary; 
        uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
        
        if (_user != ORIGIN_MEMBER_ID) {
            if (lifetimeCurrent + availableNow > maxTotalAllowed) {
                 availableNow = maxTotalAllowed > lifetimeCurrent ? maxTotalAllowed - lifetimeCurrent : 0;
            }
            if (lifetimeCurrent + availableNow + pendingLocked > maxTotalAllowed) {
                 uint256 rem = maxTotalAllowed > (lifetimeCurrent + availableNow) ? maxTotalAllowed - (lifetimeCurrent + availableNow) : 0;
                 pendingLocked = rem;
            }
        }
        return (availableNow, pendingLocked);
    }

    function withdraw() external nonReentrant {
        if (block.timestamp <= launchTime + 3 days) revert Err_WithdrawalNotStarted(); 
        if (block.number <= lastBlockNumber[msg.sender]) revert Err_SameBlockTxnNotAllowed();
        if (tx.origin != msg.sender) revert Err_NoContractCallsAllowed();
        if (block.timestamp <= lastWithdrawTime[msg.sender] + WITHDRAWAL_COOLING_PERIOD) revert Err_WithdrawalCooldownActive();

        _realizePendingDirectBonus(msg.sender);
        _updateCompounding(msg.sender);
        
        User storage user = users[msg.sender];
        if (user.totalDeposits == 0 || user.isCapped) revert Err_NoActiveInvestmentOrCapped();

        WithdrawCache memory vars;
        vars.rate = user.currentRwpRate == 0 ? MIN_ROI_PERC : user.currentRwpRate;

        for (uint256 i = 0; i < userInvestments[msg.sender].length; i++) {
            Investment storage inv = userInvestments[msg.sender][i];
            if (inv.isActive) {
                uint256 generated = (inv.compoundedPrincipal - inv.amount) + inv.rwpWithdrawn;
                uint256 maxRwpAllowed = (inv.amount * 25) / 10;
                uint256 availableForPackage = inv.compoundedPrincipal - inv.amount;

                if (generated >= maxRwpAllowed) {
                    uint256 excess = generated - maxRwpAllowed;
                    availableForPackage -= excess;
                }
                vars.availableRwp += availableForPackage;
            }
        }

        _realizeLevelIncome(msg.sender); 
        _realizeUplineIncome(msg.sender);
        _realizeSalary(msg.sender); 

        vars.rwp = cappingCalc(vars.availableRwp, ROI_MAX_WITHDRAWAL * WAD);
        vars.direct = cappingCalc(user.directBonus, DIRECT_MAX_WITHDRAWAL * WAD);
        vars.level = cappingCalc(user.levelRewardsRealized, LEVEL_MAX_WITHDRAWAL * WAD);
        vars.upline = cappingCalc(user.pendingUplineIncome, UPLINE_INC_MAX_WITHDRAWAL * WAD);
        vars.salary = cappingCalc(user.unwithdrawnSalary, SALARY_MAX_WITHDRAWAL * WAD);
        
        vars.total = vars.rwp + vars.direct + vars.level + vars.upline + vars.salary;
        if (vars.total == 0) revert Err_NothingToWithdraw();

        if (msg.sender != ORIGIN_MEMBER_ID) {
            uint256 maxTotalAllowed = user.totalDeposits * MAX_INCOME_MULTIPLIER; 
            if (user.totalWithdrawn + vars.total >= maxTotalAllowed) {
                uint256 allowedRemaining = maxTotalAllowed - user.totalWithdrawn;
                
                if (vars.total > 0) {
                    uint256 rwpScaled = (vars.rwp * allowedRemaining) / vars.total;
                    uint256 directScaled = (vars.direct * allowedRemaining) / vars.total;
                    uint256 levelScaled = (vars.level * allowedRemaining) / vars.total;
                    uint256 uplineScaled = (vars.upline * allowedRemaining) / vars.total;
                    uint256 salaryScaled = (vars.salary * allowedRemaining) / vars.total;
                    
                    uint256 dust = allowedRemaining - (rwpScaled + directScaled + levelScaled + uplineScaled + salaryScaled);
                    
                    if (dust > 0) {
                        if (vars.rwp > 0) rwpScaled += dust;
                        else if (vars.direct > 0) directScaled += dust;
                        else if (vars.level > 0) levelScaled += dust;
                        else if (vars.upline > 0) uplineScaled += dust;
                        else if (vars.salary > 0) salaryScaled += dust;
                    }
                    
                    vars.rwp = rwpScaled;
                    vars.direct = directScaled;
                    vars.level = levelScaled;
                    vars.upline = uplineScaled;
                    vars.salary = salaryScaled;
                }
                
                vars.total = allowedRemaining;
                vars.capped = true;
            }
        }

        uint256 remainingRwpToDeduct = vars.rwp;

        for (uint256 i = 0; i < userInvestments[msg.sender].length; i++) {
            Investment storage inv = userInvestments[msg.sender][i];
            if (inv.isActive && remainingRwpToDeduct > 0) {
                uint256 generated = (inv.compoundedPrincipal - inv.amount) + inv.rwpWithdrawn;
                uint256 maxRwpAllowed = (inv.amount * 25) / 10;
                uint256 availableForPackage = inv.compoundedPrincipal - inv.amount;

                if (generated >= maxRwpAllowed) {
                    availableForPackage -= (generated - maxRwpAllowed);
                }

                uint256 toDeduct = availableForPackage > remainingRwpToDeduct ? remainingRwpToDeduct : availableForPackage;
                
                inv.rwpWithdrawn += toDeduct;
                inv.compoundedPrincipal -= toDeduct;
                remainingRwpToDeduct -= toDeduct;

                if (inv.rwpWithdrawn >= maxRwpAllowed) {
                    inv.isActive = false;
                    vars.dropVol += inv.amount;
                    emit InvestmentCapped(msg.sender, i);
                }
            }
        }

        if (vars.dropVol > 0) {
            _updateUplineStream(msg.sender, vars.dropVol, false, vars.rate, false);
        }

        user.directBonus -= vars.direct;
        user.levelRewardsRealized -= vars.level; 
        user.pendingUplineIncome -= vars.upline;
        user.unwithdrawnSalary -= vars.salary; 
        user.totalWithdrawn += vars.total;

        if (vars.capped) {
            user.isCapped = true; 
            _checkAndToggleEligibility(msg.sender); 
            
            uint256 activeVol = 0;
            for (uint256 i = 0; i < userInvestments[msg.sender].length; i++) {
                if (userInvestments[msg.sender][i].isActive) {
                    activeVol += userInvestments[msg.sender][i].amount;
                }
            }
            if (activeVol > 0) {
                _updateUplineStream(msg.sender, activeVol, false, vars.rate, false);
            }
        }

        _executeWithdrawTransfer(vars.total);
    }

    function _executeWithdrawTransfer(uint256 totalUsdtToWithdraw) internal {
        uint256 effectivePrice = getSpotPrice();
        if (effectivePrice == 0) revert Err_UnableToGetLivePrice();

        uint256 tokensToTransfer = (totalUsdtToWithdraw * WAD) / effectivePrice;
        uint256 txnfee = (tokensToTransfer * 5) / 100;
        uint256 userAmount = tokensToTransfer - txnfee;

        IMintableBurnableERC20(address(projectToken)).mint(address(this), userAmount);

        if (msg.sender == ORIGIN_MEMBER_ID) {
            uint256 amt1 = (userAmount * 250) / 1000;
            uint256 amt2 = (userAmount * 250) / 1000;
            uint256 amt3 = (userAmount * 200) / 1000;
            uint256 amt4 = (userAmount * 150) / 1000;
            uint256 amt5 = (userAmount * 115) / 1000;
            uint256 amt6 = (userAmount * 10) / 1000;
            uint256 amt7 = userAmount - (amt1 + amt2 + amt3 + amt4 + amt5 + amt6);

            projectToken.safeTransfer(GEN_W1, amt1);
            projectToken.safeTransfer(GEN_W2, amt2);
            projectToken.safeTransfer(GEN_W3, amt3);
            projectToken.safeTransfer(GEN_W4, amt4);
            projectToken.safeTransfer(GEN_W5, amt5);
            projectToken.safeTransfer(GEN_W6, amt6);
            projectToken.safeTransfer(GEN_W7, amt7);
        } else {
            projectToken.safeTransfer(msg.sender, userAmount);
        }
        
        lastBlockNumber[msg.sender] = block.number;
        lastWithdrawTime[msg.sender] = block.timestamp;
        _tryAutoRank(msg.sender);
        emit Withdrawn(msg.sender, totalUsdtToWithdraw, userAmount);
    }

    function _updateDownlineBusiness(address _user, uint256 _amount) internal {
        address currentUpline = users[_user].referrer;
        for (uint256 i = 1; i <= maxDownlineDepth; i++) {
            if (currentUpline == address(0)) break; 
            users[currentUpline].totalDownlineBusiness += _amount;
            users[currentUpline].freshBusiness += _amount;
            currentUpline = users[currentUpline].referrer;
        }
    }

    function claimRank() external nonReentrant {
        User storage user = users[msg.sender];
        if (user.isCapped) revert Err_UserIsCapped();
        if (user.directCount == 0) revert Err_NoActiveDirects();

        _realizePendingDirectBonus(msg.sender);
        _realizeSalary(msg.sender);

        uint8 newRank = user.currentRank;
        bool isMaintenance = false;
        bool rankUpgraded = false;

        for (uint8 r = 10; r > user.currentRank; r--) {
            if (_checkRankQualification(msg.sender, r)) {
                newRank = r;
                rankUpgraded = true;
                break;
            }
        }

        if (!rankUpgraded && user.currentRank > 0) {
            if (block.timestamp >= user.salaryEndTime - 7 days) { 
                if (_checkMaintenanceQualification(msg.sender, user.currentRank)) {
                    isMaintenance = true;
                }
            }
        }

        if (!rankUpgraded && !isMaintenance) revert Err_NotQualifiedForUpgrade();

        if (isMaintenance) {
            _consumeMaintenanceVolume(msg.sender, user.currentRank);
        }

        if (rankUpgraded) {
            user.currentRank = newRank;
            user.salaryLastClaimTime = block.timestamp;
            user.salaryEndTime = block.timestamp + 30 days; 
        } else if (isMaintenance) {
            user.salaryLastClaimTime = block.timestamp;
            user.salaryEndTime = user.salaryEndTime > block.timestamp ? user.salaryEndTime + 30 days : block.timestamp + 30 days;
        }

        address[] memory directs = userDirects[msg.sender];
        for(uint256 i = 0; i < directs.length; i++) {
            address d = directs[i];
            legSnapshot[msg.sender][d] = users[d].totalDeposits + users[d].totalDownlineBusiness;
        }
        if(rankUpgraded || isMaintenance){
            _resetDirectFreshBusiness(msg.sender);
        }
        emit RankClaimed(msg.sender, user.currentRank, isMaintenance);
    }

    function _tryAutoRank(address _user) internal {
        User storage u = users[_user];
        if (u.isCapped || u.directCount == 0) return;

        uint8 newRank = u.currentRank;
        bool rankUpgraded = false;
        bool isMaintenance = false;

        for (uint8 r = 10; r > u.currentRank; r--) {
            if (_checkRankQualification(_user, r)) {
                newRank = r;
                rankUpgraded = true;
                break;
            }
        }

        if (!rankUpgraded && u.currentRank > 0) {
            if (block.timestamp >= u.salaryEndTime - 7 days) {
                if (_checkMaintenanceQualification(_user, u.currentRank)) {
                    isMaintenance = true;
                }
            }
        }

        if (rankUpgraded || isMaintenance) {
            _realizeSalary(_user);

            if (isMaintenance) {
                _consumeMaintenanceVolume(_user, u.currentRank);
            }

            if (rankUpgraded) {
                u.currentRank = newRank;
                u.salaryLastClaimTime = block.timestamp;
                u.salaryEndTime = block.timestamp + 30 days;
            } else if (isMaintenance) {
                u.salaryLastClaimTime = block.timestamp;
                u.salaryEndTime = u.salaryEndTime > block.timestamp ? u.salaryEndTime + 30 days : block.timestamp + 30 days;
            }
            
            address[] memory directs = userDirects[_user];
            for(uint256 i = 0; i < directs.length; i++) {
                address d = directs[i];
                legSnapshot[_user][d] = users[d].totalDeposits + users[d].totalDownlineBusiness;
            }
            
            if(rankUpgraded || isMaintenance){
                _resetDirectFreshBusiness(_user);
            }
            
            emit RankClaimed(_user, u.currentRank, isMaintenance);
        }
    }
    
    function _checkRankQualification(address _user, uint8 _rank) internal view returns (bool) {
        uint256 target = rankReq[_rank];        
        uint256 tmpval = 0;
        uint256 power = 0;
        uint256 weaker = 0;
        uint256 total = 0;
        address[] memory directs = userDirects[_user];
        for(uint256 i = 0; i < directs.length; i++) {
            User storage directDB = users[directs[i]];
            tmpval = directDB.totalDeposits + directDB.totalDownlineBusiness;
            if(tmpval>power){
                power = tmpval;
            }
            total += tmpval;
        }
        weaker = total - power;
        return power >= perc_calc(target, 40) && weaker >= perc_calc(target, 60);
    }

    function _resetDirectFreshBusiness(address _user) internal {
        address[] memory directs = userDirects[_user];
        for(uint256 i = 0; i < directs.length; i++) {
            users[directs[i]].freshBusiness = 0;
        }
    }

    function _checkMaintenanceQualification(address _user, uint8 _rank) internal view returns (bool) {
        uint256 target = perc_calc(rankReq[_rank], MIN_FRESH_BUSINESS); 
        uint256 tmpval = 0;
        uint256 power = 0;
        uint256 weaker = 0;
        uint256 total = 0;
        address[] memory directs = userDirects[_user];
        for(uint256 i = 0; i < directs.length; i++) {
            User storage directDB = users[directs[i]];
            tmpval = directDB.freshBusiness;
            if(tmpval>power){
                power = tmpval;
            }
            total += tmpval;
        }
        weaker = total - power;
        return power >= perc_calc(target, 40) && weaker >= perc_calc(target, 60);
    }

    function _consumeMaintenanceVolume(address _user, uint8 _rank) internal {
        uint256 target = rankReq[_rank] / 5; 
        uint256 maxPerLeg = (target * 40) / 100;
        uint256 remainingToBurn = target;

        address[] memory directs = userDirects[_user];
        for(uint256 i = 0; i < directs.length; i++) {
            if (remainingToBurn == 0) break; 

            address d = directs[i];
            uint256 currentLegVol = users[d].totalDeposits + users[d].totalDownlineBusiness;
            uint256 pastLegVol = legSnapshot[_user][d];

            if (currentLegVol > pastLegVol) {
                uint256 newVol = currentLegVol - pastLegVol;
                uint256 usableFromLeg = newVol > maxPerLeg ? maxPerLeg : newVol;

                uint256 amountToTake = usableFromLeg > remainingToBurn ? remainingToBurn : usableFromLeg;

                maintenanceBurnedVolume[_user][d] += amountToTake; 
                remainingToBurn -= amountToTake;
            }
        }
    }

    function _realizeSalary(address _user) internal {
        User storage u = users[_user];
        if (u.currentRank > 0 && u.salaryLastClaimTime < u.salaryEndTime && !u.isCapped) {
            uint256 endTime = block.timestamp > u.salaryEndTime ? u.salaryEndTime : block.timestamp;
            uint256 timePassed = endTime - u.salaryLastClaimTime;
            
            if (timePassed > 0) {
                uint256 salaryPerSec = rankIncome[u.currentRank] / 30 days;
                uint256 pendingSalary = timePassed * salaryPerSec;
                
                uint256 lifetimeProjected = u.totalWithdrawn + u.directBonus + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary;
                uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
                
                if (_user == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeProjected) {
                    uint256 remCapAmount = _user == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeProjected;
                    u.unwithdrawnSalary += cappingCalc(pendingSalary, remCapAmount);
                }
                
                u.salaryLastClaimTime = endTime;
            }
        }
    }

    function getPendingSalary(address userAddress) public view returns (uint256) {
        User memory u = users[userAddress];
        if (u.currentRank == 0 || u.isCapped) return u.unwithdrawnSalary;
        
        uint256 pending = u.unwithdrawnSalary;
        if (u.salaryLastClaimTime < u.salaryEndTime) {
            uint256 endTime = block.timestamp > u.salaryEndTime ? u.salaryEndTime : block.timestamp;
            uint256 timePassed = endTime - u.salaryLastClaimTime;
            uint256 salaryPerSec = rankIncome[u.currentRank] / 30 days;
            uint256 newlyGenerated = timePassed * salaryPerSec;
            
            uint256 lifetimeProjected = u.totalWithdrawn + u.directBonus + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary;
            uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
            
            if (userAddress == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeProjected) {
                uint256 remCapAmount = userAddress == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeProjected;
                pending += newlyGenerated > remCapAmount ? remCapAmount : newlyGenerated;
            }
        }
        return pending;
    }
    
    function getLevelIncomeData(address _user) external view returns (uint256 pending, uint256 ratePerDay) {
        User storage u = users[_user];
        if (u.isCapped) return (0, 0);

        uint256 unlockedLevels = _user == ORIGIN_MEMBER_ID ? 40 : u.directCount * 2;
        if (unlockedLevels > 40) unlockedLevels = 40;

        for (uint8 lvl = 1; lvl <= unlockedLevels; lvl++) {
            if (u.levelRewardBase[lvl] > 0) {
                ratePerDay += (u.levelRewardBase[lvl] * 5) / 1000;
            }
        }

        uint256 timeElapsed = block.timestamp - u.lastLevelUpdateTime;
        pending = (ratePerDay * timeElapsed) / 1 days;
        
        return (pending, ratePerDay);
    }

    function getPendingUplineIncome(address _user) external view returns (uint256) {
        User storage u = users[_user];
        if (!u.isUplineEligible || u.isCapped) return u.pendingUplineIncome;

        uint256 pending = u.pendingUplineIncome;
        
        address up1 = u.referrer;
        if (up1 != address(0)) {
            uint256 rwp1 = getTotalLifetimeRWP(up1);
            
            if (up1 != ORIGIN_MEMBER_ID && rwp1 > u.lastUplineRwpSeen[0]) {
                uint256 div = users[up1].eligibleL1Count > 0 ? users[up1].eligibleL1Count : 1;
                pending += ((rwp1 - u.lastUplineRwpSeen[0]) * 50) / (1000 * div);
            }

            address up2 = users[up1].referrer;
            if (up2 != address(0)) {
                uint256 rwp2 = getTotalLifetimeRWP(up2);
                
                if (up2 != ORIGIN_MEMBER_ID && rwp2 > u.lastUplineRwpSeen[1]) {
                    uint256 div = users[up2].eligibleL2Count > 0 ? users[up2].eligibleL2Count : 1;
                    pending += ((rwp2 - u.lastUplineRwpSeen[1]) * 30) / (1000 * div);
                }

                address up3 = users[up2].referrer;
                if (up3 != address(0)) {
                    uint256 rwp3 = getTotalLifetimeRWP(up3);
                    
                    if (up3 != ORIGIN_MEMBER_ID && rwp3 > u.lastUplineRwpSeen[2]) {
                        uint256 div = users[up3].eligibleL3Count > 0 ? users[up3].eligibleL3Count : 1;
                        pending += ((rwp3 - u.lastUplineRwpSeen[2]) * 20) / (1000 * div);
                    }
                }
            }
        }
        return pending;
    }

    function _checkAndToggleEligibility(address _user) internal {
        User storage u = users[_user];
        bool shouldBeEligible = (u.totalDeposits >= UPLINE_INCOME_THRESHOLD && u.directCount >= 5 && !u.isCapped);
        
        if (shouldBeEligible && !u.isUplineEligible) {
            u.isUplineEligible = true;
            _realizeUplineIncome(_user); 
            _resetUplineRwpTrackers(_user);
            _adjustUplineEligibleCounts(_user, true);
        } else if (!shouldBeEligible && u.isUplineEligible) {
            u.isUplineEligible = false;
            _realizeUplineIncome(_user); 
            _adjustUplineEligibleCounts(_user, false);
        }
    }

    function _adjustUplineEligibleCounts(address _user, bool _isAdd) internal {
        address up1 = users[_user].referrer;
        if (up1 != address(0)) {
            if (_isAdd) users[up1].eligibleL1Count++; else if (users[up1].eligibleL1Count > 0) users[up1].eligibleL1Count--;
            
            address up2 = users[up1].referrer;
            if (up2 != address(0)) {
                if (_isAdd) users[up2].eligibleL2Count++; else if (users[up2].eligibleL2Count > 0) users[up2].eligibleL2Count--;
                
                address up3 = users[up2].referrer;
                if (up3 != address(0)) {
                    if (_isAdd) users[up3].eligibleL3Count++; else if (users[up3].eligibleL3Count > 0) users[up3].eligibleL3Count--;
                }
            }
        }
    }

    function getTotalLifetimeRWP(address _user) public view returns (uint256) {
        uint256 total = 0;
        Investment[] memory packages = userInvestments[_user];
        uint256 userRate = (users[_user].currentRwpRate == 0 ? MIN_ROI_PERC : users[_user].currentRwpRate);

        for (uint256 i = 0; i < packages.length; i++) {
            uint256 simulatedPrincipal = packages[i].compoundedPrincipal;
            uint256 boostperc = packages[i].boostperc;
            uint256 multiplier = _getMultiplier(userRate + boostperc);
            if (packages[i].isActive && !users[_user].isCapped) {
                uint256 timeElapsed = block.timestamp - packages[i].lastUpdateTime;
                uint256 daysElapsed = timeElapsed / 1 days;
                uint256 secondsElapsed = timeElapsed % 1 days;

                if (daysElapsed > 0) {
                    simulatedPrincipal = (simulatedPrincipal * _rpow(multiplier, daysElapsed, WAD)) / WAD;
                }
                if (secondsElapsed > 0) {
                    simulatedPrincipal += (simulatedPrincipal * (userRate + boostperc) * secondsElapsed) / (1000 * 1 days);
                }
            }

            uint256 generated = (simulatedPrincipal - packages[i].amount) + packages[i].rwpWithdrawn;
            uint256 maxRwp = (packages[i].amount * 25) / 10;
            
            if (generated > maxRwp) {
                generated = maxRwp; 
            }
            total += generated;
        }
        return total;
    }

    function _realizeUplineIncome(address _user) internal {
        User storage u = users[_user];
        if (u.isUplineEligible) {
            uint256 newlyGenerated = 0;

            address up1 = u.referrer;
            if (up1 != address(0)) {
                uint256 rwp1 = getTotalLifetimeRWP(up1);
                
                if (up1 != ORIGIN_MEMBER_ID && rwp1 > u.lastUplineRwpSeen[0]) {
                    uint256 div = users[up1].eligibleL1Count > 0 ? users[up1].eligibleL1Count : 1;
                    newlyGenerated += ((rwp1 - u.lastUplineRwpSeen[0]) * 50) / (1000 * div);
                }
                u.lastUplineRwpSeen[0] = rwp1; 

                address up2 = users[up1].referrer;
                if (up2 != address(0)) {
                    uint256 rwp2 = getTotalLifetimeRWP(up2);
                    
                    if (up2 != ORIGIN_MEMBER_ID && rwp2 > u.lastUplineRwpSeen[1]) {
                        uint256 div = users[up2].eligibleL2Count > 0 ? users[up2].eligibleL2Count : 1;
                        newlyGenerated += ((rwp2 - u.lastUplineRwpSeen[1]) * 30) / (1000 * div);
                    }
                    u.lastUplineRwpSeen[1] = rwp2;

                    address up3 = users[up2].referrer;
                    if (up3 != address(0)) {
                        uint256 rwp3 = getTotalLifetimeRWP(up3);
                        
                        if (up3 != ORIGIN_MEMBER_ID && rwp3 > u.lastUplineRwpSeen[2]) {
                            uint256 div = users[up3].eligibleL3Count > 0 ? users[up3].eligibleL3Count : 1;
                            newlyGenerated += ((rwp3 - u.lastUplineRwpSeen[2]) * 20) / (1000 * div);
                        }
                        u.lastUplineRwpSeen[2] = rwp3;
                    }
                }
            }

            if (newlyGenerated > 0 && !u.isCapped) {
                uint256 lifetimeProjected = u.totalWithdrawn + u.directBonus + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary;
                uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
                
                if (_user == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeProjected) {
                    uint256 remCapAmount = _user == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeProjected;
                    u.pendingUplineIncome += cappingCalc(newlyGenerated, remCapAmount);
                }
            }
        }
    }

    function _resetUplineRwpTrackers(address _user) internal {
        User storage u = users[_user];
        address up1 = u.referrer;
        if (up1 != address(0)) {
            u.lastUplineRwpSeen[0] = getTotalLifetimeRWP(up1);
            address up2 = users[up1].referrer;
            if (up2 != address(0)) {
                u.lastUplineRwpSeen[1] = getTotalLifetimeRWP(up2);
                address up3 = users[up2].referrer;
                if (up3 != address(0)) {
                    u.lastUplineRwpSeen[2] = getTotalLifetimeRWP(up3);
                }
            }
        }
    }

    function _checkAndApplyBooster(address _user) internal {
        User storage u = users[_user];
        if (u.isBoosted) return;

        uint256 newRate = 0;

        if (u.directBoosterCount >= 3 && u.directBoosterBusiness >= u.totalDeposits) newRate = MIN_BOOSTER_PERC;

        if (newRate > 0) {
            u.isBoosted = true;
            if (u.totalDeposits > 0) _updateCompounding(_user); 
            emit RateBoosted(_user, u.currentRwpRate + newRate);
            if (!u.isCapped) {
                uint256 activeVol = 0;
                for (uint256 i = 0; i < userInvestments[_user].length; i++) {
                    if (userInvestments[_user][i].isActive) activeVol += userInvestments[_user][i].amount;
                    userInvestments[_user][i].boostperc = newRate;
                }
                if (activeVol > 0) {
                    _updateUplineStream(_user, activeVol, true, newRate, false);
                }
            }
        }
    }

    function _realizeLevelIncome(address _user) internal {
        User storage u = users[_user];
        if (u.isCapped) return;

        uint256 timeElapsed = block.timestamp - u.lastLevelUpdateTime;
        if (timeElapsed > 0) {
            uint256 pending = 0;
            uint256 unlockedLevels = _user == ORIGIN_MEMBER_ID ? 40 : u.directCount * 2;
            if (unlockedLevels > 40) unlockedLevels = 40;

            for (uint8 lvl = 1; lvl <= unlockedLevels; lvl++) {
                if (u.levelRewardBase[lvl] > 0) {
                    pending += (u.levelRewardBase[lvl] * 5 * timeElapsed) / (1000 * 1 days);
                }
            }
            
            if (pending > 0) {
                uint256 lifetimeProjected = u.totalWithdrawn + u.directBonus + u.levelRewardsRealized + u.pendingUplineIncome + u.unwithdrawnSalary;
                uint256 maxTotalAllowed = u.totalDeposits * MAX_INCOME_MULTIPLIER;
                
                if (_user == ORIGIN_MEMBER_ID || maxTotalAllowed > lifetimeProjected) {
                    uint256 remCapAmount = _user == ORIGIN_MEMBER_ID ? type(uint256).max : maxTotalAllowed - lifetimeProjected;
                    u.levelRewardsRealized += cappingCalc(pending, remCapAmount);
                }
            }
        }
        u.lastLevelUpdateTime = block.timestamp;
    }

    function _updateUplineStream(address _user, uint256 _amount, bool _isAdd, uint256 _rateFactor, bool _addTeamVolume) internal {
        address currentUpline = users[_user].referrer;
        
        for (uint8 i = 1; i <= 40; i++) {
            if (currentUpline == address(0)) break; 
            
            User storage upline = users[currentUpline];
            
            if (!upline.isCapped) {
                _realizeLevelIncome(currentUpline);

                uint256 percent;
                if (i == 1) percent = MAX_L1_PERC; 
                else if (i == 2) percent = MAX_L2_PERC;   
                else if (i == 3) percent = MAX_L3_PERC;   
                else percent = MAX_L4_PERC;

                uint256 baseDelta = (_amount * percent * _rateFactor) / (1000 * 5); 

                if (_isAdd) {
                    if (_addTeamVolume) {
                        upline.teamVolume += _amount;
                    }
                    upline.levelRewardBase[i] += baseDelta; 
                } else {
                    if (upline.levelRewardBase[i] >= baseDelta) upline.levelRewardBase[i] -= baseDelta;
                    else upline.levelRewardBase[i] = 0;
                }
            }
            currentUpline = upline.referrer;
        }
    }


    function getSpotPrice() public view returns (uint256 price) {
        address pairAddress = uniswapPair;
        if (pairAddress == address(0)) revert Err_LiquidityPairNotSet();

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert Err_NoLiquidity();

        address token0 = pair.token0();
        uint256 r0 = uint256(reserve0);
        uint256 r1 = uint256(reserve1);

        price = token0 == address(projectToken) ? (r1 * WAD) / r0 : (r0 * WAD) / r1;
    }

    function _getMultiplier(uint256 rate) internal pure returns (uint256) {
        if (rate == 10) return 1010000000000000000; 
        if (rate == 8)  return 1008000000000000000; 
        if (rate == 7)  return 1007000000000000000; 
        return 1005000000000000000;                 
    }

    function _rpow(uint256 x, uint256 n, uint256 scalar) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : scalar;
        for (n /= 2; n != 0; n /= 2) {
            x = (x * x) / scalar;
            if (n % 2 != 0) {
                z = (z * x) / scalar;
            }
        }
    }

    function _updateCompounding(address userAddress) internal {
        if (users[userAddress].isCapped) return; 

        Investment[] storage packages = userInvestments[userAddress];
        uint256 userRate = users[userAddress].currentRwpRate == 0 ? MIN_ROI_PERC : users[userAddress].currentRwpRate;
        
        for (uint256 i = 0; i < packages.length; i++) {
            if (packages[i].isActive) {

                uint256 multiplier = _getMultiplier(userRate + packages[i].boostperc);
                uint256 timeElapsed = block.timestamp - packages[i].lastUpdateTime;
                
                if (timeElapsed >= 1 days) {
                    uint256 newPrincipal = packages[i].compoundedPrincipal;
                    uint256 daysElapsed = timeElapsed / 1 days;
                    
                    newPrincipal = (newPrincipal * _rpow(multiplier, daysElapsed, WAD)) / WAD;

                    packages[i].compoundedPrincipal = newPrincipal;
                    packages[i].lastUpdateTime += (daysElapsed * 1 days);
                }
            }
        }
    }

    function _swapTokenFromPancakev2(uint256 totalUsdtAmount, uint256 minTokensOut) internal {
        IUniswapV2Pair pair = IUniswapV2Pair(uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        
        if (reserve0 == 0 || reserve1 == 0) revert Err_LiquidityPoolEmpty();

        uint256 initialTokenBalance = projectToken.balanceOf(address(this));

        uint256 swapAmount = (totalUsdtAmount * 60) / 100;
        uint256 liquidityUsdtAmount = totalUsdtAmount - swapAmount;

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(projectToken);

        dexRouter.swapExactTokensForTokens(
            swapAmount, 
            minTokensOut, 
            path, 
            address(this), 
            block.timestamp
        );

        (uint112 newReserve0, uint112 newReserve1, ) = pair.getReserves();

        (uint112 reserveUsdt, uint112 reserveToken) = pair.token0() == address(usdt) 
            ? (newReserve0, newReserve1) 
            : (newReserve1, newReserve0);

        uint256 exactTokensNeeded = dexRouter.quote(liquidityUsdtAmount, reserveUsdt, reserveToken);

        if (projectToken.balanceOf(address(this)) >= exactTokensNeeded) {
            
            uint256 minToleranceMultiplier = 100 - liquiditySlippage;
            uint256 amountUsdtMin = (liquidityUsdtAmount * minToleranceMultiplier) / 100;
            uint256 amountTokenMin = (exactTokensNeeded * minToleranceMultiplier) / 100;

            dexRouter.addLiquidity(
                address(usdt),
                address(projectToken),
                liquidityUsdtAmount,
                exactTokensNeeded,
                amountUsdtMin,
                amountTokenMin,
                address(0xdead), 
                block.timestamp
            );
            
            emit LiquidityAdded(liquidityUsdtAmount, exactTokensNeeded);
        }

        uint256 currentBalance = projectToken.balanceOf(address(this));
        if (currentBalance > initialTokenBalance) {
            uint256 tokensToBurn = currentBalance - initialTokenBalance;
            IMintableBurnableERC20(address(projectToken)).burn(tokensToBurn);
        }
    }

    function setROI(uint256 _value) external DAOMultiSignRequired {
        if (_value < 2 || _value > 10) revert Err_InvalidROI();
        MIN_ROI_PERC = _value;
    }

    function setWithdrawalHourlyLimit(uint256 _roi, uint256 _direct, uint256 _level, uint256 _upline_inc, uint256 _salary) external DAOMultiSignRequired {
        if (
            (_roi < 500 || _roi > 10000) ||
            (_direct < 500 || _direct > 10000) ||
            (_level < 1500 || _level > 30000) ||
            (_upline_inc < 500 || _upline_inc > 10000) ||
            (_salary < 2000 || _salary > 40000)
        ) revert Err_InvalidValues();
        
        ROI_MAX_WITHDRAWAL = _roi;
        DIRECT_MAX_WITHDRAWAL = _direct;
        LEVEL_MAX_WITHDRAWAL = _level;
        UPLINE_INC_MAX_WITHDRAWAL = _upline_inc;
        SALARY_MAX_WITHDRAWAL = _salary;
    }

    function setLevelROI(uint256 _p1, uint256 _p2, uint256 _p3, uint256 _p4) external DAOMultiSignRequired {
        if (_p1 < perc_calc(200, 60) || _p1 > 400) revert Err_InvalidLevelPercentage(); 
        if (_p2 < perc_calc(50, 60) || _p2 > 100) revert Err_InvalidLevelPercentage();
        if (_p3 < perc_calc(40, 60) || _p3 > 80) revert Err_InvalidLevelPercentage();
        if (_p4 < perc_calc(30, 60) || _p4 > 60) revert Err_InvalidLevelPercentage();
        MAX_L1_PERC = _p1; 
        MAX_L2_PERC = _p2; 
        MAX_L3_PERC = _p3; 
        MAX_L4_PERC = _p4;
    }

    function setSalaryFreshBusiness(uint256 _value) external DAOMultiSignRequired {
        if (_value < 20 || _value > 50) revert Err_InvalidFreshBusiness();
        MIN_FRESH_BUSINESS = _value;
    }

    function setMaxDownlineDepth(uint256 _newDepth) external DAOMultiSignRequired {
        if (_newDepth < 100) revert Err_InvalidDepth();
        maxDownlineDepth = _newDepth;
    }

    function setLiquiditySlippage(uint256 _slippage) external DAOMultiSignRequired {
        if (_slippage < 1 || _slippage > 25) revert Err_InvalidSlippage();
        liquiditySlippage = _slippage;
    }

    function setTradingPair(address _newPair) external DAOMultiSignRequired {
        if (_newPair == address(0)) revert Err_InvalidAddress();
        uniswapPair = _newPair;
    }

    function setDexRouter(address _newRouter) external DAOMultiSignRequired {
        if (_newRouter == address(0)) revert Err_InvalidAddress();
        
        if (address(dexRouter) != address(0)) {
            usdt.approve(address(dexRouter), 0);
            projectToken.approve(address(dexRouter), 0);
        }

        dexRouter = IUniswapV2Router02(_newRouter);

        usdt.approve(address(_newRouter), type(uint256).max);
        projectToken.approve(address(_newRouter), type(uint256).max);
    }

    function setMinInvestment(uint256 _amount) external DAOMultiSignRequired {
        if (_amount == 0) revert Err_InvalidAmount();
        MIN_INVESTMENT = _amount;
    }

    function updateDAOMultisignController(address _multisigController) external DAOMultiSignRequired {
        if (_multisigController == address(0)) revert Err_InvalidAddress();
        DAOMultisigController = _multisigController;
    }
    
    function rescueAccidentalTokens(address _tokenAddress, address _to, uint256 amount) external DAOMultiSignRequired {
        if (_tokenAddress == address(projectToken)) revert Err_CannotDrainRewardTokens();
        IERC20(_tokenAddress).safeTransfer(_to, amount);
    }
}