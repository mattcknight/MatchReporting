SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT
	pl.LogDay
	,SearchMode = CASE WHEN (len(pl.HostName2) > 0) THEN 'AppFabric' ELSE 'Other' END
	,NumSearches = COUNT(1)
	,ZeroSearches = SUM(CASE WHEN (pl.[Rows] = 0) THEN 1 ELSE 0 END)
FROM ProcLog.dbo.ProcLogMrSIX pl WITH (NOLOCK)
JOIN DW_Session_2014_27.dbo.SessionFact27 s WITH (NOLOCK) ON pl.SID = s.SID 
	AND s.ClientIP1 != '10'
WHERE pl.LogDay >= CAST( '2014-07-01' AS DATE)
AND pl.SearcherUserID = 0
AND pl.ProcName='SearchUberv9'
AND pl.Searchname='OneWay'
AND pl.SpotlightOnly = 0
AND LEN(IsNull(pl.SeekString,'')) = 0
AND LEN(IsNull(pl.SelfString,'')) = 0 
AND LEN(IsNull(pl.WeightString,'')) = 0
AND pl.SID IS NOT NULL
AND pl.SearchGeoTypeID = 4
GROUP BY pl.LogDay, CASE WHEN (len(pl.HostName2) > 0) THEN 'AppFabric' ELSE 'Other' END
ORDER BY pl.LogDay, CASE WHEN (len(pl.HostName2) > 0) THEN 'AppFabric' ELSE 'Other' END