# Infinity Six System Contract – Comprehensive Analysis and Documentation

This document provides a line-by-line and section-by-section explanation of the `InfinitySixSystem` (`i6systemcontract.sol`) smart contract. It covers the logic, mathematics, validation checks, and security protections built into the system.

---

## 1. Imports and Interfaces

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
```
Imports standard OpenZeppelin utilities:
- `IERC20`: Standard interface for ERC20 interaction.
- `SafeERC20`: Prevents silent failures on non-standard ERC20 tokens.
- `Ownable`: Standard owner contract.
- `ReentrancyGuard`: Provides the `nonReentrant` modifier to block reentrancy attacks.

### External Interfaces
- `IMintableBurnableERC20`: Expands `IERC20` to include `mint` and `burn` methods for the `i6` token.
- `IUniswapV2Router02`: Interface for PancakeSwap/UniswapV2 router, providing token swapping and liquidity addition.
- `IUniswapV2Pair`: Interface for UniswapV2/PancakeSwap liquidity pools to query reserves and fetch token addresses.

---

## 2. Constants and System Settings

```solidity
    address constant ORIGIN_MEMBER_ID = 0xdF4fA7B59e9735f273B661153A03e64A6AE61cd1;
    address constant GEN_W1 = 0xc1Eb7F0c59499846eA7d9E889DCd89263Dd21026; 
    address constant GEN_W2 = 0x2526c7a2744d7d63980f6A5cF48a670C821345Fc; 
    address constant GEN_W3 = 0x1A1cE4eb714480206586EAD87af132C4D73BA34e; 
    address constant GEN_W4 = 0x20eC5480B375deDC830587f049be3Aa5650F680E; 
    address constant GEN_W5 = 0x80EFEa7E52D95749fb5544f39E7d53f3E485759a; 
    address constant GEN_W6 = 0xA82a34158900fD2e861B4DD73C5Fb2f972C978CC; 
    address constant GEN_W7 = 0x48e16dD50d687dEe67ac441AA0e74A958677E08B;
```
- `ORIGIN_MEMBER_ID`: Special genesis account bypassing income limits (6x cap) by design.
- `GEN_W1` to `GEN_W7`: Seven distinct wallet addresses. When the origin account withdraws, rewards are split and transferred to these wallets according to hardcoded splits.

```solidity
    uint256 private constant WAD = 10**18;
    uint256 public MIN_INVESTMENT = 100 * WAD;
    uint256 public constant MAX_INVESTMENT = 20000 * WAD;
    uint256 public constant DIRECT_BONUS_RATE = 50;
    uint256 public constant UPLINE_INCOME_THRESHOLD = 1500 * WAD;
    uint256 public constant MAX_DIRECTS = 200;
    uint256 public MIN_FRESH_BUSINESS = 25;
    uint256 public MIN_ROI_PERC = 5;
    uint256 public MIN_BOOSTER_PERC = 5;
```
- `WAD`: Standard multiplier for 18 decimal point precision.
- `MIN_INVESTMENT`: Default minimum deposit size (100 USDT).
- `MAX_INVESTMENT`: Maximum active deposit size (20,000 USDT).
- `DIRECT_BONUS_RATE`: Direct referral bonus rate of 5% (`50 / 1000`).
- `UPLINE_INCOME_THRESHOLD`: Required individual deposit size (1,500 USDT) to qualify for UPLINE income.
- `MAX_DIRECTS`: Hard cap of 200 direct referrals per user.
- `MIN_FRESH_BUSINESS`: Fresh business factor (25%) needed for rank maintenance.
- `MIN_ROI_PERC`: Default base daily compounding rate (0.5% daily).
- `MIN_BOOSTER_PERC`: Default booster daily rate increase (+0.5% daily).

```solidity
    uint256 public maxDownlineDepth = 1000;
    uint256 public liquiditySlippage = 5;
    uint256 public launchTime;
    uint256 public constant ACTIVE_BOOSTER_PERIOD = 7 days;
    uint256 public constant WITHDRAWAL_COOLING_PERIOD = 60 minutes;
    address public DAOMultisigController;
    uint256 public constant MAX_INCOME_MULTIPLIER = 6;
