SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON 

-- Get all Phase II users
IF object_id('tempdb.dbo.#phaseIIpop') IS NOT NULL DROP TABLE #phaseIIpop;
SELECT 
	sal.userid
	,GenderAndGenderSeek = sa.Details.value('(//GenderAndGenderSeek)[1]', 'nvarchar(max)')
	,CurrentAge = sa.Details.value('(//CurrentAge)[1]', 'INT')
INTO #phaseIIpop
FROM [Match_4].[dbo].[SiteInstrumentationLog] sal WITH (NOLOCK)
INNER JOIN [Match_4].[dbo].[luSiteInstrumentation] sa WITH (NOLOCK) ON (sa.luSiteInstrumentationID = sal.luSiteInstrumentationID)
WHERE sa.AssetKey = 'PriceTargetingEvaluated' 
AND sa.Details.value('(//PriceTargetingPromoId)[1]', 'nvarchar(max)') = '1167'
ORDER BY sal.UserID
create index idx_#phaseIIpop on #phaseIIpop(UserID)


IF object_id('tempdb.dbo.#honoured') IS NOT NULL DROP TABLE #honoured; 
SELECT 
	sal.UserID
	,Honored = MAX(coalesce(sa.Details.value('(//Honored)[1]', 'BIT'),0))
INTO #honoured
FROM [Match_4].[dbo].[SiteInstrumentationLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteInstrumentation] sa WITH (NOLOCK) ON sa.luSiteInstrumentationID = sal.luSiteInstrumentationID 
	AND sa.AssetKey='PriceTargetingV1Evaluated'
WHERE CAST(CASE WHEN sa.Details.value('(//IsInTest)[1]', 'VARCHAR(10)') = 'true' THEN 1 ELSE 0 END AS BIT) = 1
AND coalesce(sa.Details.value('(//Honored)[1]', 'BIT'),0) != 0
GROUP BY sal.UserID
ORDER BY sal.UserID
create index idx_#honoured on #honoured(UserID)


IF object_id('tempdb.dbo.#phaseIIIpop') IS NOT NULL DROP TABLE #phaseIIIpop;  
SELECT 
	DISTINCT 
	sal.UserID
	,Score = sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)')
	,ScoreGroup = CASE 
			WHEN sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') > 18 THEN 'Group 01'
			WHEN sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') > 1.5 and sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') <= 18 THEN 'Group 02'
			WHEN sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') > 0.8 and sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') <= 1.5 THEN 'Group 03'
			WHEN sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') > 0.4 and sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') <= 0.8 THEN 'Group 04'
			WHEN sa.Details.value('(//Score)[1]', 'NUMERIC(20,5)') <= 0.4 THEN 'Group 05'
	  END 
	,ScoreRoundedDown = CAST(CASE WHEN sa.Details.value('(//ScoreRoundedDown)[1]', 'VARCHAR(100)') = 'true' THEN 1 ELSE 0 END AS BIT)
	,Honored = coalesce(sa.Details.value('(//Honored)[1]', 'BIT'),0) 
	,sal.SID
	,Decile = RIGHT(LEFT(u.TestingGuid, 4), 1)
	,SignupDt = CAST(u.SignupDt AS DATE)
INTO #phaseIIIpop
FROM [Match_4].[dbo].[SiteInstrumentationLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteInstrumentation] sa WITH (NOLOCK) ON sa.luSiteInstrumentationID = sal.luSiteInstrumentationID 
	AND sa.AssetKey='PriceTargetingV1Evaluated'
JOIN [ProfileReadData].[dbo].[Users] u WITH (NOLOCK) ON u.UserID = sal.UserID 
	AND u.LoginDisabled = 0 
	AND u.SignupDt >= '2014-05-05 12:30:00' -- remove fraud
	AND u.SIgnupDt < '2014-05-19 12:00:00'
JOIN #honoured h1 ON h1.UserID = sal.UserID 
	AND h1.Honored = coalesce(sa.Details.value('(//Honored)[1]', 'BIT'),0)
LEFT JOIN #phaseIIpop pII ON pII.userid = sal.UserID
WHERE pII.UserID IS NULL -- no phase 2 users
create index idx_#phaseIIIpop on #phaseIIIpop(UserID)


IF object_id('tempdb.dbo.#HounouredRC') IS NOT NULL DROP TABLE #HounouredRC; 
SELECT 
	sal.userid
	,logdatetime = min(sal.logdatetime)
INTO #HounouredRC
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #phaseIIIpop c1 ON sal.userid = c1.userid 
AND sal.logdatetime > CASE
	WHEN c1.Honored = 1 THEN SignupDt
	WHEN c1.Honored = 2 THEN DATEADD(dd, 1, SignupDt)
	END
WHERE sa.AssetKey = 'RateCard'
GROUP BY sal.userid
create index idx_#HounouredRC on #HounouredRC(UserID)


