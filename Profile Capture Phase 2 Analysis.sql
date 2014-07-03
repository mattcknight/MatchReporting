SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = '2014-06-30 13:30'

-- All users who registered on Site Code 1, PlatformID 0 in the US after the test start date
IF object_id('tempdb.dbo.#tmpProfileCapture') IS NOT NULL DROP TABLE #tmpProfileCapture;
SELECT
	u.UserID
	,u.SignupDt
	,rs.[SID]
	,Cohort = CASE 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('A','8') THEN 'v1'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('B','9') THEN 'v2'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('C','E') THEN 'v3'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('D','F') THEN 'v4'
		ELSE 'Control' 
		END
INTO #tmpProfileCapture
FROM ProfileReadData.dbo.Users u WITH (NOLOCK)
JOIN WorkDB.dbo.vRegSessionInfo rs ON u.UserID = rs.UserID 
	AND rs.PlatformID = 0
WHERE u.signupdt >= @StartDate
	AND u.countrycode = 1 -- US only
	AND u.sitecode = 1 -- US and CA only


-- Find Fraud Users
if object_id ('tempdb.dbo.#Fraud_Users') is not null drop table #Fraud_Users
select brc.userid 
into #Fraud_Users 
from #tmpProfileCapture rd
INNER JOIN [Match_4].[dbo].[BillResignComm] brc WITH (NOLOCK) on rd.userID = brc .UserID
WHERE brc.resigntype = 'K'
AND DATEDIFF (ss, rd.SignupDt ,brc.resigndt) < 604800 -- 7 days
AND brc.resigncode not in (42 ,112, 1025)


-- Remove Fraud Users from pool
if object_id('tempdb.dbo.#ProfileCapture') is not null drop table #ProfileCapture; 
select us.*
into #ProfileCapture
from #tmpProfileCapture us 
left join #Fraud_Users fr on fr.UserID = us.UserID
where fr.UserID IS NULL


IF object_id('tempdb.dbo.#Summary') IS NOT NULL DROP TABLE #Summary;
SELECT
	Cohort
	,Users = COUNT(DISTINCT u.UserID)
	,ProfileCreate = COUNT(DISTINCT ps.UserID)
	,ProfileSubmit = COUNT(DISTINCT CASE WHEN pss.firstsubmitdt IS NOT NULL THEN pss.UserID END)
	,ProfileApproved = COUNT(DISTINCT CASE WHEN pss.firstapproveddt IS NOT NULL THEN pss.UserID END)
	,PhotoApproved = COUNT(DISTINCT CASE WHEN ps.firstapproveddt IS NOT NULL THEN pp.UserID END)
	,Subs = COUNT(DISTINCT CASE WHEN p.prodid IS NOT NULL THEN t.UserID END)
INTO #Summary
FROM #ProfileCapture u
LEFT JOIN [WorkDB].[dbo].[vProfileSubmitSessionInfo] pss ON u.UserID = pss.UserID 
	AND pss.PlatformID = 0
	AND pss.[SID] = u.[SID]
LEFT JOIN [ProfileReadData].[dbo].[proSelf] ps WITH (NOLOCK) ON ps.userid = u.userid 
	AND ps.CreateDt < DATEADD(MINUTE,90,u.SignupDt)
LEFT JOIN [ProfileReadData].[dbo].[proPhoto] pp WITH (NOLOCK) ON pp.userid = u.userid		
	AND ps.PhotoID = pp.PhotoID 
	AND pp.UploadDt <= DATEADD(MINUTE,60,pss.FirstSubmitDt) 
	AND ps.photoid > 0
LEFT JOIN [BillingData].[dbo].[AcctOrder] ao WITH (NOLOCK) ON ao.UserID = u.UserID
LEFT JOIN [BillingData].[dbo].[AcctDtl] ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
LEFT JOIN [BillingData].[dbo].[TrxDtl] td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
LEFT JOIN [BillingData].[dbo].[Trx] t WITH (NOLOCK) ON t.trxid = td.trxid 
	AND t.lutrxtypeid IN (1, 8) -- Sale
	AND t.lutrxstatusid = 1 -- Success
	AND t.lutrxcategoryid IN (1, 4)
