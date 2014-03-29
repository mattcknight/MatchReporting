SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpPriceUp') IS NOT NULL DROP TABLE #tmpPriceUp

SELECT 
	[UserGroup]
	,[RCViews]
	,[subs]
	,[totalCash]
	,[resignations]
INTO #tmpPriceUp
FROM Reportsdev.dbo.mv_priceup_newregs_all

SELECT 
	[UserGroup]
	,[RCViews] = SUM([RCViews])
	,[subs] = SUM([subs])
	,[totalCash] = SUM(totalCash)
	,[Conversion] = CONVERT(DECIMAL(10,2),100.00*SUM([subs])/SUM([RCViews]))
	,[ResignRate] = CONVERT(DECIMAL(10,2),100.00*SUM([resignations])/SUM([subs]))
FROM #tmpPriceUp
GROUP BY [UserGroup]
ORDER BY 1

DROP TABLE #tmpPriceUp