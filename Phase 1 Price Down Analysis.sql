SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

IF OBJECT_ID('tempdb..#tmpPriceDown') IS NOT NULL DROP TABLE #tmpPriceDown
IF OBJECT_ID('tempdb..#totalsales') IS NOT NULL DROP TABLE #totalsales
IF OBJECT_ID('tempdb..#renewalSales') IS NOT NULL DROP TABLE #renewalSales
IF OBJECT_ID('tempdb..#initialsales') IS NOT NULL DROP TABLE #initialsales
IF object_id('tempdb..#resignations') IS NOT NULL DROP TABLE #resignations; 
IF OBJECT_ID('tempdb..#tmpPriceDownFinal') IS NOT NULL DROP TABLE #tmpPriceDownFinal

SELECT
	u.UserId
	,TestCohort = CASE 
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('0', '1', '2', '3') THEN 0 -- Control
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('4', '5', '6') THEN 1 -- 25% Off
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('7', '8', '9') THEN 2 -- 50% Off
		END
	,AgeGroup = CASE 
		WHEN FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) < 23 THEN 1
		WHEN FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) > 57 THEN 2
		END
	,CleanRead = CASE
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('0', '1', '2', '3') AND ao.PromoID = 'default' THEN 1
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('4', '5', '6') AND ao.PromoID = '1160' THEN 1
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('7', '8', '9') AND ao.PromoID = '1161' THEN 1
		ELSE 0
		END
	,MIN(t.statusdt) statusdt
	,MIN(t.TrxId) trxId
INTO #tmpPriceDown
FROM billingdata.dbo.acctorder ao WITH (NOLOCK)
INNER JOIN ProfileReadData.dbo.Users u WITH (NOLOCK) ON u.UserID = ao.UserID
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid 
	AND t.lutrxtypeid IN (1, 8) 
	AND t.lutrxstatusid = 1 
	AND t.lutrxcategoryid IN (1, 4)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid AND p.luProdFeatureID = 1
WHERE t.StatusDt >= '2014-01-28 14:00' -- Test Start Date
AND t.StatusDt <= '2014-02-27 14:00' -- to 1 mo of subs
AND ao.IsResub = 0 -- FTS only
AND u.LoginDisabled <> 2 -- No Fraud
AND u.sitecode = 1 -- US and CA only
AND u.GenderGenderSeek IN (1, 2, 3) -- MsW and LGBT GGS
AND (FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) < 23 OR FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) > 57) -- 18-22, 58+
AND ao.PromoID <> '592' -- No Mobile Promo
AND u.BrandID NOT IN (1026491, 1025282, 1025281, 1025279, 1026525, 1026754, 1026509) -- Exclude specific brandIDs
GROUP BY 
	u.userid
	,CASE 
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('0', '1', '2', '3') THEN 0
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('4', '5', '6') THEN 1
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('7', '8', '9') THEN 2
		END
	,CASE 
		WHEN FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) < 23 THEN 1
		WHEN FLOOR(DATEDIFF(DAY, u.Birthday, u.SignupDt) / 365) > 57 THEN 2
		END
	,CASE 
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('0', '1', '2', '3') AND ao.PromoID = 'default' THEN 1
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('4', '5', '6') AND ao.PromoID = '1160' THEN 1
		WHEN right(LEFT(u.testingguid, 4), 1) IN ('7', '8', '9') AND ao.PromoID = '1161' THEN 1
		ELSE 0
		END
	,td.DtlDays

-- Remove users who are in other discount cohorts
DELETE
FROM #tmpPriceDown
WHERE TestCohort IS NULL

CREATE CLUSTERED INDEX #ifts201301 ON #tmpPriceDown (userid)


-- Total Cash
SELECT 
	f.TestCohort
	,f.AgeGroup
	,totalcashcollected = SUM(t.PreTaxAmt)
	,cntdistinctusers = COUNT(DISTINCT f.userid)
INTO #totalsales
FROM #tmpPriceDown f
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.userid = f.userid 
	AND t.lutrxstatusid = 1
	AND t.luTrxCategoryID IN (0, 1, 2, 4) -- no auth
WHERE t.StatusDt >= f.statusdt
GROUP BY f.TestCohort, f.AgeGroup
ORDER BY f.TestCohort, f.AgeGroup


-- Renewal Cash
SELECT 
	f.TestCohort
	,f.AgeGroup
	,totalcashcollected = SUM(t.PreTaxAmt)
	,cntdistinctusers = COUNT(DISTINCT f.userid)
INTO #renewalSales
FROM #tmpPriceDown f
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.userid = f.userid 
	AND t.lutrxstatusid = 1
	AND t.luTrxCategoryID IN (0, 1, 2, 4) -- no auth
	AND t.[luTrxTypeID] = 2
WHERE t.StatusDt >= f.statusdt
GROUP BY f.TestCohort, f.AgeGroup
ORDER BY f.TestCohort, f.AgeGroup


-- Initial Cash 
SELECT 
	f.TestCohort
	,f.AgeGroup
	,InitialCashCollected = SUM(t.pretaxamt)
INTO #initialsales
FROM #tmpPriceDown f
INNER JOIN billingdata.dbo.Trx t WITH (NOLOCK) ON f.TrxId = t.TrxId AND f.UserID = t.UserID
GROUP BY f.TestCohort, f.AgeGroup


-- Resignations  
SELECT 
	f.TestCohort
	,f.AgeGroup
	,Resignations = COUNT(DISTINCT t.UserID)
INTO #resignations
FROM #tmpPriceDown f
INNER JOIN [BillingData].[dbo].[AcctDtl] t WITH (NOLOCK) ON f.UserID = t.UserID AND  t.luCancelTypeID = 1
GROUP BY f.TestCohort, f.AgeGroup


