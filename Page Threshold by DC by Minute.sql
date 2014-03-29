SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT 
	CAST(h.LogEntryDateTime AS DATE) AS MetricDate
	,DATEPART(HOUR,h.LogEntryDateTime) AS MetricHour
	,DATEPART(MINUTE,h.LogEntryDateTime) AS MetricMinute
	,CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END AS DataCenter
	,WebServer
	,COUNT(*) AS MetricValue
FROM ReportsDevelopment.[dbo].[PageThresholdHeader] h WITH (NOLOCK)
WHERE h.LogEntryDateTime >= DATEADD(DAY,-365,GetDate())
AND h.ExecutionTime >= 5000
GROUP BY 
	CAST(h.LogEntryDateTime AS DATE)
	,DATEPART(HOUR,h.LogEntryDateTime)
	,DATEPART(MINUTE,h.LogEntryDateTime)
	,CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
	,WebServer
ORDER BY 
	CAST(h.LogEntryDateTime AS DATE)
	,DATEPART(HOUR,h.LogEntryDateTime)
	,DATEPART(MINUTE,h.LogEntryDateTime)
	,CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
	,WebServer