```
- `maxDownlineDepth`: Limit of levels downline to propagate business volume.
- `liquiditySlippage`: Permitted slippage (5%) during auto-liquidity operations.
- `launchTime`: Unix timestamp indicating when the contract was deployed.
- `ACTIVE_BOOSTER_PERIOD`: Time window (7 days) for a sponsor to acquire booster qualifications after registration.
- `WITHDRAWAL_COOLING_PERIOD`: Mandated cooldown (60 minutes) between withdrawals per account.
- `DAOMultisigController`: DAO address managing system changes.
- `MAX_INCOME_MULTIPLIER`: Global earnings multiplier limit (6x of active deposits).

---

## 3. Data Structures

### `Investment`
```solidity
    struct Investment {
        uint256 amount;
        uint256 compoundedPrincipal;
        uint256 rwpWithdrawn;
        uint256 lastUpdateTime;
        bool isActive; 
        uint256 boostperc;
    }
```
Tracks details for each package deposit:
- `amount`: Original investment size in USDT.
- `compoundedPrincipal`: Active principal after daily compounding and withdrawals.
- `rwpWithdrawn`: Sum of ROI withdrawn from this specific package.
- `lastUpdateTime`: Block timestamp of last compounding.
- `isActive`: Boolean status showing if package is active (caps at 2.5x of original `amount`).
- `boostperc`: Applied booster daily rate increase (+0.5% daily).

### `User`
```solidity
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
```
Contains referral tree details, volumes, ranks, pending rewards, and capping states.

### `PendingBonus`
```solidity
    struct PendingBonus {
        uint256 amount;
        uint256 unlockTime;
    }
```
Stores referral commissions locked for 12 hours before becoming withdrawable.

### `WithdrawCache`
```solidity
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
```
Stack variable container to prevent stack-too-deep errors during withdrawals.

---

## 4. Constructor

```solidity
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
```
- Sets USDT, projectToken, dexRouter, and uniswapPair.
- Sets maximum approvals for the router to handle liquidity actions.
- Configures `DAOMultisigController` as deployer.
- Seeds the `ORIGIN_MEMBER_ID` with a genesis investment of 50,000 USDT.

---

## 5. Mathematical Helper Functions

```solidity
    function perc_calc(uint256 value, uint256 percent) internal pure returns (uint256) {
        return (value * percent) / 100;
    }

    function cappingCalc(uint256 _amount, uint256 _capAmount) internal pure returns (uint256) {
        if(_amount > _capAmount){
            return _capAmount;
        }
        return _amount;
    }
