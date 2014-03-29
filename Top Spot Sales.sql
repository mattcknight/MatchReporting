SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpTopSpotPurchases') IS NOT NULL
	DROP TABLE  #tmpTopSpotPurchases
 
DECLARE
    @FloorDate DATE,
    @CeilingDate DATE = dateadd(day, 1, getdate())
 
SELECT @FloorDate = '2014-01-15'-- MIN(BeginDt)
FROM BillingData.dbo.AcctDtlTopSpot
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
    ,PurchaseCount = COUNT(adib.AcctDtlID)
    ,DistinctUserCount = COUNT(DISTINCT adib.UserID)
    ,NewUserCount = ISNULL(newusers.NewUserCount,0)
	,AvgPurchaseRateToday = CONVERT(DECIMAL(10,3),1.00*COUNT(adib.AcctDtlID) / NULLIF(COUNT(DISTINCT adib.UserID),0))
	,AvgPurchaseRate = CONVERT(DECIMAL(10,3),1.00*COUNT(adib.AcctDtlID) / NULLIF(ISNULL(newusers.NewUserCount,0),0))
INTO #tmpTopSpotPurchases
FROM cteDateDriver dd
LEFT JOIN BillingData.[dbo].[AcctDtlImpulseBuys] adib On dd.PurchaseDate = cast(adib.BeginDt AS DATE) AND adib.luProdFeatureID = 26
LEFT JOIN (
	SELECT minBeginDt, NewUserCount = count(UserID)
	FROM (
		SELECT UserID, minBeginDt = MIN(CAST(BeginDt AS DATE))
		FROM BillingData.dbo.AcctDtlTopSpot
		GROUP BY UserID
		) x
	GROUP BY minBeginDt
	) newusers ON dd.PurchaseDate = newusers.minBeginDt
GROUP BY dd.PurchaseDate, ISNULL(newusers.NewUserCount,0)
ORDER BY 1
OPTION (maxrecursion 2000)

SELECT *
FROM #tmpTopSpotPurchases
WHERE PurchaseDate <= dateadd(day, -1, CAST(getdate() AS DATE))