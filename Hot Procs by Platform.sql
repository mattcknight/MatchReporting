SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#Objects') IS NOT NULL 
	DROP TABLE #Objects;

WITH cteDailyTotals(TraceDate, Category, ObjectName, [Platform], Executions, ExecutionsPerSecond)
AS (
    SELECT
		CAST(t.TraceStartDate AS DATE) AS TraceDate
		,t.Category
		,t.ObjectName
		,[Platform] = CASE 
			WHEN Right(HostName,3) in ('141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157') THEN 'Mobile'
			WHEN Right(HostName,3) in ('211','212','213','214') THEN 'G3' 
			ELSE 'Match8' END
		,Executions = SUM(t.SumExecutions)
		,ExecutionsPerSecond = ROUND((SUM(t.SumExecutions)*1.0)/300,2)
	FROM [TraceData].[dbo].[PowerView] t WITH (NOLOCK)
	WHERE t.TraceStartDate >= DATEADD(DAY, -3, CAST(GETDATE() AS DATE))
	AND t.ObjectName NOT LIKE 'Repl%'
	AND t.ObjectName NOT LIKE 'csa_%'
	AND t.ObjectName NOT LIKE 'sp_%'
	GROUP BY
		CAST(t.TraceStartDate AS DATE)
		,t.Category
		,t.ObjectName
		,CASE 
			WHEN Right(HostName,3) in ('141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157') THEN 'Mobile'
			WHEN Right(HostName,3) in ('211','212','213','214') THEN 'G3' 
			ELSE 'Match8' END
    )
SELECT
	today.Category
    ,today.ObjectName
	,today.[Platform]
    ,today.Executions AS E
    ,AllDays.AvgExecutions_All AS E_Avg
	,EPS = CONVERT(DECIMAL(10,2),today.ExecutionsPerSecond)
	,EPS_Avg = CONVERT(DECIMAL(10,2),AllDays.AvgExecutionsPerSecond_All)
	,Factor = (today.Executions / AllDays.AvgExecutions_All)
INTO #Objects
FROM cteDailyTotals today
LEFT JOIN (
    SELECT 
		Category
		,ObjectName
		,[Platform]
        ,AvgExecutions_All = SUM(Executions) / COUNT(distinct TraceDate)
		,AvgExecutionsPerSecond_All = ROUND((SUM(Executions)*1.0)/300,2) / COUNT(distinct TraceDate)
    FROM cteDailyTotals
    WHERE TraceDate < DATEADD(DAY,-1,CAST(GETDATE() AS DATE))
    GROUP BY Category,ObjectName,[Platform]
    ) AS AllDays ON 
			today.ObjectName = AllDays.ObjectName 
		AND today.Category = AllDays.Category 
		AND today.[Platform] = AllDays.[Platform]
WHERE today.TraceDate = CAST(GETDATE() AS DATE)
AND today.Executions > 1000
AND ( isnull(AllDays.AvgExecutions_All, 0) = 0 OR abs(today.Executions - isnull(AllDays.AvgExecutions_All, 0)) / AllDays.AvgExecutions_All > .20 )
ORDER BY (today.Executions / AllDays.AvgExecutions_All) DESC


SELECT 
	CAST(t.TraceStartDate AS DATE) AS MetricDate
	,[Platform] = CASE 
		WHEN Right(HostName,3) in ('141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157') THEN 'Mobile'
		WHEN Right(HostName,3) in ('211','212','213','214') THEN 'G3' 
		ELSE 'Match8' END
	,t.ObjectName
	,SUM(t.SumExecutions) AS MetricValue
FROM [TraceData].[dbo].[PowerView] t WITH (NOLOCK)
JOIN #Objects o ON t.ObjectName = o.ObjectName 
	AND t.Category = o.Category
GROUP BY 
	CAST(t.TraceStartDate AS DATE),t.ObjectName
	,CASE 
		WHEN Right(HostName,3) in ('141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157') THEN 'Mobile'
		WHEN Right(HostName,3) in ('211','212','213','214') THEN 'G3' 
		ELSE 'Match8' END
ORDER BY 1