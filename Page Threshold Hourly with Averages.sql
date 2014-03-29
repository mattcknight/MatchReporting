SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON
 
SELECT
	t1.LogEntryDate
	,t1.HourOfDay
	,CASE WHEN t1.DC = 1 THEN 'ClearView' ELSE 'DuPont' END AS DataCenter
	,t2.Page
	,t1.CntExecutions AS Cnt
	,ISNULL(PrevHr_CntExecutions, 0) AS PrevHourCnt
	,ISNULL(NWoW_CntExecutions, 0) AS FourWeekAvgCnt
	,ISNULL(Yesterday_CntExecutions, 0) AS YesterdayCnt
FROM ReportsDevelopment.dbo.PageThresholdHeaderHourlySummary t1 WITH (NOLOCK)
JOIN ReportsDevelopment.dbo.PageThresholdPage t2 WITH (NOLOCK) ON t2.PageId = t1.PageId
WHERE t1.LogEntryDate = CAST(DATEADD(HOUR, -1, GETDATE()) AS DATE)
AND t1.HourOfDay = DATEPART(HOUR,DATEADD(HOUR, -1, GETDATE()) )
AND
(    
      (
            -- absolute value of 1K for new pages
            ISNULL(NWoW_CntExecutions, 0) = 0
            AND ISNULL(Yesterday_CntExecutions, 0) = 0
            AND ISNULL(PrevHr_CntExecutions, 0) = 0
            AND CntExecutions > 1000
      )
      OR
      (
            -- deviation from 4 week average
            ISNULL(NWoW_CntExecutions, 0) > 0
            AND CntExecutions > 2 * NWoW_CntExecutions
      )
      OR
      (
            -- deviation from previous hour
            ISNULL(NWoW_CntExecutions, 0) = 0
            AND ISNULL(PrevHr_CntExecutions, 0) > 0
            AND CntExecutions > 2 * PrevHr_CntExecutions
      )
      OR
      (
            -- deviation from yesterday average
            ISNULL(NWoW_CntExecutions, 0) = 0
            AND ISNULL(PrevHr_CntExecutions, 0) = 0
            AND ISNULL(Yesterday_CntExecutions, 0) > 0
            AND CntExecutions > 2 * Yesterday_CntExecutions    
      )
      OR
      (
            -- catch all
            CntExecutions > 3000
      )
)
AND CntExecutions > 300  -- This is to filter out any noise