LEFT JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
LEFT JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid 
	AND p.luProdFeatureID = 1 -- Base Feature
GROUP BY Cohort


-- Rate Card Views
IF object_id('tempdb.dbo.#RateCardViews') IS NOT NULL DROP TABLE #RateCardViews; 
SELECT
	Cohort
	,Viewers = COUNT(DISTINCT p.UserID)
INTO #RateCardViews
FROM [Match_4].[dbo].[SiteAssetLog] sal WITH (NOLOCK)
JOIN [Match_4].[dbo].[luSiteAsset] sa WITH (NOLOCK) ON sa.luSiteAssetID = sal.luSiteAssetID
JOIN #ProfileCapture p ON sal.UserID = p.UserID
WHERE sa.AssetKey = 'RateCard'
GROUP BY Cohort


DELETE FROM WorkDB.dbo.MK_ProfileCapturePhase2;
INSERT INTO WorkDB.dbo.MK_ProfileCapturePhase2 (Cohort,Users,ProfileCreate,ProfileSubmit,ProfileApproved,PhotoApproved,RCViewers,Subs,ProfileCreateRate,ProfileSubmitRate,ProfileApprovedRate,PhotoApprovedRate,RCViewRate,SubsPerUserRate,SubsPerRCViewerRate)
SELECT
	pc.Cohort
	,Users
	,ProfileCreate
	,ProfileSubmit
	,ProfileApproved
	,PhotoApproved
	,RC_Views = rc.Viewers
	,Subs
	,ProfileCreateRate = ISNULL(SUM(NULLIF(ProfileCreate, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,ProfileSubmitRate = ISNULL(SUM(NULLIF(ProfileSubmit, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,ProfileApprovedRate = ISNULL(SUM(NULLIF(ProfileApproved, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,PhotoApprovedRate = ISNULL(SUM(NULLIF(PhotoApproved, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,RCViewRate = ISNULL(SUM(NULLIF(rc.Viewers, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,SubsPerUserRate = ISNULL(SUM(NULLIF(Subs, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,SubsPerRCViewerRate = ISNULL(SUM(NULLIF(Subs, 0.0000)) / CAST(SUM(NULLIF(rc.Viewers, 0.0000)) AS DECIMAL(10,4)),0.0000)
FROM #Summary pc
JOIN #RateCardViews rc ON pc.Cohort = rc.Cohort
GROUP BY pc.Cohort,Users,ProfileCreate,ProfileSubmit,ProfileApproved,PhotoApproved,Subs,rc.Viewers
ORDER BY pc.Cohort

DROP TABLE #tmpProfileCapture
drop table #Fraud_Users
drop table #ProfileCapture
DROP TABLE #Summary
DROP TABLE #RateCardViews 

SELECT * FROM WorkDB.dbo.MK_ProfileCapturePhase2

--TRUNCATE TABLE WorkDB.dbo.MK_ProfileCapturePhase2;
--DROP TABLE WorkDB.dbo.MK_ProfileCapturePhase2;
--CREATE TABLE WorkDB.dbo.MK_ProfileCapturePhase2 (
--	Cohort VARCHAR(MAX)
--	,Users INT
--	,ProfileCreate INT
--	,ProfileSubmit INT
--	,ProfileApproved INT
--	,PhotoApproved INT
--	,RCViewers INT
--	,Subs INT
--	,ProfileCreateRate DECIMAL(18,4)
--	,ProfileSubmitRate DECIMAL(18,4)
--	,ProfileApprovedRate DECIMAL(18,4)
--	,PhotoApprovedRate DECIMAL(18,4)
--	,RCViewRate DECIMAL(18,4)
--	,SubsPerUserRate DECIMAL(18,4)
--	,SubsPerRCViewerRate DECIMAL(18,4)
-- );

