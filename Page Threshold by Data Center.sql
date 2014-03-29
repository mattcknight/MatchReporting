SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT 
	MetricDate = CAST(h.LogEntryDateTime AS DATE)
	,MetricHour = DATEPART(HOUR,h.LogEntryDateTime)
	,DataCenter = CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
	,MetricValue = COUNT(*)
FROM ReportsDevelopment.[dbo].[PageThresholdHeader] h WITH (NOLOCK)	
WHERE LogEntryDateTime >= DATEADD(HOUR, -24, GETDATE())
AND h.ExecutionTime >= 5000
GROUP BY 
	CAST(h.LogEntryDateTime AS DATE)
	,DATEPART(HOUR,h.LogEntryDateTime)
	,CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
ORDER BY 
	CAST(h.LogEntryDateTime AS DATE)
	,DATEPART(HOUR,h.LogEntryDateTime)
	,CASE WHEN LEFT(h.WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END