SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = '2014-06-18 13:30'

IF object_id('tempdb.dbo.#allRCViewers') IS NOT NULL DROP TABLE #allRCViewers;
SELECT DISTINCT
	sal.UserID
	,Decile = RIGHT(LEFT(u.TestingGuid, 18), 1)
	,Cohort = CASE   
		WHEN RIGHT(LEFT(u.TestingGuid, 18), 1) IN ('1','3','5','7','9','B','D','F') AND sa.Details.value('(//RateCardLog/IsTabbed)[1]', 'nvarchar(max)') = 'true' THEN 'Test'
		WHEN RIGHT(LEFT(u.TestingGuid, 18), 1) IN ('0','2','4','6','8','A','C','E') AND sa.Details.value('(//RateCardLog/IsTabbed)[1]', 'nvarchar(max)') = 'false' THEN 'Control'
		END
	,sal.[SID]
	,sal.LogDateTime
	,SignupDt = CAST(u.SignupDt AS DATE)
INTO #allRCViewers
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN [ProfileReadData].[dbo].[Users] u WITH (NOLOCK) ON u.UserID = sal.UserID 
	AND u.LoginDisabled = 0 -- remove fraud
	AND u.SiteCode = 1 -- Site Code 1 only
WHERE sa.AssetKey = 'RateCard'
AND sal.LogDateTime >= @StartDate
AND sa.Details.value('(//RateCardLog/PromoId)[1]', 'nvarchar(max)') <> 'default' -- Only Promo takers
AND sa.Details.value('(//RateCardLog/IsCommunication)[1]', 'nvarchar(max)') = 'false' -- Not in communication path
AND sa.Details.value('(//RateCardLog/IsOneClick)[1]', 'nvarchar(max)') = 'false' -- Not 1-Click
AND sa.Details.value('(//RateCardLog/IsMobile)[1]', 'nvarchar(max)') = 'false' -- No mobile users
CREATE INDEX idx_#allRCViewers1 on #allRCViewers(UserID)
CREATE INDEX idx_#allRCViewers2 on #allRCViewers(UserID, SID)


IF object_id('tempdb.dbo.#rcViewCnt') IS NOT NULL DROP TABLE #rcViewCnt;
SELECT 
	Cohort
	,Users = COUNT(DISTINCT UserID)
INTO #rcViewCnt
FROM #allRCViewers
WHERE Cohort IS NOT NULL
GROUP BY Cohort


---- PAYMENT PAGE VIEWS
IF object_id('tempdb.dbo.#allPmtViewers') IS NOT NULL DROP TABLE #allPmtViewers; 
SELECT DISTINCT
	sal.[SID] 
	,sal.UserID
	,cc.Cohort 
	,sal.LogDateTime 
	,cc.SignupDt
INTO #allPmtViewers
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #allRCViewers cc ON sal.UserID = cc.UserID AND sal.[SID] = cc.[SID]
WHERE sa.AssetKey = 'PaymentPage'
AND sal.LogDateTime >= @StartDate
AND cc.Cohort IS NOT NULL
create index idx_tmp2a on #allPmtViewers(UserID)
create index idx_tmp2b on #allPmtViewers(UserID, SID)



---- DISTINCT PAYMENT PAGE VIEWERS
IF object_id('tempdb.dbo.#pmtViewCnt') IS NOT NULL DROP TABLE #pmtViewCnt;        
SELECT 
	Cohort
	,Users = COUNT(DISTINCT UserID)
INTO #pmtViewCnt
FROM #allPmtViewers
GROUP BY Cohort

-- SELECT * FROM #pmtViewCnt


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
	,a.Cohort
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
	a.Cohort
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
GROUP BY a.Cohort
ORDER BY a.Cohort


DELETE FROM WorkDB.dbo.MK_PromoRateCard;
INSERT INTO WorkDB.dbo.MK_PromoRateCard (Cohort,RCViewers,PmntViewers,Subs,RC_Pmnt,Pmnt_Sub,RC_Sub,TotalCash,ARPU,Resignations,ResignRate)
SELECT
	[Cohort] = r.Cohort
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
LEFT JOIN #pmtViewCnt p ON r.Cohort = p.Cohort
LEFT JOIN #trxSummary t ON r.Cohort = t.Cohort
GROUP BY r.Cohort
ORDER BY r.Cohort


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
	,[Resignations]
	,[Resign %] = ResignRate
FROM WorkDB.dbo.MK_PromoRateCard



--TRUNCATE TABLE WorkDB.dbo.MK_PromoRateCard;
--DROP TABLE WorkDB.dbo.MK_PromoRateCard;
--CREATE TABLE WorkDB.dbo.MK_PromoRateCard (
--	Cohort VARCHAR(MAX)
--	,RCViewers INT
--	,PmntViewers INT
--	,Subs INT
--	,RC_Pmnt DECIMAL(10,2)
--	,Pmnt_Sub DECIMAL(10,2)
--	,RC_Sub DECIMAL(10,2)
--	,TotalCash DECIMAL(10,2)
--	,ARPU DECIMAL(10,2)
--	,Resignations INT
--	,ResignRate DECIMAL(10,2)
-- );