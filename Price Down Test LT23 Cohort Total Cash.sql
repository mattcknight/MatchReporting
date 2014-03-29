SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

IF OBJECT_ID('tempdb..#tmpPriceDown') IS NOT NULL DROP TABLE #tmpPriceDown
IF OBJECT_ID('tempdb..#totalsales') IS NOT NULL DROP TABLE #totalsales
IF OBJECT_ID('tempdb..#initialsales') IS NOT NULL DROP TABLE #initialsales
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
	,DaysSinceReg = FLOOR(DATEDIFF(DAY, u.SignupDt, t.CreateDt) / 365)
	,u.GenderGenderSeek
	,Package = CASE 
		WHEN td.DtlDays <= 30 THEN 1
		WHEN td.DtlDays > 30 AND td.DtlDays <= 100 THEN 3
		WHEN td.DtlDays > 100 AND td.DtlDays <= 200 THEN 6
		WHEN td.DtlDays > 200 THEN 12
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
INNER JOIN ProfileReadData.dbo.Users u WITH (NOLOCK) ON u.UserID = ao.UserID AND u.sitecode = 1
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid AND t.lutrxtypeid IN (1, 8) AND t.lutrxstatusid = 1 AND t.lutrxcategoryid IN (1, 4)
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
	,FLOOR(DATEDIFF(DAY, u.SignupDt, t.CreateDt) / 365)
	,u.GenderGenderSeek
	,CASE 
		WHEN td.DtlDays <= 30 THEN 1
		WHEN td.DtlDays > 30 AND td.DtlDays <= 100 THEN 3
		WHEN td.DtlDays > 100 AND td.DtlDays <= 200 THEN 6
		WHEN td.DtlDays > 200 THEN 12
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

-- Collect all cash
SELECT 
	f.TestCohort
	,f.AgeGroup
	,totalcashcollected = SUM(t.PreTaxAmt)
	,cntdistinctusers = COUNT(DISTINCT f.userid)
INTO #totalsales
FROM #tmpPriceDown f
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.lutrxstatusid = 1 AND t.userid = f.userid AND t.luTrxCategoryID IN (0, 1, 2, 4) -- no auth
WHERE t.StatusDt >= f.statusdt
GROUP BY f.TestCohort, f.AgeGroup
ORDER BY f.TestCohort, f.AgeGroup

-- Collect initial cash 
SELECT 
	f.TestCohort
	,f.AgeGroup
	,InitialCashCollected = SUM(t.pretaxamt)
INTO #initialsales
FROM #tmpPriceDown f
INNER JOIN billingdata.dbo.Trx t WITH (NOLOCK) ON f.TrxId = t.TrxId AND f.UserID = t.UserID
GROUP BY f.TestCohort, f.AgeGroup

-- Get totals
SELECT 
	t1.AgeGroup
	,t1.TestCohort
	,t1.totalcashcollected
	,t1.cntdistinctusers
INTO #tmpPriceDownFinal
FROM #totalsales t1
JOIN #initialsales t2 ON t1.TestCohort = t2.TestCohort AND t1.AgeGroup = t2.AgeGroup
ORDER BY t1.AgeGroup, t1.TestCohort


DECLARE @ControlCash_LT23 DECIMAL(10,2)
DECLARE @ControlDistSubs_LT23 DECIMAL(10,2)
DECLARE @ControlCash_Indx_LT23 DECIMAL(10,2)
DECLARE @ControlDistSubs_Indx_LT23 DECIMAL(10,2)

DECLARE @ControlCash_GT58 DECIMAL(10,2)
DECLARE @ControlDistSubs_GT58 DECIMAL(10,2)
DECLARE @ControlCash_Indx_GT58 DECIMAL(10,2)
DECLARE @ControlDistSubs_Indx_GT58 DECIMAL(10,2)

SELECT 
	@ControlCash_LT23 = SUM(totalcashcollected)
	,@ControlCash_Indx_LT23 = SUM(totalcashcollected*.75)
	,@ControlDistSubs_LT23 = SUM(cntdistinctusers)
	,@ControlDistSubs_Indx_LT23 = SUM(cntdistinctusers*.75)
FROM #tmpPriceDownFinal
WHERE TestCohort = 0
AND AgeGroup = 1
GROUP BY AgeGroup, TestCohort

SELECT
	@ControlCash_GT58 = SUM(totalcashcollected)
	,@ControlCash_Indx_GT58 = SUM(totalcashcollected*.75)
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
	,[Cash(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(ROUND(SUM(totalcashcollected*.75),2) AS NUMERIC(36,2))
		ELSE CAST(ROUND(SUM(totalcashcollected),2) AS NUMERIC(36,2))
		END
	,[Users(Indx)] = CASE
		WHEN TestCohort = 0 THEN CAST(SUM(cntdistinctusers*.75) AS NUMERIC(36,0))
		ELSE CAST(SUM(cntdistinctusers) AS NUMERIC(36,0))
		END
	,[Conversion]= CASE
		WHEN TestCohort <> 0 THEN CAST((((SUM(cntdistinctusers) / @ControlDistSubs_Indx_LT23) - 1)*100) AS NUMERIC(36,2))
		ELSE 0
		END
	,[Cash] = CASE
		WHEN TestCohort <> 0 THEN CAST((((SUM(totalcashcollected) / @ControlCash_Indx_LT23) - 1)*100) AS NUMERIC(36,2))
		ELSE 0
		END
FROM #tmpPriceDownFinal
WHERE AgeGroup = 1
GROUP BY [TestCohort]
ORDER BY [TestCohort]