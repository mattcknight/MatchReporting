SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = '2014-06-11 14:00:00'

IF object_id('tempdb.dbo.#phase4pop_tmp') IS NOT NULL DROP TABLE #phase4pop_tmp;  
SELECT 
	DISTINCT 
	sil.UserID
	,Score = si.Details.value('(//Score)[1]', 'NUMERIC(20,5)')
	,ScoreGroup = CASE 
		WHEN si.Details.value('(//Score)[1]', 'NUMERIC(20,5)') = 1 THEN 'Group 01'
		WHEN si.Details.value('(//Score)[1]', 'NUMERIC(20,5)') = 0 THEN 'Group 02'
		END 
	,sil.[SID]
	,Decile = RIGHT(LEFT(u.TestingGuid, 4), 1)
	,SignupDt = CAST(u.SignupDt AS DATE)
	,NewReg = CASE WHEN SignupDt< @StartDate THEN 1 ELSE 0 END
INTO #phase4pop_tmp
FROM [Match_4].[dbo].[SiteInstrumentationLog] sil WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteInstrumentation] si WITH (NOLOCK) ON si.luSiteInstrumentationID = sil.luSiteInstrumentationID 
	AND si.AssetKey='PriceTargetingV2Evaluated'
	and si.Details.value('(//IsInTest)[1]', 'nvarchar(max)') = 'True'
	and si.Details.value('(//Score)[1]', 'INT') = 1
JOIN [ProfileReadData].[dbo].[Users] u WITH (NOLOCK) ON u.UserID = sil.UserID 
	AND u.SiteCode = 1
WHERE sil.LogDateTime >= @StartDate
CREATE INDEX idx_#phase4pop_tmp on #phase4pop_tmp(UserID)

-- Ivans Fraud Rule
if object_id ('tempdb.dbo.#Fraud_Users') is not null drop table #Fraud_Users
select brc.userid 
into #Fraud_Users 
from #phase4pop_tmp rd
INNER JOIN [Match_4].[dbo].[billresigncomm] brc WITH (NOLOCK) on rd.userID = brc .UserID
WHERE brc.resigntype = 'K'
AND DATEDIFF (ss, rd.SignUpDt ,brc.resigndt) < 604800 -- 7 days
AND brc.resigncode not in (42 ,112, 1025)


if object_id('tempdb.dbo.#phase4pop') is not null drop table #phase4pop; 
select us.*
into #phase4pop
from #phase4pop_tmp us 
left join #Fraud_Users fr on fr.UserID = us.UserID
where fr.UserID IS NULL


IF object_id('tempdb.dbo.#RateCardViews') IS NOT NULL DROP TABLE #RateCardViews; 
SELECT 
	sal.UserID
	,sal.LogDateTime
INTO #RateCardViews
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #phase4pop p4 ON sal.UserID = p4.UserID
WHERE sa.AssetKey = 'RateCard'
GROUP BY sal.UserID, sal.LogDateTime
CREATE INDEX idx_#RateCardViews on #RateCardViews(UserID)


IF object_id('tempdb.dbo.#allRCViewers') IS NOT NULL DROP TABLE #allRCViewers;
SELECT DISTINCT
    sal.[SID]
    ,sal.UserID
    ,p4.Score
	,p4.Decile
	,PTP_ID = sa.Details.value('(//RateCardLog/PriceTargetingPromoId)[1]', 'nvarchar(max)')
	,p4.ScoreGroup
	,UserGroup = CASE
		WHEN p4.ScoreGroup = 'Group 01' THEN
			CASE   
				WHEN p4.Decile IN ('0','1','2','3') THEN 'Control'
				WHEN p4.Decile IN ('4','5','6','7','8','9','A','B','C','D','E','F') THEN 'Test (7.5% Up)'
				END
		WHEN p4.ScoreGroup = 'Group 02' THEN '03 - Control'
		END
	,PromoRateCardTest = CASE   
		WHEN p4.Decile IN ('1','3','5','7','9','B','D','F') THEN 'Test'
		WHEN p4.Decile IN ('0','2','4','6','8','A','C','E') THEN 'Control'
		END
	,p4.SignupDt
    ,sal.LogDateTime
