SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE 
	@StartDate DATETIME
	,@EndDate DATETIME
SELECT 
   @StartDate = '2014-06-27 14:00'
	,@EndDate = '2015-01-01'

IF object_id('tempdb.dbo.#phase4pop_tmp') IS NOT NULL DROP TABLE #phase4pop_tmp;  
SELECT
	DISTINCT
	sil.UserID
	,sil.[SID]
	,Decile = RIGHT(LEFT(u.TestingGuid, 4), 1)
	,UserGroup = CASE   
		WHEN RIGHT(LEFT(u.TestingGuid, 4), 1) IN ('0','1','2','3') THEN 'Control'
		WHEN RIGHT(LEFT(u.TestingGuid, 4), 1) IN ('4','5','6','7','8','9','A','B','C','D','E','F') THEN 'Test (7.5% Up)'
		END
	,SignupDt = CAST(u.SignupDt AS DATE)
	,NewReg = CASE WHEN u.SignupDt > @StartDate THEN 1 ELSE 0 END
INTO #phase4pop_tmp
FROM [Match_4].[dbo].[SiteInstrumentationLog] sil WITH (NOLOCK)
INNER JOIN [Match_4].[dbo].[luSiteInstrumentation] si WITH (NOLOCK) ON si.luSiteInstrumentationID = sil.luSiteInstrumentationID 
	AND si.AssetKey = 'PriceTargetingV2Evaluated'
	and si.Details.value('(//IsInTest)[1]', 'nvarchar(max)') = 'True'
	and si.Details.value('(//Score)[1]', 'INT') = 1
INNER JOIN [ProfileReadData].[dbo].[Users] u WITH (NOLOCK) ON u.UserID = sil.UserID
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
CREATE INDEX idx_#Fraud_Users on #Fraud_Users(UserID)


if object_id('tempdb.dbo.#phase4pop') is not null drop table #phase4pop; 
select us.*
into #phase4pop
from #phase4pop_tmp us 
left join #Fraud_Users fr on fr.UserID = us.UserID
where fr.UserID IS NULL
CREATE INDEX idx_#phase4pop on #phase4pop(UserID)


IF object_id('tempdb.dbo.#allRCViewers_tmp') IS NOT NULL DROP TABLE #allRCViewers_tmp;
SELECT DISTINCT
    sal.[SID]
    ,sal.UserID
	,p4.SignupDt
	,p4.Decile
	,p4.UserGroup
	,p4.NewReg
    ,sal.LogDateTime
INTO #allRCViewers_tmp
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
INNER JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
INNER JOIN #phase4pop p4 ON sal.UserID = p4.UserID 
	--AND p4.[SID] = sal.[SID]
WHERE sa.AssetKey = 'RateCard'
AND sal.LogDateTime >= @StartDate
CREATE INDEX idx_#allRCViewers1 on #allRCViewers_tmp(UserID)


IF object_id('tempdb.dbo.#allRCViewers_with_PrioSubInfo') IS NOT NULL DROP TABLE #allRCViewers_with_PrioSubInfo;
SELECT
	rc.[SID]
	,rc.UserID
	,rc.SignupDt
	,rc.Decile
	,rc.UserGroup
	,rc.NewReg
	,rc.LogDateTime
	,PriorSub = MAX(CASE WHEN fin.TrxID IS NOT NULL THEN 1 ELSE 0 END) 
INTO #allRCViewers_with_PrioSubInfo
FROM #allRCViewers_tmp rc
LEFT JOIN [MADW].[MatchMetrics].[Match\Matt Knight].[MK_rt_tbl_stage_Transactions] fin ON rc.UserID = fin.UserID
	AND fin.AccountType = 'Subscription Account' 
	AND fin.subtype IN ('FTS', 'Renewal', 'Resub')
	AND fin.trandate < @StartDate
