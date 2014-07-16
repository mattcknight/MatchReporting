SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = '2012-01-01'

IF OBJECT_ID('tempdb..#tmpIMConvo') IS NOT NULL
	DROP TABLE #tmpIMConvo

SELECT
	MetricDate
	,FromUserID
	,FromUserDisabled
	,ToUserID
	,ToUserDisabled 
	,LastStatus
INTO #tmpIMConvo
FROM
(
SELECT 
	MetricDate = CAST([AlertStatusDt] AS DATE)
	,SessionID
	,FromUserID
	,FromUserDisabled = u1.LoginDisabled
	,ToUserID
	,ToUserDisabled = u2.LoginDisabled
	,LastStatus = MAX(im.AlertStatusID)
FROM [Match_4].[dbo].[IMAlertHistory] im WITH (NOLOCK)
JOIN ProfileReadData.dbo.Users u1 ON im.FromUserID = u1.UserID
JOIN ProfileReadData.dbo.Users u2 ON im.ToUserID = u2.UserID
WHERE AlertStatusDt >= @StartDate
AND AlertStatusID <> 5
GROUP BY
	CAST([AlertStatusDt] AS DATE)
	,SessionID
	,FromUserID
	,u1.LoginDisabled
	,ToUserID
	,u2.LoginDisabled
) AS x

SELECT 
	MetricDate
	,Senders = COUNT(DISTINCT(FromUserID))
	,Recipients = COUNT(DISTINCT(ToUserID))
	,Initiated = COUNT(1)
	,Displayed = SUM(CASE WHEN LastStatus IN (1,2,3,4) THEN 1 END)
	,Accepted = SUM(CASE WHEN LastStatus IN (2,4) THEN 1 END)
	,Rejected = SUM(CASE WHEN LastStatus IN (3) THEN 1 END)
	,Senders_FA = COUNT(DISTINCT(CASE WHEN FromUserDisabled NOT IN (1,2) THEN FromUserID END))
	,Recipients_FA = COUNT(DISTINCT(CASE WHEN ToUserDisabled NOT IN (1,2) THEN ToUserID END))
	,Initiated_FA = SUM(CASE WHEN FromUserDisabled NOT IN (1,2) THEN 1 END)
	,Displayed_FA = SUM(CASE WHEN LastStatus IN (1,2,3,4) AND FromUserDisabled NOT IN (1,2) THEN 1 END)
	,Accepted_FA = SUM(CASE WHEN LastStatus IN (2,4) AND FromUserDisabled NOT IN (1,2) THEN 1 END)
	,Rejected_FA = SUM(CASE WHEN LastStatus IN (3) AND FromUserDisabled NOT IN (1,2) THEN 1 END)
FROM #tmpIMConvo
GROUP BY MetricDate
ORDER BY MetricDate

DROP TABLE #tmpIMConvo