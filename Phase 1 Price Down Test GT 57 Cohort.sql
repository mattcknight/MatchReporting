SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpPriceDown') IS NOT NULL DROP TABLE #tmpPriceDown

SELECT 
	[UserGroup]
	,[RCViews]
	,[subs]
	,[totalCash] = CASE 
		WHEN UserGroup = '0 - Control' THEN CONVERT(DECIMAL(10,2),1.5 * totalCash)
		ELSE totalCash END
INTO #tmpPriceDown
FROM  ReportsDev.dbo.mv_pricedown_o58gen123

SELECT 
	[UserGroup]
	,[eliglibleUsers] = SUM([RCViews])
	,[subs] = SUM([subs])
	,[totalCash] = SUM(totalCash)
	,[Conversion] = CONVERT(DECIMAL(10,2),100.00*SUM([subs])/SUM([RCViews]))
FROM #tmpPriceDown
GROUP BY [UserGroup]
ORDER BY 1

DROP TABLE #tmpPriceDown