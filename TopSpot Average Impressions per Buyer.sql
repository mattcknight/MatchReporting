SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpTSImpressions') IS NOT NULL DROP TABLE #tmpTSImpressions

SELECT 
	MetricUnit = adib.AcctDtlID
	,MetricDate_Start = CAST(adib.BeginDt AS DATE)
	,MetricDate_End = CAST(adib.EndDt AS DATE)
	,MetricValue = COUNT(1)
INTO #tmpTSImpressions
FROM BillingData.dbo.AcctDtlImpulseBuys adib WITH (NOLOCK)
LEFT JOIN Match_4.dbo.TopSpotImpressions tsi WITH (NOLOCK) On adib.UserID = tsi.ResultUserID AND tsi.ImpressionDt BETWEEN adib.BeginDt AND adib.EndDt
WHERE adib.BeginDt >= '2014-01-15'
AND adib.luProdFeatureID = 26
GROUP BY 
	adib.AcctDtlID
	,CAST(adib.BeginDt AS DATE)
	,CAST(adib.EndDt AS DATE)
ORDER BY 2

SELECT MetricDate_Start, COUNT(MetricUnit) AS Buyers, SUM(MetricValue) AS TotalImpressions,  SUM(MetricValue) / COUNT(MetricUnit) AS AvgImpressionsBuyer
FROM #tmpTSImpressions
WHERE MetricDate_Start <= dateadd(day, -1, CAST(getdate() AS DATE))
GROUP BY MetricDate_Start
ORDER BY 1

DROP TABLE #tmpTSImpressions