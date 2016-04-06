SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE
    @FloorDate DATE,
    @CeilingDate DATE = dateadd(day, 1, getdate())
SELECT @FloorDate = '2014-07-01'

IF OBJECT_ID('tempdb..#tmpRFFSales') IS NOT NULL DROP TABLE  #tmpRFFSales
SELECT 
	ad.UserID
	,ad.AcctDtlID
	,ad.BeginDt
INTO #tmpRFFSales
FROM billingdata.dbo.acctdtl ad WITH (NOLOCK)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON ad.ProdDtlID = pd.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON pd.prodid = p.prodid
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid
	AND t.lutrxstatusid = 1 
	AND t.lutrxcategoryid = 1
WHERE luprodfeatureid = 28
AND luCancelTypeID = 0
AND ad.createdt > @FloorDate

IF OBJECT_ID('tempdb..#tmpRFFPurchases') IS NOT NULL DROP TABLE  #tmpRFFPurchases
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
    ,DistinctUserCount = ISNULL(COUNT(DISTINCT rff.UserID),0)
INTO #tmpRFFPurchases
FROM cteDateDriver dd
LEFT JOIN #tmpRFFSales rff ON dd.PurchaseDate = CAST(rff.BeginDt AS DATE) 
GROUP BY dd.PurchaseDate
ORDER BY 1
OPTION (maxrecursion 2000)

SELECT *
FROM #tmpRFFPurchases

DROP TABLE #tmpRFFSales
DROP TABLE #tmpRFFPurchases


SELECT SUM(ad.SalesPrice)
FROM billingdata.dbo.acctorder ao WITH (NOLOCK)
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
	AND ad.luCancelTypeID = 0
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid
	AND t.lutrxstatusid = 1 
	AND t.lutrxcategoryid = 1
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid AND p.luProdFeatureID = 28 -- Reply For Free