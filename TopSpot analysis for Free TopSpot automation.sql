SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED 
SET NOCOUNT ON

SELECT 
	LapseDate = CAST(ad.EndDt AS DATE)
	,ad.UserID
INTO #LapseUsers
FROM [BillingData].[dbo].[AcctDtl] ad WITH (NOLOCK)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid 
	AND p.luProdFeatureID = 1 -- Base Feature
WHERE ad.luCancelTypeID = 1
AND ad.EndDt < '2014-07-02'
AND ad.EndDt >= '2014-06-01'

SELECT
	u.UserID
	,u.LapseDate
	,EmailRule = CASE WHEN ehl.RecipientUserID IS NOT NULL THEN 1 ELSE 0 END
INTO #LapseUsersEmail
FROM #LapseUsers u
LEFT JOIN Match_UserData.dbo.EmailHeaderLight ehl WITH (NOLOCK) ON u.UserID = ehl.RecipientUserID
	AND ehl.SendDate >= DATEADD(DAY,-7,u.LapseDate)

SELECT
	l.LapseDate
	,NoEmail = SUM(CASE WHEN l.EmailRule = 0 THEN 1 ELSE 0 END)
	,HasEmail = SUM(CASE WHEN l.EmailRule = 1 THEN 1 ELSE 0 END)
FROM #LapseUsersEmail l
GROUP BY l.LapseDate
ORDER BY l.LapseDate



SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#SearchImpressions') IS NOT NULL DROP TABLE #SearchImpressions
SELECT
	MetricDate = CAST(SearchResultImpressionDt AS DATE)
	,SearchTypeID
	,SearchResultImpressionID
	,Impressions = COUNT(DISTINCT ResultUserID)
	,TopSpot = SUM(CASE WHEN IsTopSpot = 1 THEN 1 ELSE 0 END)
INTO #SearchImpressions
FROM DW.dbo.SearchResultImpressions
WHERE CodeBaseID = 36 -- Match8 Only
GROUP BY 
	CAST(SearchResultImpressionDt AS DATE)
	,SearchTypeID
	,SearchResultImpressionID