INTO #allRCViewers
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #phase4pop p4 ON sal.UserID = p4.UserID 
	AND p4.[SID] = sal.[SID]
JOIN #RateCardViews rc ON rc.UserID = sal.UserID 
	AND sal.LogDateTime = rc.LogDateTime
WHERE sa.AssetKey = 'RateCard'
CREATE INDEX idx_#allRCViewers1 on #allRCViewers(UserID)
CREATE INDEX idx_#allRCViewers2 on #allRCViewers(UserID, SID)


IF object_id('tempdb.dbo.#rcViewCnt') IS NOT NULL DROP TABLE #rcViewCnt;
SELECT 
	UserGroup
	,ScoreGroup
	,Users = COUNT(DISTINCT UserID)
INTO #rcViewCnt
FROM #allRCViewers
WHERE UserGroup IS NOT NULL
GROUP BY 
	UserGroup
	,ScoreGroup


---- PAYMENT PAGE VIEWS
IF object_id('tempdb.dbo.#allPmtViewers') IS NOT NULL DROP TABLE #allPmtViewers; 
SELECT DISTINCT
	sal.[SID] 
	,sal.UserID  
	,cc.Score
	,cc.ScoreGroup
	,cc.UserGroup  
	,sal.LogDateTime 
	,cc.SignupDt
INTO #allPmtViewers
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #allRCViewers cc ON sal.UserID = cc.UserID AND sal.[SID] = cc.[SID]
WHERE sa.AssetKey = 'PaymentPage'
AND sal.LogDateTime >= @StartDate
AND cc.UserGroup IS NOT NULL
create index idx_tmp2a on #allPmtViewers(UserID)
create index idx_tmp2b on #allPmtViewers(UserID, SID)


---- DISTINCT PAYMENT PAGE VIEWERS
IF object_id('tempdb.dbo.#pmtViewCnt') IS NOT NULL DROP TABLE #pmtViewCnt;        
SELECT 
	UserGroup
	,ScoreGroup
	,Users = COUNT(DISTINCT UserID)
INTO #pmtViewCnt
FROM #allPmtViewers
GROUP BY 
	UserGroup
	,ScoreGroup


---- PAYMENTS RECIEVED
IF object_id('tempdb.dbo.#trx') IS NOT NULL DROP TABLE #trx;                    
SELECT DISTINCT 
	t.UserID
	,t.CreateDt
	,CreateDay = CAST(t.CreateDt AS DATE)
	,PD.Months
	,PG.IsBundled
	,p.ProdID
	,t.PreTaxAmt
	,PD.RenewalAmt 
	,current_BeginDt = AD.BeginDt
	,current_EndDt = AD.EndDt
	,ao.[SID]
	,a.UserGroup
	,a.Score
	,a.ScoreGroup 
	,ao.PromoID
	,prom.Descr
	,a.SignupDt
	,SignupDay = CAST(a.SignupDt AS DATE)
	,t.StatusDt
	,DiscountPromoID = promdis.PromoID
	,Day_Purchased = DATEDIFF(DAY, a.SignupDt, t.statusdt)
