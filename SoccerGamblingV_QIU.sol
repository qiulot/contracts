pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "./QIUToken.sol";

/**
 * @title SoccerGamblingV_QIU
 * @dev SoccerGamblingV_QIU 是球乐中的主要合同，主要作用是发起竞猜，参与竞猜的相关逻辑以及保障
 * 所有的竞猜以及球币返还逻辑均在此合同中定义以及执行
 */

contract SoccerGamblingV_QIU is Ownable {

    using SafeMath for uint;

    struct BettingInfo {
        uint id;
        address bettingOwner;
        bool buyHome;
        bool buyAway;
        bool buyDraw;
        uint bettingAmount;
    }
    
    struct GamblingPartyInfo {
        uint id;
        address dealerAddress; // 发起竞猜玩家的地址
        uint homePayRate;
        uint awayPayRate;
        uint drawPayRate;
        uint payRateScale;
        uint bonusPool; // 以Wei作为单位
        uint baseBonusPool;
        int finalScoreHome;
        int finalScoreAway;
        bool isEnded;
        bool isLockedForBet;
        BettingInfo[] bettingsInfo;
    }

    mapping (uint => GamblingPartyInfo) public gamblingPartiesInfo;
    mapping (uint => uint[]) public matchId2PartyId;
    uint private _nextGamblingPartyId;
    uint private _nextBettingInfoId;
    QIUToken public _internalToken;

    uint private _commissionNumber;
    uint private _commissionScale;
    

    function SoccerGamblingV_QIU(QIUToken _tokenAddress) public {
        _nextGamblingPartyId = 0;
        _nextBettingInfoId = 0;
        _internalToken = _tokenAddress;
        _commissionNumber = 2;
        _commissionScale = 100;
    }

    function modifyCommission(uint number,uint scale) public onlyOwner returns(bool){
        _commissionNumber = number;
        _commissionScale = scale;
        return true;
    }

    function _availableBetting(uint gamblingPartyId,uint8 buySide,uint bettingAmount) private view returns(bool) {
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        uint losePay = 0;
        if (buySide==0)
            losePay = losePay.add((gpInfo.homePayRate.mul(bettingAmount)).div(gpInfo.payRateScale));
            //losePay += gpInfo.homePayRate * bettingAmount / gpInfo.payRateScale;
        else if (buySide==1)
            losePay = losePay.add((gpInfo.awayPayRate.mul(bettingAmount)).div(gpInfo.payRateScale));
        else if (buySide==2)
            losePay = losePay.add((gpInfo.drawPayRate.mul(bettingAmount)).div(gpInfo.payRateScale));
        uint mostPay = 0;
        for (uint idx = 0; idx<gpInfo.bettingsInfo.length; idx++) {
            BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
            if (bInfo.buyHome && (buySide==0))
                mostPay = mostPay.add((gpInfo.homePayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
            else if (bInfo.buyAway && (buySide==1))
                mostPay = mostPay.add((gpInfo.awayPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
            else if (bInfo.buyDraw && (buySide==2))
                mostPay = mostPay.add((gpInfo.drawPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
                //mostPay += gpInfo.drawPayRate * bInfo.bettingAmount / gpInfo.payRateScale;
        }
        if (mostPay + losePay > gpInfo.bonusPool)
            return false;
        else 
            return true;
    }

    event NewBettingSucceed(address fromAddr,uint newBettingInfoId);
    function betting(uint gamblingPartyId,uint8 buySide,uint bettingAmount) public {
        require(bettingAmount > 0);
        require(_internalToken.balanceOf(msg.sender) >= bettingAmount);
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        require(gpInfo.isEnded == false);
        require(gpInfo.isLockedForBet == false);
        require(_availableBetting(gamblingPartyId, buySide, bettingAmount));
        BettingInfo memory bInfo;
        bInfo.id = _nextBettingInfoId;
        bInfo.bettingOwner = msg.sender;
        bInfo.buyHome = false;
        bInfo.buyAway = false;
        bInfo.buyDraw = false;
        bInfo.bettingAmount = bettingAmount;
        if (buySide == 0)
            bInfo.buyHome = true;
        if (buySide == 1)
            bInfo.buyAway = true;
        if (buySide == 2)
            bInfo.buyDraw = true;
        _internalToken.originTransfer(this,bettingAmount);
        gpInfo.bettingsInfo.push(bInfo);
        _nextBettingInfoId++;
        //gpInfo.bonusPool = gpInfo.bonusPool + msg.value;
        gpInfo.bonusPool = gpInfo.bonusPool.add(bettingAmount);
        NewBettingSucceed(msg.sender,bInfo.id);
    }

    function remainingBettingFor(uint gamblingPartyId) public view returns
        (uint remainingAmountHome,
         uint remainingAmountAway,
         uint remainingAmountDraw
        ) {
        for (uint8 buySide = 0;buySide<3;buySide++){
            GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
            uint bonusPool = gpInfo.bonusPool;
            for (uint idx = 0; idx<gpInfo.bettingsInfo.length; idx++) {
                BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
                if (bInfo.buyHome && (buySide==0))
                    bonusPool = bonusPool.sub((gpInfo.homePayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
                    //bonusPool = bonusPool - (gpInfo.homePayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                else if (bInfo.buyAway && (buySide==1))
                    bonusPool = bonusPool.sub((gpInfo.awayPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
                    //bonusPool = bonusPool - (gpInfo.awayPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                else if (bInfo.buyDraw && (buySide==2))
                    bonusPool = bonusPool.sub((gpInfo.drawPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale));
                    //bonusPool = bonusPool - (gpInfo.drawPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
            }
            if (buySide == 0)
                remainingAmountHome = (bonusPool.mul(gpInfo.payRateScale)).div(gpInfo.homePayRate);
                //remainingAmountHome = bonusPool * gpInfo.payRateScale / gpInfo.homePayRate;
            else if (buySide == 1)
                remainingAmountAway = (bonusPool.mul(gpInfo.payRateScale)).div(gpInfo.awayPayRate);
                //remainingAmountAway = bonusPool * gpInfo.payRateScale / gpInfo.awayPayRate;
            else if (buySide == 2)
                remainingAmountDraw = (bonusPool.mul(gpInfo.payRateScale)).div(gpInfo.drawPayRate);
                //remainingAmountDraw = bonusPool * gpInfo.payRateScale / gpInfo.drawPayRate;
        }
    }

    event MatchAllGPsLock(address fromAddr,uint matchId,bool isLocked);
    function lockUnlockMatchGPForBetting(uint matchId,bool lock) public {
        uint[] storage gamblingPartyIds = matchId2PartyId[matchId];
        for (uint idx = 0;idx < gamblingPartyIds.length;idx++) {
            lockUnlockGamblingPartyForBetting(gamblingPartyIds[idx],lock);
        }
        MatchAllGPsLock(msg.sender,matchId,lock);        
    }

    function lockUnlockGamblingPartyForBetting(uint gamblingPartyId,bool lock) public onlyOwner {
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        gpInfo.isLockedForBet = lock;
    }

    function getGamblingPartyInfo(uint gamblingPartyId) public view returns (uint gpId,
                                                                            address dealerAddress,
                                                                            uint homePayRate,
                                                                            uint awayPayRate,
                                                                            uint drawPayRate,
                                                                            uint payRateScale,
                                                                            uint bonusPool,
                                                                            int finalScoreHome,
                                                                            int finalScoreAway,
                                                                            bool isEnded) 
    {

        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        gpId = gpInfo.id;
        dealerAddress = gpInfo.dealerAddress; // The address of the inital founder
        homePayRate = gpInfo.homePayRate;
        awayPayRate = gpInfo.awayPayRate;
        drawPayRate = gpInfo.drawPayRate;
        payRateScale = gpInfo.payRateScale;
        bonusPool = gpInfo.bonusPool; // count by wei
        finalScoreHome = gpInfo.finalScoreHome;
        finalScoreAway = gpInfo.finalScoreAway;
        isEnded = gpInfo.isEnded;
    }

    //此函数中移除了部分非必要返回值，因为会导致如下编译时错误
    //exception is: CompilerError: Stack too deep, try removing local variables.
    //to get the extra value for the gambingParty , need to invoke the method getGamblingPartyInfo
    function getGamblingPartySummarizeInfo(uint gamblingPartyId) public view returns(
        uint gpId,
        //uint salesAmount,
        uint homeSalesAmount,
        int  homeSalesEarnings,
        uint awaySalesAmount,
        int  awaySalesEarnings,
        uint drawSalesAmount,
        int  drawSalesEarnings,
        int  dealerEarnings,
        uint baseBonusPool
    ){
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        gpId = gpInfo.id;
        baseBonusPool = gpInfo.baseBonusPool;
        for (uint idx = 0; idx < gpInfo.bettingsInfo.length; idx++) {
            BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
            //salesAmount += bInfo.bettingAmount;
            if (bInfo.buyHome){
                homeSalesAmount += bInfo.bettingAmount;
                if (gpInfo.isEnded && (gpInfo.finalScoreHome > gpInfo.finalScoreAway)){
                    homeSalesEarnings = homeSalesEarnings - int(bInfo.bettingAmount*gpInfo.homePayRate/gpInfo.payRateScale);
                }else
                    homeSalesEarnings += int(bInfo.bettingAmount);
            } else if (bInfo.buyAway){
                awaySalesAmount += bInfo.bettingAmount;
                if (gpInfo.isEnded && (gpInfo.finalScoreHome < gpInfo.finalScoreAway)){
                    awaySalesEarnings = awaySalesEarnings - int(bInfo.bettingAmount*gpInfo.awayPayRate/gpInfo.payRateScale);
                }else
                    awaySalesEarnings += int(bInfo.bettingAmount);
            } else if (bInfo.buyDraw){
                drawSalesAmount += bInfo.bettingAmount;
                if (gpInfo.isEnded && (gpInfo.finalScoreHome == gpInfo.finalScoreAway)){
                    drawSalesEarnings = drawSalesEarnings - int(bInfo.bettingAmount*gpInfo.drawPayRate/gpInfo.payRateScale);
                }else
                    drawSalesEarnings += int(bInfo.bettingAmount);
            }
        }
        int commission;    
        if(gpInfo.isEnded){
            dealerEarnings = int(gpInfo.bonusPool);
        }else{
            dealerEarnings = int(gpInfo.bonusPool);
            return;
        }
        if (homeSalesEarnings > 0){
            commission = homeSalesEarnings * int(_commissionNumber) / int(_commissionScale);
            homeSalesEarnings -= commission;
        }
        if (awaySalesEarnings > 0){
            commission = awaySalesEarnings * int(_commissionNumber) / int(_commissionScale);
            awaySalesEarnings -= commission;
        }
        if (drawSalesEarnings > 0){
            commission = drawSalesEarnings * int(_commissionNumber) / int(_commissionScale);
            drawSalesEarnings -= commission;
        }
        if (homeSalesEarnings < 0)
            dealerEarnings = int(gpInfo.bonusPool) + homeSalesEarnings;
        if (awaySalesEarnings < 0)
            dealerEarnings = int(gpInfo.bonusPool) + awaySalesEarnings;
        if (drawSalesEarnings < 0)
            dealerEarnings = int(gpInfo.bonusPool) + drawSalesEarnings;
        commission = dealerEarnings * int(_commissionNumber) / int(_commissionScale);
        dealerEarnings -= commission;
    }

    function getMatchSummarizeInfo(uint matchId) public view returns (
                                                            uint mSalesAmount,
                                                            uint mHomeSalesAmount,
                                                            uint mAwaySalesAmount,
                                                            uint mDrawSalesAmount,
                                                            int mDealerEarnings,
                                                            uint mBaseBonusPool
                                                        )
    {
        for (uint idx = 0; idx<matchId2PartyId[matchId].length; idx++) {
            uint gamblingPartyId = matchId2PartyId[matchId][idx];
            var (,homeSalesAmount,,awaySalesAmount,,drawSalesAmount,,dealerEarnings,baseBonusPool) = getGamblingPartySummarizeInfo(gamblingPartyId);
            mHomeSalesAmount += homeSalesAmount;
            mAwaySalesAmount += awaySalesAmount;
            mDrawSalesAmount += drawSalesAmount;
            mSalesAmount += homeSalesAmount + awaySalesAmount + drawSalesAmount;
            mDealerEarnings += dealerEarnings;
            mBaseBonusPool = baseBonusPool;
        }
    }

    function getSumOfGamblingPartiesBonusPool(uint matchId) public view returns (uint) {
        uint sum = 0;
        for (uint idx = 0; idx<matchId2PartyId[matchId].length; idx++) {
            uint gamblingPartyId = matchId2PartyId[matchId][idx];
            GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
            sum += gpInfo.bonusPool;
        }
        return sum;
    }

    function getWinLoseAmountByBettingOwnerInGamblingParty(uint gamblingPartyId,address bettingOwner) public view returns (int) {
        int winLose = 0;
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        require(gpInfo.isEnded);
        for (uint idx = 0; idx < gpInfo.bettingsInfo.length; idx++) {
            BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
            if (bInfo.bettingOwner == bettingOwner) {
                if ((gpInfo.finalScoreHome > gpInfo.finalScoreAway) && (bInfo.buyHome)) {
                    winLose += int(gpInfo.homePayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else if ((gpInfo.finalScoreHome < gpInfo.finalScoreAway) && (bInfo.buyAway)) {
                    winLose += int(gpInfo.awayPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else if ((gpInfo.finalScoreHome == gpInfo.finalScoreAway) && (bInfo.buyDraw)) {
                    winLose += int(gpInfo.drawPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else {
                    winLose -= int(bInfo.bettingAmount);
                }
            }
        }   
        if (winLose > 0){
            int commission = winLose * int(_commissionNumber) / int(_commissionScale);
            winLose -= commission;
        }
        return winLose;
    }

    function getWinLoseAmountByBettingIdInGamblingParty(uint gamblingPartyId,uint bettingId) public view returns (int) {
        int winLose = 0;
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        require(gpInfo.isEnded);
        for (uint idx = 0; idx < gpInfo.bettingsInfo.length; idx++) {
            BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
            if (bInfo.id == bettingId) {
                if ((gpInfo.finalScoreHome > gpInfo.finalScoreAway) && (bInfo.buyHome)) {
                    winLose += int(gpInfo.homePayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else if ((gpInfo.finalScoreHome < gpInfo.finalScoreAway) && (bInfo.buyAway)) {
                    winLose += int(gpInfo.awayPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else if ((gpInfo.finalScoreHome == gpInfo.finalScoreAway) && (bInfo.buyDraw)) {
                    winLose += int(gpInfo.drawPayRate * bInfo.bettingAmount / gpInfo.payRateScale);
                } else {
                    winLose -= int(bInfo.bettingAmount);
                }
                break;
            }
        }   
        if (winLose > 0){
            int commission = winLose * int(_commissionNumber) / int(_commissionScale);
            winLose -= commission;
        }
        return winLose;
    }

    event NewGamblingPartyFounded(address fromAddr,uint newGPId);
    //在测试用例中用来Debug的事件
    //event DBG(address sender,uint balance);
    function foundNewGamblingParty(
        uint matchId,
        uint homePayRate,
        uint awayPayRate,
        uint drawPayRate,
        uint payRateScale,
        uint basePool
        ) public
        {
        address sender = msg.sender;
        require(basePool > 0);
        require(_internalToken.balanceOf(sender) >= basePool);
        uint newId = _nextGamblingPartyId;
        gamblingPartiesInfo[newId].id = newId;
        gamblingPartiesInfo[newId].dealerAddress = sender;
        gamblingPartiesInfo[newId].homePayRate = homePayRate;
        gamblingPartiesInfo[newId].awayPayRate = awayPayRate;
        gamblingPartiesInfo[newId].drawPayRate = drawPayRate;
        gamblingPartiesInfo[newId].payRateScale = payRateScale;
        gamblingPartiesInfo[newId].bonusPool = basePool;
        gamblingPartiesInfo[newId].baseBonusPool = basePool;
        gamblingPartiesInfo[newId].finalScoreHome = -1;
        gamblingPartiesInfo[newId].finalScoreAway = -1;
        gamblingPartiesInfo[newId].isEnded = false;
        gamblingPartiesInfo[newId].isLockedForBet = false;
        _internalToken.originTransfer(this,basePool);
        matchId2PartyId[matchId].push(gamblingPartiesInfo[newId].id);
        _nextGamblingPartyId++;
        NewGamblingPartyFounded(sender,newId);//fire event
    }

    event MatchAllGPsEnded(address fromAddr,uint matchId);
    function endMatch(uint matchId,int homeScore,int awayScore) public {
        uint[] storage gamblingPartyIds = matchId2PartyId[matchId];
        for (uint idx = 0;idx < gamblingPartyIds.length;idx++) {
            endGamblingParty(gamblingPartyIds[idx],homeScore,awayScore);
        }
        MatchAllGPsEnded(msg.sender,matchId);        
    }

    event GamblingPartyEnded(address fromAddr,uint gamblingPartyId);
    function endGamblingParty(uint gamblingPartyId,int homeScore,int awayScore) public onlyOwner {
        GamblingPartyInfo storage gpInfo = gamblingPartiesInfo[gamblingPartyId];
        require(!gpInfo.isEnded);
        gpInfo.finalScoreHome = homeScore;
        gpInfo.finalScoreAway = awayScore;
        gpInfo.isEnded = true;
        int flag = -1;
        if (homeScore > awayScore)
            flag = 0;
        else if (homeScore < awayScore)
            flag = 1;
        else
            flag = 2;
        uint commission; // variable for commission caculation.
        uint bonusPool = gpInfo.bonusPool;
        for (uint idx = 0; idx < gpInfo.bettingsInfo.length; idx++) {
            BettingInfo storage bInfo = gpInfo.bettingsInfo[idx];
            uint transferAmount = 0;
            if (flag == 0 && bInfo.buyHome)
                transferAmount = (gpInfo.homePayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale);
                //transferAmount = gpInfo.homePayRate * bInfo.bettingAmount / gpInfo.payRateScale;
            if (flag == 1 && bInfo.buyAway)
                transferAmount = (gpInfo.awayPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale);
                //transferAmount = gpInfo.awayPayRate * bInfo.bettingAmount / gpInfo.payRateScale;
            if (flag == 2 && bInfo.buyDraw)
                transferAmount = (gpInfo.drawPayRate.mul(bInfo.bettingAmount)).div(gpInfo.payRateScale);
                //transferAmount = gpInfo.drawPayRate * bInfo.bettingAmount / gpInfo.payRateScale;
            if (transferAmount != 0) {
                bonusPool = bonusPool.sub(transferAmount);
                //bonusPool = bonusPool - transferAmount;
                commission = (transferAmount.mul(_commissionNumber)).div(_commissionScale);
                //commission = transferAmount * _commissionNumber / _commissionScale;
                transferAmount = transferAmount.sub(commission);
                //transferAmount -= commission;
                _internalToken.ownerTransferFrom(this,bInfo.bettingOwner,transferAmount);
                _internalToken.ownerTransferFrom(this,owner,commission);
            }
        }    
        if (bonusPool > 0) {
            uint amount = bonusPool;
            // subs the commission
            commission = (amount.mul(_commissionNumber)).div(_commissionScale);
            //commission = amount * _commissionNumber / _commissionScale;
            amount = amount.sub(commission);
            //amount -= commision;         
            //gpInfo.dealerAddress.transfer(amount);
            _internalToken.ownerTransferFrom(this,gpInfo.dealerAddress,amount);
            _internalToken.ownerTransferFrom(this,owner,commission);
        }
        GamblingPartyEnded(msg.sender,gpInfo.id);
    }

    function getETHBalance() public view returns (uint) {
        return this.balance; // balance is "inherited" from the address type
    }
}