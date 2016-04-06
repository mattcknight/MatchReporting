SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON
 
DECLARE
    @FloorDate DATE,
    @CeilingDate DATE = dateadd(day, 1, getdate())
 
SELECT @FloorDate = '2014-07-01'


IF OBJECT_ID('tempdb..#tmpMMSales') IS NOT NULL DROP TABLE  #tmpMMSales
SELECT 
	ad.UserID
	,ad.AcctDtlID
	,ad.BeginDt
INTO #tmpMMSales
FROM billingdata.dbo.acctdtl ad WITH (NOLOCK)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON ad.ProdDtlID = pd.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON pd.prodid = p.prodid AND p.luProdFeatureID = 30
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid
	AND t.lutrxstatusid = 1 
	AND t.lutrxcategoryid = 1
WHERE luCancelTypeID = 14
AND ad.createdt > @FloorDate


IF OBJECT_ID('tempdb..#tmpMatchMePurchases') IS NOT NULL DROP TABLE  #tmpMatchMePurchases

;
WITH cteDateDriver(PurchaseDate)
AS (
	SELECT PurchaseDate = @FloorDate
	UNION ALL
	SELECT DATEADD(DAY, 1, PurchaseDate)
	FROM cteDateDriver
	WHERE PurchaseDate < dateadd(day, -1, getdate())
    )
SELECT 
	dd.PurchaseDate
    ,PurchaseCount = COUNT(adts.AcctDtlID)
    ,DistinctUserCount = COUNT(DISTINCT adts.UserID)
    ,NewUserCount = ISNULL(newusers.NewUserCount,0)
	,AvgPurchaseRateToday = CONVERT(DECIMAL(10,3),1.00*COUNT(adts.AcctDtlID) / NULLIF(COUNT(DISTINCT adts.UserID),0))
	,AvgPurchaseRate = CONVERT(DECIMAL(10,3),1.00*COUNT(adts.AcctDtlID) / NULLIF(ISNULL(newusers.NewUserCount,0),0))
INTO #tmpMatchMePurchases
FROM cteDateDriver dd
LEFT JOIN #tmpMMSales adts On dd.PurchaseDate = cast(adts.BeginDt AS DATE)
LEFT JOIN (
	SELECT minBeginDt, NewUserCount = count(UserID)
	FROM (
		SELECT UserID, minBeginDt = MIN(CAST(BeginDt AS DATE))
		FROM #tmpMMSales
		GROUP BY UserID
		) x
	GROUP BY minBeginDt
	) newusers ON dd.PurchaseDate = newusers.minBeginDt
GROUP BY dd.PurchaseDate, ISNULL(newusers.NewUserCount,0)
ORDER BY 1
OPTION (maxrecursion 2000)

SELECT *
FROM #tmpMatchMePurchases
--WHERE PurchaseDate <= dateadd(day, -1, CAST(getdate() AS DATE))



SELECT SUM(ad.SalesPrice)
FROM billingdata.dbo.acctorder ao WITH (NOLOCK)
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
	AND ad.luCancelTypeID = 14
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid
	AND t.lutrxstatusid = 1 
	AND t.lutrxcategoryid = 1
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid AND p.luProdFeatureID = 30 -- Reply For Free