INTO #trx 
FROM BillingData.dbo.Trx t WITH (NOLOCK)
JOIN BillingData.dbo.TrxDtl td WITH (NOLOCK) ON T.TrxID=TD.TrxID
JOIN BillingData.dbo.AcctDtl ad WITH (NOLOCK) ON TD.AcctDtlID=AD.AcctDtlID
JOIN BillingData.dbo.Acct act WITH (NOLOCK) ON ad.UserID=act.UserID
JOIN BillingData.dbo.AcctOrder ao WITH (NOLOCK) ON ad.AcctOrderID=ao.AcctOrderID
JOIN BillingData.dbo.ProdDtl pd WITH (NOLOCK) ON AD.ProdDtlID=PD.ProdDtlID
JOIN BillingData.dbo.ProdGrp pg WITH (NOLOCK) ON PG.ProdGrpID = PD.ProdGrpID
JOIN BillingData.dbo.Prod p WITH (NOLOCK) ON PD.ProdID=P.ProdID
JOIN BillingData.dbo.luProdFeature lpf WITH (NOLOCK) ON P.luProdFeatureID=lpf.luProdFeatureID
JOIN #allPmtViewers a WITH (NOLOCK) ON t.userid=a.UserID AND a.SID = ao.SID AND a.LogDateTime < t.CreateDt
JOIN BillingData.dbo.Promo prom WITH (NOLOCK) ON prom.PromoID = ao.PromoID 
LEFT JOIN BillingData.dbo.PromoDiscount promdis WITH (NOLOCK) ON ao.PromoID = promdis.PromoID
WHERE t.CreateDt >= @StartDate
AND t.luTrxTypeID In (1,8,12) -- New, BDC, Gift
AND t.luTrxStatusID = 1  -- SUCCESS
AND t.luTrxCategoryID IN (1,4) -- SALES and Gift Transfer
AND lpf.luProdFeatureID = 1
AND ad.BeginDt <> ad.EndDt


IF object_id('tempdb.dbo.#resignations') IS NOT NULL DROP TABLE #resignations;   
SELECT DISTINCT a.UserID 
INTO #resignations
FROM [BillingData].[dbo].[AcctDtl] a WITH (NOLOCK)
JOIN #allPmtViewers b ON a.UserID = b.UserID
WHERE luCancelTypeID = 1 
AND CancelDt IS NOT NULL


---- TRANSACTION SUMMARY
IF object_id('tempdb.dbo.#trxSummary') IS NOT NULL DROP TABLE #trxSummary;                    
SELECT 
	a.UserGroup
	,a.ScoreGroup
	,subs = COUNT(DISTINCT a.UserID)
	,totalCash = SUM(CAST(ISNULL(c.PreTaxAmt, 0.00) AS NUMERIC(18, 2)))
	,sum_square_totalCash = SUM(CAST(ISNULL(c.PreTaxAmt, 0.00) AS NUMERIC(18, 2)) * CAST(ISNULL(c.PreTaxAmt, 0.00) AS NUMERIC(18, 2)))
	,pkg_1MS = COUNT(DISTINCT CASE WHEN months = 1 THEN a.UserID ELSE NULL END)
	,pkg_3MS = COUNT(DISTINCT CASE WHEN months = 3 AND isbundled = 0 THEN a.UserID ELSE NULL END)
	,pkg_6MS = COUNT(DISTINCT CASE WHEN months = 6 AND isbundled = 0 THEN a.UserID ELSE NULL END)
	,pkg_12MS = COUNT(DISTINCT CASE WHEN months = 12 AND isbundled = 0 THEN a.UserID ELSE NULL END)
	,pkg_3MB = COUNT(DISTINCT CASE WHEN months = 3 AND isbundled = 1 AND prodid NOT IN (5158) THEN a.UserID ELSE NULL END)
	,pkg_3MBUpsell = COUNT(DISTINCT CASE WHEN months = 3 AND isbundled = 1 AND prodid IN (5158) THEN a.UserID ELSE NULL END)
	,pkg_6MB = COUNT(DISTINCT CASE WHEN months = 6 AND isbundled = 1 AND prodid NOT IN (5159) THEN a.userid ELSE NULL END)
	,pkg_6MBUpsell = COUNT(DISTINCT CASE WHEN months = 6 AND isbundled = 1 AND prodid IN (5159) THEN a.userid ELSE NULL END)
	,pkg_12MB = COUNT(DISTINCT CASE WHEN months = 12 AND isbundled = 1 AND prodid NOT IN (5160) THEN a.userid ELSE NULL END)
	,pkg_12MBUpsell = COUNT(DISTINCT CASE WHEN months = 12 AND isbundled = 1 AND prodid IN (5160) THEN a.userid ELSE NULL END)
	,resignations = SUM(CASE WHEN b.UserID IS NOT NULL THEN 1 ELSE 0 END)
