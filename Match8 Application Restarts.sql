SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT
	MetricDate = CAST(LogEntryDateTime AS DATE)
	,MetricHour = DATEPART(HOUR,LogEntryDateTime)
	,DataCenter = CASE WHEN LEFT(WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
	,WebServer
	,MetricValue = COUNT(1)
FROM AppDebug.dbo.MessageLog WITH (NOLOCK)
WHERE MessageText = 'Match8 Application Start'
AND (WebServer LIKE 'DA1MAWS%' OR WebServer LIKE 'EC1MAWS%')
AND WebServer NOT LIKE '%211'
AND WebServer NOT LIKE '%212'
AND WebServer NOT LIKE '%213'
AND WebServer NOT LIKE '%214'
AND WebServer NOT LIKE '%500'
AND WebServer <> 'DA1MAWS057'
AND LogEntryDateTime >= CAST(DATEADD(HOUR,-24,GETDATE()) AS DATE)
AND CodebaseID = 36
GROUP BY
	CAST(LogEntryDateTime AS DATE)
	,DATEPART(HOUR,LogEntryDateTime)
	,CASE WHEN LEFT(WebServer,2) = 'DA' THEN 'ClearView' ELSE 'DuPont' END
	,WebServer
ORDER BY 1,2,3,4