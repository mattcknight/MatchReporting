SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

IF OBJECT_ID('tempdb..#tmpTopSpotPriceTest') IS NOT NULL DROP TABLE #tmpTopSpotPriceTest

SELECT
	u.UserId
	,TestCohort = CASE 
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1') THEN '$1.99 for 15 Mins' -- $1.99 for 15 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('2','3') THEN '$1.99 for 30 Mins' -- $1.99 for 30 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('4','5') THEN '$2.99 for 30 Mins' -- $2.99 for 30 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('6','7') THEN '$2.99 for 60 Mins' -- $2.99 for 60 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('8','9') THEN '$3.00 for 30 Mins' -- $3.00 for 30 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('A','B') THEN '$3.00 for 60 Mins' -- $3.00 for 30 Mins - AKA Control
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('C','D') THEN '$3.99 for 60 Mins' -- $3.99 for 60 Mins
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('E','F') THEN '$4.99 for 60 Mins' -- $4.99 for 60 Mins
		END
	,t.PreTaxAmt
	,t.TrxID
	,t.lutrxtypeid
	,t.lutrxcategoryid
	,PurchaseDate = CAST(t.CreateDt AS DATE)
INTO #tmpTopSpotPriceTest
FROM billingdata.dbo.acctorder ao WITH (NOLOCK)
INNER JOIN ProfileReadData.dbo.Users u WITH (NOLOCK) ON u.UserID = ao.UserID
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid AND t.lutrxtypeid = 14 AND t.lutrxstatusid = 1 AND t.lutrxcategoryid IN (1, 4)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid AND p.luProdFeatureID = 26 -- TopSpot
WHERE t.StatusDt >= '2014-03-01' -- Test Start Date
--AND t.StatusDt < CAST(GETDATE() AS DATE)
AND u.LoginDisabled <> 2 -- No Fraud
AND u.sitecode = 1 -- US and CA only


SELECT 
	PurchaseDate
	,TestCohort
	,Users = COUNT(DISTINCT UserID)
	,TotalRevenue = SUM(PreTaxAmt)
	,ARPU = SUM(PreTaxAmt) / COUNT(DISTINCT UserID)
FROM #tmpTopSpotPriceTest
GROUP BY PurchaseDate, TestCohort
ORDER BY 1,2

DROP TABLE #tmpTopSpotPriceTest