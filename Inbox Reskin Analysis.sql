SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = CAST('2014-06-11 14:00:00.000' AS DATETIME)


IF object_id('tempdb.dbo.#InboxReskinUsers') IS NOT NULL DROP TABLE #InboxReskinUsers;
SELECT 
	Cohort = CASE WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0') THEN 'Test' ELSE 'Control' END
	,u.UserID
INTO #InboxReskinUsers
FROM [ProfileReadData].[dbo].[Users] u WITH (NOLOCK)
WHERE u.SignupDt >= @StartDate
AND u.SiteCode = 1
AND u.CountryCode = 1 -- US Only
AND u.LoginDisabled NOT IN (1, 2) -- No Fraud


IF object_id('tempdb.dbo.#Emailers') IS NOT NULL DROP TABLE #Emailers;
SELECT 
	u.Cohort
	,Emails_Sent = COUNT(DISTINCT l.EmailHeaderID)
	,InitialContact = COUNT(DISTINCT CASE WHEN l.IsResponse = 0 THEN l.EmailHeaderID END)
	,Conversations = COUNT(DISTINCT CASE WHEN l.IsResponse = 0 THEN l.RecipientUserID END)
INTO #Emailers
FROM #InboxReskinUsers u
INNER JOIN [Match_UserData].[dbo].[EmailHeaderLight] l WITH (NOLOCK) ON l.SenderUserID = u.UserID 
	AND l.SendDate >= @StartDate
GROUP BY u.Cohort
ORDER BY u.Cohort


IF object_id('tempdb.dbo.#Subs') IS NOT NULL DROP TABLE #Subs;
SELECT 
	u.Cohort
	,Subs = COUNT(DISTINCT u.UserID)
INTO #Subs
FROM #InboxReskinUsers u
INNER JOIN billingdata.[dbo].[trx] t WITH (NOLOCK) ON t.UserID = u.UserID
	AND t.StatusDt >= @StartDate
	AND t.luTrxTypeID In (1,8,12) -- New, BDC, Gift
	AND t.luTrxStatusID = 1  -- SUCCESS
	AND t.luTrxCategoryID IN (1,4) -- SALES and Gift Transfer
JOIN BillingData.dbo.TrxDtl td WITH (NOLOCK) ON T.TrxID=TD.TrxID
JOIN BillingData.dbo.AcctDtl ad WITH (NOLOCK) ON TD.AcctDtlID = AD.AcctDtlID
	AND ad.BeginDt <> ad.EndDt
JOIN BillingData.dbo.Acct act WITH (NOLOCK) ON ad.UserID = act.UserID
JOIN BillingData.dbo.AcctOrder ao WITH (NOLOCK) ON ad.AcctOrderID = ao.AcctOrderID
JOIN BillingData.dbo.ProdDtl pd WITH (NOLOCK) ON AD.ProdDtlID = PD.ProdDtlID
JOIN BillingData.dbo.ProdGrp pg WITH (NOLOCK) ON PG.ProdGrpID = PD.ProdGrpID
JOIN BillingData.dbo.Prod p WITH (NOLOCK) ON PD.ProdID = P.ProdID
JOIN BillingData.dbo.luProdFeature lpf WITH (NOLOCK) ON P.luProdFeatureID=lpf.luProdFeatureID
	AND lpf.luProdFeatureID = 1
GROUP BY u.Cohort
ORDER BY u.Cohort


SELECT
	u.Cohort
	,Users = COUNT(DISTINCT u.UserID)
	,e.Emails_Sent
	,e.InitialContact
	,e.Conversations
	,s.Subs
	,ConvRate = CAST(s.Subs AS DECIMAL(10,2)) / COUNT(DISTINCT u.UserID)
	,EmailPerSub = CAST(s.Subs AS DECIMAL(10,2)) / e.Emails_Sent
FROM #InboxReskinUsers u
JOIN #Emailers e ON u.Cohort = e.Cohort
JOIN #Subs s on u.Cohort = s.Cohort
GROUP BY u.Cohort,e.Emails_Sent,e.InitialContact,e.Conversations, s.Subs
ORDER BY 1


DROP TABLE #InboxReskinUsers
DROP TABLE #Emailers
DROP TABLE #Subs