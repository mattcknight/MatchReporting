SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpTopSpotPurchases') IS NOT NULL
	DROP TABLE  #tmpTopSpotPurchases
 
DECLARE
    @FloorDate DATE,
    @CeilingDate DATE = dateadd(day, 1, getdate())
 
SELECT @FloorDate = '2014-01-15'-- MIN(BeginDt)
FROM BillingData.dbo.ImpulseFeatureLog WHERE luProdFeatureID = 26
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
INTO #tmpTopSpotPurchases
FROM cteDateDriver dd
LEFT JOIN BillingData.dbo.ImpulseFeatureLog adts On dd.PurchaseDate = cast(adts.BeginDt AS DATE) 
	AND adts.luProdFeatureID = 26 
	AND adts.IsComplimentary = 0 
	AND adts.SuppressFromUser = 0
LEFT JOIN (
	SELECT minBeginDt, NewUserCount = count(UserID)
	FROM (
		SELECT UserID, minBeginDt = MIN(CAST(BeginDt AS DATE))
		FROM BillingData.dbo.ImpulseFeatureLog
		WHERE luProdFeatureID = 26
		AND IsComplimentary = 0 
		AND SuppressFromUser = 0
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