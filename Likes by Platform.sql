SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON 

SELECT 
	MetricDate = CAST(ActivityDtm AS DATE)
	,p.MobilePlatformDesc
	,MetricValue = COUNT(*)
FROM [WorkDB].[dbo].[LikesSessionInfo] l
JOIN [Match_4].[dbo].[MobilePlatform] p ON l.PlatformId = p.MobilePlatformId
WHERE l.ActivityDtm >= CAST(DATEADD(DAY,-30,GETDATE()) AS DATE)
AND l.ActivityDtm < CAST(GETDATE() AS DATE)
AND p.MobilePlatformId IN (0,1,6,24)
GROUP BY
	CAST(l.ActivityDtm AS DATE)
	,p.MobilePlatformDesc
ORDER BY 1,2