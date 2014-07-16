SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME, @EndDate DATETIME
SELECT @StartDate = '2014-07-02 13:00', @EndDate = '2014-07-30 12:00'


IF object_id('tempdb.dbo.#InboxReskinUsers') IS NOT NULL DROP TABLE #InboxReskinUsers;
SELECT 
	Cohort = CASE WHEN RIGHT(LEFT(u.TestingGUID, 7), 1) IN ('0','1','2','3','4','5','6','7') THEN 'Test' ELSE 'Control' END
	,u.UserID
	,u.SignupDt
INTO #InboxReskinUsers_tmp
FROM [ProfileReadData].[dbo].[Users] u WITH (NOLOCK)
JOIN [WorkDB].[dbo].[vRegSessionInfo] r WITH (NOLOCK) ON r.UserID = u.UserID AND r.PlatformID = 0
WHERE u.SignupDt >= @StartDate
AND u.SignupDt < @EndDate
AND u.SiteCode = 1
AND u.CountryCode = 1 -- US Only


-- Ivans Fraud Rule
if object_id ('tempdb.dbo.#Fraud_Users') is not null drop table #Fraud_Users
select brc.userid 
into #Fraud_Users 
from #InboxReskinUsers_tmp rd
INNER JOIN [Match_4].[dbo].[billresigncomm] brc WITH (NOLOCK) on rd.userID = brc .UserID
WHERE brc.resigntype = 'K'
AND DATEDIFF (ss, rd.SignUpDt ,brc.resigndt) < 604800 -- 7 days
AND brc.resigncode not in (42 ,112, 1025)


if object_id('tempdb.dbo.#phase4pop') is not null drop table #phase4pop; 
select us.*
into #InboxReskinUsers
from #InboxReskinUsers_tmp us 
left join #Fraud_Users fr on fr.UserID = us.UserID
where fr.UserID IS NULL


IF object_id('tempdb.dbo.#Emailers') IS NOT NULL DROP TABLE #Emailers;
SELECT 
	u.Cohort
	,Emails_Sent = COUNT(DISTINCT l.EmailHeaderID)
	,InitialContact = COUNT(DISTINCT CASE WHEN l.IsResponse = 0 THEN l.EmailHeaderID END)
	,Conversations = COUNT(DISTINCT CASE WHEN l.IsResponse = 0 THEN l.RecipientUserID END)
INTO #Emailers
FROM #InboxReskinUsers u
INNER JOIN [WorkDB].[dbo].[vEmailHeaderSessionInfo] l WITH (NOLOCK) ON l.SenderUserID = u.UserID
	AND l.EmailAreaID = 0
	AND l.PlatformID = 0
	AND l.SendDate >= @StartDate
	AND l.SendDate < @EndDate
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
	,ConvPerSub = CAST(s.Subs AS DECIMAL(10,2)) / e.Conversations
FROM #InboxReskinUsers u
JOIN #Emailers e ON u.Cohort = e.Cohort
JOIN #Subs s on u.Cohort = s.Cohort
GROUP BY u.Cohort,e.Emails_Sent,e.InitialContact,e.Conversations, s.Subs
ORDER BY 1


DROP TABLE #InboxReskinUsers
DROP TABLE #Emailers
DROP TABLE #Subs