-- Get totals
SELECT 
	t.AgeGroup
	,t.TestCohort
	,t.cntdistinctusers
	,TotalCash = t.totalcashcollected
	,InitialCash = i.InitialCashCollected
	,RenewalCash = r.totalcashcollected
	,Resignations = res.Resignations
INTO #tmpPriceDownFinal
FROM #totalsales t
JOIN #initialsales i ON t.TestCohort = i.TestCohort AND t.AgeGroup = i.AgeGroup
JOIN #renewalSales r ON t.TestCohort = r.TestCohort AND t.AgeGroup = r.AgeGroup
JOIN #resignations res ON t.TestCohort = res.TestCohort AND t.AgeGroup = res.AgeGroup
ORDER BY t.AgeGroup, t.TestCohort


DECLARE @ControlCash_LT23 DECIMAL(10,2)
DECLARE @ControlDistSubs_LT23 DECIMAL(10,2)
DECLARE @ControlCash_Indx_LT23 DECIMAL(10,2)
DECLARE @ControlDistSubs_Indx_LT23 DECIMAL(10,2)

DECLARE @ControlCash_GT58 DECIMAL(10,2)
DECLARE @ControlDistSubs_GT58 DECIMAL(10,2)
DECLARE @ControlCash_Indx_GT58 DECIMAL(10,2)
DECLARE @ControlDistSubs_Indx_GT58 DECIMAL(10,2)

SELECT 
	@ControlCash_LT23 = SUM(TotalCash)
	,@ControlCash_Indx_LT23 = SUM(TotalCash*.75)
	,@ControlDistSubs_LT23 = SUM(cntdistinctusers)
	,@ControlDistSubs_Indx_LT23 = SUM(cntdistinctusers*.75)
FROM #tmpPriceDownFinal
WHERE TestCohort = 0
AND AgeGroup = 1
GROUP BY AgeGroup, TestCohort

SELECT
	@ControlCash_GT58 = SUM(TotalCash)
	,@ControlCash_Indx_GT58 = SUM(TotalCash*.75)
	,@ControlDistSubs_GT58 = SUM(cntdistinctusers)
	,@ControlDistSubs_Indx_GT58 = SUM(cntdistinctusers*.75)
FROM #tmpPriceDownFinal
WHERE TestCohort = 0
AND AgeGroup = 2
GROUP BY AgeGroup, TestCohort

-- Normalize and Summarize
SELECT
	[TestCohort]
	,[Cohort] = CASE
		WHEN TestCohort = 0 THEN 'Control'
		WHEN TestCohort = 1 THEN '25% Off'
		WHEN TestCohort = 2 THEN '50% Off'
		END
	,[Conversion]= CASE
		WHEN TestCohort <> 0 THEN CAST((((SUM(cntdistinctusers) / @ControlDistSubs_Indx_LT23) - 1)*100) AS NUMERIC(36,2))
		ELSE 0
		END
	,[Users] = SUM(cntdistinctusers)
	,[Total Cash] = SUM(TotalCash)
	,[Initial Cash] = SUM(InitialCash)
	,[Renewal Cash] = SUM(RenewalCash)
	,[Resignations] = SUM(Resignations) 
	,[Users(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(SUM(cntdistinctusers*.75) AS NUMERIC(36,0))
		ELSE CAST(SUM(cntdistinctusers) AS NUMERIC(36,0))
		END
	,[Total Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(TotalCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(TotalCash),2) AS NUMERIC(36,2))
		END
	,[Initial Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(InitialCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(InitialCash),2) AS NUMERIC(36,2))
		END
	,[Renewal Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(RenewalCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(RenewalCash),2) AS NUMERIC(36,2))
		END
	,[Resignations(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(SUM(Resignations*.75) AS NUMERIC(36,0))
		ELSE CAST(SUM(Resignations) AS NUMERIC(36,0))
		END
FROM #tmpPriceDownFinal
WHERE AgeGroup = 1
GROUP BY [TestCohort]
ORDER BY [TestCohort]


SELECT
	[TestCohort]
	,[Cohort] = CASE
		WHEN TestCohort = 0 THEN 'Control'
		WHEN TestCohort = 1 THEN '25% Off'
		WHEN TestCohort = 2 THEN '50% Off'
		END
	,[Conversion]= CASE
		WHEN TestCohort <> 0 THEN CAST((((SUM(cntdistinctusers) / @ControlDistSubs_Indx_GT58) - 1)*100) AS NUMERIC(36,2))
		ELSE 0
		END
	,[Users] = SUM(cntdistinctusers)
	,[Total Cash] = SUM(TotalCash)
	,[Initial Cash] = SUM(InitialCash)
	,[Renewal Cash] = SUM(RenewalCash)
	,[Resignations] = SUM(Resignations) 
	,[Users(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(SUM(cntdistinctusers*.75) AS NUMERIC(36,0))
		ELSE CAST(SUM(cntdistinctusers) AS NUMERIC(36,0))
		END
	,[Total Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(TotalCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(TotalCash),2) AS NUMERIC(36,2))
		END
	,[Initial Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(InitialCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(InitialCash),2) AS NUMERIC(36,2))
		END
	,[Renewal Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(RenewalCash*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(RenewalCash),2) AS NUMERIC(36,2))
		END
	,[Resignations(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(SUM(Resignations*.75) AS NUMERIC(36,0))
		ELSE CAST(SUM(Resignations) AS NUMERIC(36,0))
		END
FROM #tmpPriceDownFinal
WHERE AgeGroup = 2
GROUP BY [TestCohort]
ORDER BY [TestCohort]