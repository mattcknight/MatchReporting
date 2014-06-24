SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF object_id('tempdb.dbo.#Page') IS NOT NULL DROP TABLE #Page;  
SELECT -- Raw Data
	MetricDate = CAST(PageDt AS DATE)
	,MetricHour = DATEPART(HOUR,PageDt)
	,MetricMinute = DATEPART(MINUTE,PageDt)
	,DataCenter = CASE WHEN WebServerName LIKE 'DA%' THEN 'Clearview' ELSE 'Dupont' END
	,WebServerName
	,Cnt = COUNT(1)
INTO #Page
FROM [DW].[dbo].[Page] WITH (NOLOCK)
WHERE WeekOfYear = DATEPART(WEEK,GETDATE())
AND PageDt >= DATEADD(MINUTE,-105,GETDATE())
AND PageDt < DATEADD(MINUTE,-75,GETDATE())
AND WebServerName NOT LIKE '%141'
AND WebServerName NOT LIKE '%142'
AND WebServerName NOT LIKE '%143'
AND WebServerName NOT LIKE '%144'
AND WebServerName NOT LIKE '%145'
AND WebServerName NOT LIKE '%146'
AND WebServerName NOT LIKE '%147'
AND WebServerName NOT LIKE '%148'
AND WebServerName NOT LIKE '%149'
AND WebServerName NOT LIKE '%150'
AND WebServerName NOT LIKE '%151'
AND WebServerName NOT LIKE '%152'
AND WebServerName NOT LIKE '%153'
AND WebServerName NOT LIKE '%154'
AND WebServerName NOT LIKE '%211'
AND WebServerName NOT LIKE '%212'
AND WebServerName NOT LIKE '%213'
AND WebServerName NOT LIKE '%214'
AND WebServerName NOT LIKE '%500'
AND WebServerName NOT LIKE 'DA0%'
AND WebServerName NOT LIKE '%MIWS%'
AND WebServerName NOT LIKE '%NEW'
AND WebServerName NOT LIKE 'DA3%'
AND WebServerName NOT LIKE 'EC3%'
AND WebServerName IS NOT NULL
AND WebServerName <> 'DA1MAWS057'
GROUP BY
	CAST(PageDt AS DATE)
	,DATEPART(HOUR,PageDt)
	,DATEPART(MINUTE,PageDt)
	,CASE WHEN WebServerName LIKE 'DA%' THEN 'Clearview' ELSE 'Dupont' END
	,WebServerName
ORDER BY 
	CAST(PageDt AS DATE)
	,DATEPART(HOUR,PageDt)
	,DATEPART(MINUTE,PageDt)
	,CASE WHEN WebServerName LIKE 'DA%' THEN 'Clearview' ELSE 'Dupont' END
	,WebServerName

SELECT * FROM #Page ORDER BY 1,2,3