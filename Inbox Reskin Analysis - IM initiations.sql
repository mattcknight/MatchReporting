SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME, @EndDate DATETIME
SELECT @StartDate = '2014-05-15', @EndDate = '2014-07-07 12:00'

-- Get all IMs sent between date range
IF OBJECT_ID('tempdb..#tmpIMSenders') IS NOT NULL DROP TABLE #tmpIMSenders
SELECT 
	MetricDate = CAST([AlertStatusDt] AS DATE)
	,Cohort = CASE 
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0') AND im.AlertStatusDt > '2014-06-11 14:00' AND im.AlertStatusDt < '2014-06-16 12:00' THEN 'Test'
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1','2','3') AND im.AlertStatusDt > '2014-06-16 14:00' AND im.AlertStatusDt < '2014-07-02 12:00' THEN 'Test'
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1','2','3','4','5','6','7') AND im.AlertStatusDt > '2014-07-02 14:00' THEN 'Test'
		ELSE 'Control' END
	,Sender = FromUserID
	,Decile = RIGHT(LEFT(u.TestingGUID, 7), 1)
	,FromUserDisabled = CASE WHEN u.LoginDisabled NOT IN (1,2) THEN 0 ELSE 1 END
	,RegAge = CASE 
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0') AND u.SignupDt < '2014-06-11 14:00' AND im.AlertStatusDt > '2014-06-11 14:00' AND im.AlertStatusDt < '2014-06-16 12:00' THEN 'Old'
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1','2','3') AND u.SignupDt < '2014-06-16 12:00' AND im.AlertStatusDt > '2014-06-16 14:00' AND im.AlertStatusDt < '2014-07-02 12:00' THEN 'Old'
		WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1','2','3','4','5','6','7') AND u.SignupDt < '2014-07-02 14:00' AND im.AlertStatusDt > '2014-07-02 14:00' THEN 'Old'
		ELSE 'New' END
	,Recipient = ToUserID
	,Recipient_Cohort = CASE
		WHEN RIGHT(LEFT(u2.TestingGUID, 7), 1) IN ('0') AND im.AlertStatusDt > '2014-06-11 14:00' AND im.AlertStatusDt < '2014-06-16 12:00' THEN 'Test'
		WHEN RIGHT(LEFT(u2.TestingGUID, 7), 1) IN ('0','1','2','3') AND im.AlertStatusDt > '2014-06-16 14:00' AND im.AlertStatusDt < '2014-07-02 12:00' THEN 'Test'
		WHEN RIGHT(LEFT(u2.TestingGUID, 7), 1) IN ('0','1','2','3','4','5','6','7') AND im.AlertStatusDt > '2014-07-02 14:00' THEN 'Test'
		ELSE 'Control' END
INTO #tmpIMSenders
FROM [Match_4].[dbo].[IMAlertHistory] im WITH (NOLOCK)
JOIN ProfileReadData.dbo.Users u ON im.FromUserID = u.UserID
JOIN ProfileReadData.dbo.Users u2 ON im.ToUserID = u2.UserID
WHERE im.AlertStatusID = 0
AND im.AlertStatusDt >= @StartDate
AND im.AlertStatusDt < @EndDate


-- Remove fraud, summary recipients
IF OBJECT_ID('tempdb..#Summary') IS NOT NULL DROP TABLE #Summary
SELECT
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Sender
	,Decile
	,RegAge
	,DistRecipients = COUNT(DISTINCT Recipient)
INTO #Summary
FROM #tmpIMSenders
WHERE FromUserDisabled NOT IN (1,2)
GROUP BY
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Sender
	,Decile
	,RegAge
ORDER BY
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Sender
	,Decile
	,RegAge

-- Standard Deviation and MEAN value for Cohort and Decile
IF OBJECT_ID('tempdb..#StDev') IS NOT NULL DROP TABLE #StDev
SELECT
	Cohort
	,Recipient_Cohort
	,Decile
	,stdev_DistRecipients = STDEV(DistRecipients)
	,Mean_DistRecipients = 
		(
			(SELECT MAX(DistRecipients) 
			FROM (SELECT TOP 50 PERCENT DistRecipients FROM #Summary WHERE Cohort = sp.Cohort AND Recipient_Cohort = sp.Recipient_Cohort AND Decile = sp.Decile ORDER BY DistRecipients) AS BottomHalf)
			+
			(SELECT MIN(DistRecipients) 
			FROM (SELECT TOP 50 PERCENT DistRecipients FROM #Summary WHERE Cohort = sp.Cohort AND Recipient_Cohort = sp.Recipient_Cohort AND Decile = sp.Decile ORDER BY DistRecipients DESC) AS TopHalf)
		) / 2
INTO #StDev
FROM #Summary sp
GROUP BY Cohort, Recipient_Cohort, Decile

-- Remove outlayers 1.5x the StDev
IF OBJECT_ID('tempdb..#Summary2') IS NOT NULL DROP TABLE #Summary2
SELECT
	s.MetricDate
	,s.Cohort
	,s.Recipient_Cohort
	,s.Sender
	,s.Decile
	,s.RegAge
	,s.DistRecipients
INTO #Summary2
FROM #Summary s
JOIN #StDev st ON s.Cohort = st.Cohort
	AND s.Recipient_Cohort = st.Recipient_Cohort
	AND s.Decile = st.Decile
WHERE s.DistRecipients < st.Mean_DistRecipients + (stdev_DistRecipients * 1.5)

-- Summary
SELECT
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Decile
	,RegAge
	,Senders = COUNT(Distinct Sender)
	,Recipients = SUM(DistRecipients)
FROM #Summary2
GROUP BY
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Decile
	,RegAge
ORDER BY
	MetricDate
	,Cohort
	,Recipient_Cohort
	,Decile
	,RegAge