INTO #trxSummary
FROM #trx a
LEFT JOIN #resignations b ON a.UserID = b.userid
INNER JOIN BillingData.dbo.Trx c ON a.userid = c.userid 
	AND c.luTrxStatusID = 1 
	AND c.CreateDt >= @StartDate
GROUP BY a.ScoreGroup, a.UserGroup
ORDER BY a.ScoreGroup, a.UserGroup


DELETE FROM WorkDB.dbo.MK_PriceTest4;
INSERT INTO WorkDB.dbo.MK_PriceTest4 (ScoreGroup,Cohort,RCViewers,PmntViewers,Subs,RC_Pmnt,Pmnt_Sub,RC_Sub,TotalCash,ARPU,Resignations,ResignRate)
SELECT 
	[Score Group] = r.ScoreGroup
	,[Cohort] = r.UserGroup
	,[RC Viewers] = SUM(ISNULL(r.Users, 0))
	,[Pmnt Viewers] = SUM(ISNULL(p.Users, 0))
	,[Subs] = SUM(ISNULL(t.subs, 0))
	,[RC to Pmnt %] = ISNULL(SUM(NULLIF(p.Users, 0.00)) / CAST(SUM(NULLIF(r.Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,[Pmnt to Sub %] = ISNULL(SUM(NULLIF(t.subs, 0.00)) / CAST(SUM(NULLIF(p.Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,RC_Sub = ISNULL(SUM(NULLIF(t.subs, 0.00)) / CAST(SUM(NULLIF(r.Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,[Total Cash] = ISNULL(SUM(NULLIF(t.totalCash, 0.00)),0.00)
	,[ARPU] = ISNULL(SUM(NULLIF(t.totalCash, 0.00)) / SUM(NULLIF(t.subs, 0.00)),0.00)
	,[Resignations] = ISNULL(SUM(NULLIF(resignations, 0)),0)
	,[Resign %] = ISNULL(SUM(NULLIF(resignations, 0.00)) / CAST(SUM(NULLIF(t.subs, 0.00)) AS DECIMAL(10,2)),0.00)
FROM #rcViewCnt r
LEFT JOIN #pmtViewCnt p ON r.UserGroup = p.UserGroup AND r.ScoreGroup = p.ScoreGroup
LEFT JOIN #trxSummary t ON r.UserGroup = t.UserGroup AND r.ScoreGroup = t.ScoreGroup
GROUP BY r.ScoreGroup, r.UserGroup
ORDER BY r.ScoreGroup, r.UserGroup


DROP TABLE #phase4pop
DROP TABLE #RateCardViews
DROP TABLE #allRCViewers
DROP TABLE #rcViewCnt
DROP TABLE #allPmtViewers
DROP TABLE #trx
DROP TABLE #resignations
DROP TABLE #pmtViewCnt
DROP TABLE #trxSummary

SELECT 
	[Score Group] = ScoreGroup
	,[Cohort]
	,[RC Viewers] = RCViewers
	,[Pmnt Viewers] = PmntViewers
	,[Subs]
	,[RC to Pmnt %] = RC_Pmnt
	,[Pmnt to Sub %] = Pmnt_Sub
	,[RC to Sub %] = RC_Sub
	,[Total Cash] = TotalCash
	,[ARPU]
	,[Resignations]
	,[Resign %] = ResignRate
FROM WorkDB.dbo.MK_PriceTest4



--TRUNCATE TABLE WorkDB.dbo.MK_PriceTest4;
--DROP TABLE WorkDB.dbo.MK_PriceTest4;
--CREATE TABLE WorkDB.dbo.MK_PriceTest4 (
--	ScoreGroup VARCHAR(MAX)
--	,Cohort VARCHAR(MAX)
--	,RCViewers INT
--	,PmntViewers INT
--	,Subs INT
--	,RC_Pmnt DECIMAL(18,4)
--	,Pmnt_Sub DECIMAL(18,4)
--	,RC_Sub DECIMAL(18,4)
--	,TotalCash DECIMAL(18,4)
--	,ARPU DECIMAL(18,4)
--	,Resignations INT
--	,ResignRate DECIMAL(18,4)
-- );