```
- `perc_calc`: Standard integer percent math.
- `cappingCalc`: Returns the minimum of the value and the maximum allowed capped limit.

---

## 6. Core Business Logic Functions

### `invest`
Allows users to invest USDT into the platform.

```solidity
    function invest(uint256 usdtAmount, address referrer, uint256 minTokensOut) external nonReentrant {
        if (block.number <= lastBlockNumber[msg.sender]) revert Err_SameBlockTxnNotAllowed();
        lastBlockNumber[msg.sender] = block.number;
        if (tx.origin != msg.sender) revert Err_NoContractCallsAllowed();
        if (usdtAmount < MIN_INVESTMENT) revert Err_MinimumInvestmentRequired();
        if (uniswapPair == address(0)) revert Err_LiquidityPairNotSet();
        if (userInvestments[msg.sender].length >= 100) revert Err_MaxInvestmentsAllowed();
```
- **Same-Block Protection**: Prevents double transactions in the same block.
- **Contract Calls Restricted**: `tx.origin != msg.sender` forces interactions through EOAs.
- **Limits Checked**: Minimum and maximum deposits validated.
- **Referrer Checks**: Rejects zero address and self-referrals. Referrer must be active.

```solidity
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
```
- Sets up transaction variables and checks if the sponsor's booster window is active.

```solidity
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
```
- If new user: initializes parameters, increases direct referrer count, and checks/toggles upline eligibility.
- If existing user: updates compounding and checks if uncapping is necessary.

```solidity
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
```
- Adds the new investment record to storage, pulls USDT from the sender, and propagates business volume down the referral tree.

```solidity
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
```
- Processes referral reward payouts, checking the sponsor's 6x income cap limits. Safe rewards are pushed to a 12-hour lockup array.

```solidity
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
```
- Adjusts upline level reward bases, executes the PancakeSwap auto-liquidity exchange, and updates system ranks.

---

### `_realizePendingDirectBonus`
```solidity
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
```
- Iteratively checks the user's locked direct bonuses starting from `pendingBonusStartIndex`. Any item past its 12-hour lock gets unlocked and credited to `directBonus` (subject to 6x capping constraints).

---

### `getDirectBonusInfo`
```solidity
    function getDirectBonusInfo(address _user) external view returns (uint256 availableNow, uint256 pendingLocked) {
```
- Returns the sum of instantly withdrawable direct bonuses and the amount currently locked behind the 12-hour vesting window.

---

### `withdraw`
Drains earned rewards and processes payouts in project tokens.

```solidity
    function withdraw() external nonReentrant {
        if (block.timestamp <= launchTime + 3 days) revert Err_WithdrawalNotStarted(); 
        if (block.number <= lastBlockNumber[msg.sender]) revert Err_SameBlockTxnNotAllowed();
        if (tx.origin != msg.sender) revert Err_NoContractCallsAllowed();
        if (block.timestamp <= lastWithdrawTime[msg.sender] + WITHDRAWAL_COOLING_PERIOD) revert Err_WithdrawalCooldownActive();

        _realizePendingDirectBonus(msg.sender);
        _updateCompounding(msg.sender);
        
        User storage user = users[msg.sender];
        if (user.totalDeposits == 0 || user.isCapped) revert Err_NoActiveInvestmentOrCapped();
```
- Validates structural block constraints: 3-day post-launch wait, same block double-call prevention, contract call rejection, and 60 minutes cooldown window.

```solidity
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
```
- Accumulates ROI yields from all active investment nodes, enforcing a **2.5x (250%)** ROI cap on each package.

```solidity
        _realizeLevelIncome(msg.sender); 
        _realizeUplineIncome(msg.sender);
        _realizeSalary(msg.sender); 

        vars.rwp = cappingCalc(vars.availableRwp, ROI_MAX_WITHDRAWAL * WAD);
        vars.direct = cappingCalc(user.directBonus, DIRECT_MAX_WITHDRAWAL * WAD);
        vars.level = cappingCalc(user.levelRewardsRealized, LEVEL_MAX_WITHDRAWAL * WAD);
        vars.upline = cappingCalc(user.pendingUplineIncome, UPLINE_INC_MAX_WITHDRAWAL * WAD);
        vars.salary = cappingCalc(user.unwithdrawnSalary, SALARY_MAX_WITHDRAWAL * WAD);
```
- Calculates level rewards, upline pool shares, and rank salaries.
- Restricts category limits (e.g. max 1,000 USDT ROI, 3,000 USDT Level income per withdrawal).

```solidity
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
```
- Enforces the global **6x (600%)** income cap. Scaling logic reduces payouts proportionally if a user reaches the limit, ensuring they cannot exceed it.

```solidity
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
```
- Deducts withdrawn ROI from the user's active packages. If a package reaches the 2.5x limit, it is deactivated, and its volume is subtracted from downline totals.

```solidity
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
```
- Deducts claimed rewards from balances. If the global 6x cap is reached, the user's active volume is removed from upline streams. Finally, the payout transfer is initiated.

---

### `_executeWithdrawTransfer`
```solidity
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
            ...
            projectToken.safeTransfer(GEN_W1, amt1);
            ...
        } else {
            projectToken.safeTransfer(msg.sender, userAmount);
        }
        
        lastBlockNumber[msg.sender] = block.number;
        lastWithdrawTime[msg.sender] = block.timestamp;
        _tryAutoRank(msg.sender);
        emit Withdrawn(msg.sender, totalUsdtToWithdraw, userAmount);
    }
```
- Fetches the current token price in USDT from the DEX reserves.
- Calculates the payout in project tokens, applies a 5% transaction fee, and mints the tokens.
- Genesis withdrawals are split among folders `GEN_W1` to `GEN_W7`.
- Standard user payouts are sent directly to their wallet.

---

### `_updateDownlineBusiness`
```solidity
    function _updateDownlineBusiness(address _user, uint256 _amount) internal {
        address currentUpline = users[_user].referrer;
        for (uint256 i = 1; i <= maxDownlineDepth; i++) {
            if (currentUpline == address(0)) break; 
            users[currentUpline].totalDownlineBusiness += _amount;
            users[currentUpline].freshBusiness += _amount;
            currentUpline = users[currentUpline].referrer;
        }
    }
```
- Traverses up the sponsor tree up to `maxDownlineDepth` levels and adds the deposit amount to `totalDownlineBusiness` and `freshBusiness`.

---

### `claimRank`
```solidity
    function claimRank() external nonReentrant {
```
- Allows manual rank upgrades. Checks and processes rank requirements, resetting the user's fresh business counters upon success.

---

### `_tryAutoRank`
```solidity
    function _tryAutoRank(address _user) internal {
```
- Automatically updates ranks during user actions (invest, withdraw) to simplify the user experience.

---

### `_checkRankQualification`
```solidity
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
```
- Enforces the **40/60 leg ratio** for rank upgrades:
  - The strongest downline leg contribution cannot exceed 40% of the target volume.
  - Weaker legs combined must contribute at least 60% of the target volume.

---

### `_resetDirectFreshBusiness`
```solidity
    function _resetDirectFreshBusiness(address _user) internal {
        address[] memory directs = userDirects[_user];
        for(uint256 i = 0; i < directs.length; i++) {
            users[directs[i]].freshBusiness = 0;
        }
    }
```
- Resets the `freshBusiness` volume tracking for direct legs after a rank upgrade or maintenance cycle.

---

### `_checkMaintenanceQualification`
```solidity
    function _checkMaintenanceQualification(address _user, uint8 _rank) internal view returns (bool) {
        uint256 target = perc_calc(rankReq[_rank], MIN_FRESH_BUSINESS); 
        ...
        return power >= perc_calc(target, 40) && weaker >= perc_calc(target, 60);
    }
```
- Verifies if the user meets the 25% fresh volume requirement (under the 40/60 leg rule) to maintain their rank salary.

---

### `_consumeMaintenanceVolume`
```solidity
    function _consumeMaintenanceVolume(address _user, uint8 _rank) internal {
        uint256 target = rankReq[_rank] / 5; 
        uint256 maxPerLeg = (target * 40) / 100;
        uint256 remainingToBurn = target;
        ...
```
- Deducts (burns) maintenance volume from active downline legs to prevent using the same business volume for multiple maintenance cycles.

---

### `_realizeSalary`
```solidity
    function _realizeSalary(address _user) internal {
```
- Calculates and credits rank salary linearly based on the time elapsed since the last claim.

---

### `getPendingSalary`
```solidity
    function getPendingSalary(address userAddress) public view returns (uint256) {
```
- Returns the accumulated, unclaimed salary for a user.

---

### `getLevelIncomeData`
```solidity
    function getLevelIncomeData(address _user) external view returns (uint256 pending, uint256 ratePerDay) {
```
- Returns the current level reward rate per day and any pending unclaimed rewards based on active downline nodes.

---

### `getPendingUplineIncome`
```solidity
    function getPendingUplineIncome(address _user) external view returns (uint256) {
```
- Calculates pending upline income from three levels of referrers based on their ROI earnings.

---

### `_checkAndToggleEligibility`
```solidity
    function _checkAndToggleEligibility(address _user) internal {
```
- Toggles a user's upline income eligibility based on their deposit size (must be >= 1,500 USDT) and direct referral count (must be >= 5).

---

### `_adjustUplineEligibleCounts`
```solidity
    function _adjustUplineEligibleCounts(address _user, bool _isAdd) internal {
```
- Updates active downline counters for uplines to ensure correct reward splits.

---

### `getTotalLifetimeRWP`
```solidity
    function getTotalLifetimeRWP(address _user) public view returns (uint256) {
```
- Calculates the lifetime ROI generated for a user across all active packages, applying compounding and booster rate increases.

---

### `_realizeUplineIncome`
```solidity
    function _realizeUplineIncome(address _user) internal {
```
- Calculates and credits pending upline rewards to the user's balance.

---

### `_resetUplineRwpTrackers`
```solidity
    function _resetUplineRwpTrackers(address _user) internal {
```
- Syncs the user's tracking indicators with the uplines' current lifetime ROI values.

---

### `_checkAndApplyBooster`
```solidity
    function _checkAndApplyBooster(address _user) internal {
```
- Grants a booster rate (+0.5% daily) if the user has referred at least 3 active partners with volume >= user's own deposit size within their first 7 days.

---

### `_realizeLevelIncome`
```solidity
    function _realizeLevelIncome(address _user) internal {
```
- Realizes pending level commission rewards.

---

### `_updateUplineStream`
```solidity
    function _updateUplineStream(address _user, uint256 _amount, bool _isAdd, uint256 _rateFactor, bool _addTeamVolume) internal {
```
- Distributes level commission bases up to 40 levels of active referrers.

---

### `getSpotPrice`
```solidity
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
```
- Calculates the `i6` token price in USDT using PancakeSwap pair reserves.

---

### `_getMultiplier` and `_rpow`
- Exponentiation helper functions used to calculate compounding interest over time.

---

### `_updateCompounding`
```solidity
    function _updateCompounding(address userAddress) internal {
```
- Updates the compounded principal of all active investments using `_rpow`.

---

### `_swapTokenFromPancakev2`
```solidity
    function _swapTokenFromPancakev2(uint256 totalUsdtAmount, uint256 minTokensOut) internal {
```
- Handles the auto-swap and liquidity creation using the incoming USDT. Swaps 60% of USDT to project tokens, uses the remaining 40% to add liquidity (sent to burn address), and burns any leftover tokens to support price stability.

---

## 9. Administrative and DAO Functions

- **`setROI(uint256 _value)`**: Sets base daily ROI (0.2% to 1.0% daily).
- **`setWithdrawalHourlyLimit(...)`**: Sets maximum withdrawal limits for ROI, direct bonus, level, upline, and salary.
- **`setLevelROI(...)`**: Sets level payout percentages for downline layers.
- **`setSalaryFreshBusiness(uint256 _value)`**: Configures rank maintenance fresh business percentage.
- **`setMaxDownlineDepth(uint256 _newDepth)`**: Restricts referral downline propagation depth.
- **`setLiquiditySlippage(uint256 _slippage)`**: Sets allowed slippage for PancakeSwap interactions.
- **`setTradingPair(address _newPair)`**: Sets the PancakeSwap pair address.
- **`setDexRouter(address _newRouter)`**: Sets the DEX router address.
- **`setMinInvestment(uint256 _amount)`**: Configures minimum investment size.
- **`updateDAOMultisignController(address _multisigController)`**: Migrates administrative controls to a new DAO address.
- **`rescueAccidentalTokens(...)`**: Recovers accidentally sent tokens. Restricts rescuing the `i6` reward token.

---

## 10. Clear Working Explanation in English

The `InfinitySixSystem` contract acts as the main system and investment coordinator for the project. It handles deposits, calculates daily compounding yields, manages referral commissions, updates user ranks, and automates liquidity operations.

### The Investment Lifecycle
Users participate by depositing USDT (minimum 100 USDT). When an investment is made, the contract automatically swaps **60%** of the USDT for `i6` tokens on PancakeSwap. The remaining **40%** of the USDT is paired with those tokens and added as liquidity to the PancakeSwap pool. The LP tokens are sent to `0xdead` to permanently lock the liquidity. Any leftover tokens from the swap are burned.

Each deposit creates a new investment package that generates a daily compound yield (starting at 0.5% daily). This compounding interest accumulates on the active principal.

### Referral and Structure Rewards
The system features a multi-tiered referral model:
1. **Direct Referral Commission**: Referrers receive a 5% commission on direct downline investments, locked for 12 hours.
2. **Booster System**: Referrers who invite 3 active partners with deposits matching or exceeding their own deposit size within their first 7 days get a booster (+0.5% daily ROI increase).
3. **Level Income**: Generates commissions up to 40 levels downline based on active downline ROI.
4. **Upline Income**: Users with at least a 1,500 USDT deposit and 5 direct referrals earn a share of the ROI generated by their 3 immediate uplines.

### Rank Salary and Maintenance
Users advance through 10 ranks based on downline volume. Ranks are evaluated under the **40/60 leg rule** (no single leg can contribute more than 40% of the target volume). Advancing ranks unlocks a monthly salary paid linearly over 30 days. To keep receiving the salary, users must generate fresh downline business equal to 25% of the rank requirement every 30 days.

### Capping and Withdrawals
Users can request withdrawals at any time, subject to a 60-minute cooldown and a 3-day post-launch wait. The system calculates earnings across all categories (ROI, Directs, Levels, Uplines, Salary) and applies category caps. 

An individual package stops generating ROI once it has paid out **2.5x (250%)** of its original value. Additionally, a global **6x (600%)** earnings multiplier applies: once a user's total withdrawals reach 6 times their total deposits, they are flagged as capped, and all reward generation and upline eligibility are disabled.

Withdrawal payouts are calculated in USDT but minted and paid out in `i6` tokens based on the current market price (minus a 5% transaction fee).

---

## 11. Mutable Parameters and Administrative Variables

The following state variables, settings, and parameters are mutable in the system contract and can be adjusted by the authorized DAO/owner addresses:

- **MIN_ROI_PERC** (adjustable via `setROI`): Sets the base daily interest rate (restricted between 0.2% and 1.0% daily).
- **Withdrawal Hourly Limits** (adjustable via `setWithdrawalHourlyLimit`):
  - `ROI_MAX_WITHDRAWAL`: Limits maximum ROI withdrawn per hour/transaction.
  - `DIRECT_MAX_WITHDRAWAL`: Limits maximum direct bonuses withdrawn per hour/transaction.
  - `LEVEL_MAX_WITHDRAWAL`: Limits maximum level rewards withdrawn per hour/transaction.
  - `UPLINE_INC_MAX_WITHDRAWAL`: Limits maximum upline income withdrawn per hour/transaction.
  - `SALARY_MAX_WITHDRAWAL`: Limits maximum rank salary withdrawn per hour/transaction.
- **Level ROI split rates** (adjustable via `setLevelROI`): Sets downline layer percentages for level income streams (e.g. `MAX_L1_PERC` to `MAX_L4_PERC`).
- **MIN_FRESH_BUSINESS** (adjustable via `setSalaryFreshBusiness`): Sets the required percentage (restricted between 20% and 50%) of the rank threshold needed as fresh business for salary maintenance.
- **maxDownlineDepth** (adjustable via `setMaxDownlineDepth`): Restricts the number of uplines that receive business volume credit (restricted to >= 100).
- **liquiditySlippage** (adjustable via `setLiquiditySlippage`): Configures slippage tolerance for PancakeSwap exchanges (restricted between 1% and 25%).
- **uniswapPair** (adjustable via `setTradingPair`): Configures the PancakeSwap trading pair address.
- **dexRouter** (adjustable via `setDexRouter`): Configures the DEX router address.
- **MIN_INVESTMENT** (adjustable via `setMinInvestment`): Configures the minimum USDT deposit amount.
- **DAOMultisigController** (adjustable via `updateDAOMultisignController`): Updates the administrative controller wallet address.

