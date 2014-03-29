SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @DaysBack INT
SELECT @DaysBack = -7

SELECT 
	CAST(p.PageDt AS DATE) as MetricDate, 
	pcd.Path, 
	COUNT(p.Skey) as TotalPageViews
FROM [DW].[dbo].[Page] p WITH (NOLOCK)
JOIN Match_4.dbo.PageCodesDynamic pcd WITH (NOLOCK) ON p.PageCode = pcd.PageCode
WHERE p.PageCode IN (1200012,1200453)
AND PageDt >= DATEADD(Day,@DaysBack,GetDate())
AND PageDt < CAST(GETDATE() AS DATE)
GROUP BY 
	CAST(PageDt AS DATE), 
	pcd.Path
ORDER BY 
	CAST(PageDt AS DATE) DESC, 
	pcd.Path
OPTION (MAXDOP 1)