IF object_id('tempdb.dbo.#allRCViewers') IS NOT NULL DROP TABLE #allRCViewers;
SELECT DISTINCT
    sal.[SID]
    ,sal.UserID
    ,pIII.Score
	,pIII.Decile
	,PTP_ID = sa.Details.value('(//RateCardLog/PriceTargetingPromoId)[1]', 'nvarchar(max)')
	,pIII.ScoreGroup
	,UserGroup = CASE
		WHEN pIII.ScoreGroup = 'Group 01' THEN
			CASE   
				WHEN pIII.Decile IN ('0','1','2','3') THEN '01 - Control (25% lvl)'
				WHEN pIII.Decile IN ('4','5','6','7') THEN '02 - 5.0% Up (25% lvl)'
				WHEN pIII.Decile IN ('8','9','A','B') THEN '03 - 7.5% Up (25% lvl)'
				WHEN pIII.Decile IN ('C','D','E','F') THEN '04 - 10.0% Up (25% lvl)'
				END
		WHEN pIII.ScoreGroup = 'Group 02' THEN
			CASE   
				WHEN pIII.Decile IN ('0','1','2','3','4','5','6','7') THEN '05 - Control (50% lvl)'
				WHEN pIII.Decile IN ('8','9','A','B') THEN '06 - 2.5% Up (25% lvl)'
				WHEN pIII.Decile IN ('C','D','E','F') THEN '07 - 5.0% Up (25% lvl)'
				END
		WHEN pIII.ScoreGroup = 'Group 03' THEN '08 - Control'
		WHEN pIII.ScoreGroup = 'Group 04' THEN
			CASE
				WHEN pIII.Decile IN ('0','1','2','3','4','5','6','7') THEN '09 - Control (50% lvl)'
				WHEN pIII.Decile IN ('8','9','A','B','C','D','E','F') THEN '10 - 25% Down (50% lvl)'
				END
		WHEN pIII.ScoreGroup = 'Group 05' THEN
			CASE   
				WHEN pIII.Decile IN ('0','1','2','3','4','5','6','7') THEN '11 - Control (50% lvl)'
				WHEN pIII.Decile IN ('8','9','A','B','C','D','E','F') THEN '12 - 50% Down (50% lvl)'
				END
		END
	,pIII.SignupDt
    ,sal.LogDateTime
INTO #allRCViewers
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #phaseIIIpop pIII ON sal.UserID = pIII.UserID 
	AND pIII.SID = sal.SID
JOIN #HounouredRC c2 ON c2.UserID = sal.UserID and sal.LogDateTime = c2.logdatetime
WHERE sa.AssetKey = 'RateCard'
AND (sa.Details.value('(//PriceTargetingPromoId)[1]', 'nvarchar(max)') <> '1167' OR sa.Details.value('(//PriceTargetingPromoId)[1]', 'nvarchar(max)') IS NULL)
create index idx_#allRCViewers1 on #allRCViewers(UserID)
create index idx_#allRCViewers2 on #allRCViewers(UserID, SID)


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
AND sal.LogDateTime >= '2014-05-05 12:30:00'
AND sal.LogDateTime < '2014-05-19 12:00:00'
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
WHERE t.CreateDt >= '2014-05-05 12:30:00'
AND t.CreateDt < '2014-05-19 12:00:00'
AND t.luTrxTypeID In (1,8,12) -- New, BDC, Gift
AND t.luTrxStatusID = 1   -- SUCCESS
AND t.luTrxCategoryID IN (1,4)  -- SALES and Gift Transfer
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
	AND c.CreateDt >= '2014-05-05 12:30:00'
	AND c.CreateDt < '2014-05-19 12:00:00'
GROUP BY ScoreGroup, UserGroup
ORDER BY ScoreGroup, UserGroup

DELETE FROM WorkDB.dbo.MK_PriceTest3_Phase2;
INSERT INTO WorkDB.dbo.MK_PriceTest3_Phase2 (ScoreGroup,Cohort,RCViewers,PmntViewers,Subs,RC_Pmnt,Pmnt_Sub,RC_Sub,TotalCash,ARPU,Resignations,ResignRate)
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

DROP TABLE #phaseIIpop
DROP TABLE #phaseIIIpop
DROP TABLE #honoured
DROP TABLE #HounouredRC
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
FROM WorkDB.dbo.MK_PriceTest3_Phase2 
WHERE ScoreGroup = 'Group 01'

SELECT 
	[Score Group] = ScoreGroup
	,[Cohort]
	,[RC Viewers] = CASE WHEN [Cohort] <> '05 - Control (50% lvl)' THEN RCViewers * 2 ELSE RCViewers END
	,[Pmnt Viewers] = CASE WHEN [Cohort] <> '05 - Control (50% lvl)' THEN PmntViewers * 2 ELSE PmntViewers END
	,[Subs] = CASE WHEN [Cohort] <> '05 - Control (50% lvl)' THEN Subs * 2 ELSE Subs END
	,[RC to Pmnt %] = RC_Pmnt
	,[Pmnt to Sub %] = Pmnt_Sub
	,[RC to Sub %] = RC_Sub
	,[Total Cash] = CASE WHEN [Cohort] <> '05 - Control (50% lvl)' THEN TotalCash * 2 ELSE TotalCash END
	,[ARPU]
	,[Resignations] = CASE WHEN [Cohort] <> '05 - Control (50% lvl)' THEN [Resignations] * 2 ELSE [Resignations] END
	,[Resign %] = ResignRate
FROM WorkDB.dbo.MK_PriceTest3_Phase2 
WHERE ScoreGroup = 'Group 02'

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
FROM WorkDB.dbo.MK_PriceTest3_Phase2 
WHERE ScoreGroup = 'Group 03'

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
FROM WorkDB.dbo.MK_PriceTest3_Phase2 
WHERE ScoreGroup = 'Group 04'

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
FROM WorkDB.dbo.MK_PriceTest3_Phase2 
WHERE ScoreGroup = 'Group 05'

--TRUNCATE TABLE WorkDB.dbo.MK_PriceTest3_Phase2;
--DROP TABLE WorkDB.dbo.MK_PriceTest3_Phase2;
--CREATE TABLE WorkDB.dbo.MK_PriceTest3_Phase2 (
--	ScoreGroup VARCHAR(MAX)
--	,Cohort VARCHAR(MAX)
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