GROUP BY
	rc.[SID]
	,rc.UserID
	,rc.SignupDt
	,rc.Decile
	,rc.UserGroup
	,rc.NewReg
	,rc.LogDateTime
CREATE INDEX idx_#allRCViewers1 ON #allRCViewers_with_PrioSubInfo(UserID)


IF object_id('tempdb.dbo.#allRCViewers') IS NOT NULL DROP TABLE #allRCViewers;  
SELECT * 
INTO #allRCViewers
FROM #allRCViewers_with_PrioSubInfo
WHERE PriorSub = 0
CREATE INDEX idx_#allRCViewers1 on #allRCViewers(UserID)
	

IF object_id('tempdb.dbo.#rcViewCnt') IS NOT NULL DROP TABLE #rcViewCnt;
SELECT 
	UserGroup
	,Users = COUNT(DISTINCT UserID)
INTO #rcViewCnt
FROM #allRCViewers
WHERE UserGroup IS NOT NULL
GROUP BY 
	UserGroup


---- PAYMENT PAGE VIEWS
IF object_id('tempdb.dbo.#allPmtViewers') IS NOT NULL DROP TABLE #allPmtViewers; 
SELECT DISTINCT
	sal.[SID] 
	,sal.UserID
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
CREATE INDEX idx_tmp2a on #allPmtViewers(UserID)


---- DISTINCT PAYMENT PAGE VIEWERS
IF object_id('tempdb.dbo.#pmtViewCnt') IS NOT NULL DROP TABLE #pmtViewCnt;        
SELECT 
	UserGroup
	,Users = COUNT(DISTINCT UserID)
INTO #pmtViewCnt
FROM #allPmtViewers
GROUP BY 
	UserGroup


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
AND t.CreateDt < @EndDate
AND t.luTrxTypeID In (1,8,12) -- New, BDC, Gift
AND t.luTrxStatusID = 1  -- SUCCESS
AND t.luTrxCategoryID IN (1,4) -- SALES and Gift Transfer
AND lpf.luProdFeatureID = 1
AND ad.BeginDt <> ad.EndDt
CREATE INDEX idx_#trx on #trx(UserID)


IF object_id('tempdb.dbo.#resignations') IS NOT NULL DROP TABLE #resignations;   
SELECT DISTINCT a.UserID 
INTO #resignations
FROM [BillingData].[dbo].[AcctDtl] a WITH (NOLOCK)
JOIN #allPmtViewers b ON a.UserID = b.UserID
WHERE luCancelTypeID = 1 
AND CancelDt IS NOT NULL
CREATE INDEX idx_#resignations on #resignations(UserID)


---- TRANSACTION SUMMARY
IF object_id('tempdb.dbo.#trxSummary') IS NOT NULL DROP TABLE #trxSummary;                    
SELECT 
	a.UserGroup
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
	AND c.CreateDt < @EndDate
GROUP BY a.UserGroup
ORDER BY a.UserGroup


DELETE FROM WorkDB.dbo.MK_PriceTest4;
INSERT INTO WorkDB.dbo.MK_PriceTest4 (Cohort,RCViewers,PmntViewers,Subs,RC_Pmnt,Pmnt_Sub,RC_Sub,TotalCash,ARPU,Resignations,ResignRate)
SELECT 
	[Cohort] = r.UserGroup
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
LEFT JOIN #pmtViewCnt p ON r.UserGroup = p.UserGroup
LEFT JOIN #trxSummary t ON r.UserGroup = t.UserGroup
GROUP BY r.UserGroup
ORDER BY r.UserGroup


DROP TABLE #phase4pop
DROP TABLE #allRCViewers
DROP TABLE #rcViewCnt
DROP TABLE #allPmtViewers
DROP TABLE #trx
DROP TABLE #resignations
DROP TABLE #pmtViewCnt
DROP TABLE #trxSummary

SELECT 
	[Cohort]
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
--	Cohort VARCHAR(MAX)
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