SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT
	pt.WebServer
	,da.DataSourceAlias
	,MetricValue = COUNT(*)
FROM [ReportsDevelopment].[dbo].[PageTimeOut] pt WITH (NOLOCK)
JOIN [ReportsDevelopment].[dbo].[PageThresholdDataSourceAlias] da ON pt.TimeOutDataSourceAliasId = da.DataSourceAliasId
WHERE pt.LogEntryDateTime >= DATEADD(MINUTE,-20,GetDate())
GROUP BY 
	pt.WebServer
	,da.DataSourceAlias
HAVING COUNT(*) > 10
ORDER BY 2