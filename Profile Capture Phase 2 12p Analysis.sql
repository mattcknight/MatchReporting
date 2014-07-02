SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

DECLARE @StartDate DATETIME
SELECT @StartDate = '2014-06-30 12:45'

-- Profile completeness per user
IF object_id('tempdb.dbo.#tmpProfileCapture') IS NOT NULL DROP TABLE #tmpProfileCapture;
SELECT
	Cohort = CASE 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('A','8') THEN 'v1'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('B','9') THEN 'v2'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('C','E') THEN 'v3'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('D','F') THEN 'v4'
		ELSE 'Control' 
		END
	,Users = COUNT(DISTINCT u.UserID)
	,ProfileCreate = COUNT(DISTINCT ps.UserID)
	,ProfileSubmit = COUNT(DISTINCT CASE WHEN pss.firstsubmitdt IS NOT NULL THEN pss.UserID END)
	,ProfileApproved = COUNT(DISTINCT CASE WHEN pss.firstapproveddt IS NOT NULL THEN pss.UserID END)
	,PhotoApproved = COUNT(DISTINCT CASE WHEN ps.firstapproveddt IS NOT NULL THEN pp.UserID END)
	,Subs = COUNT(DISTINCT CASE WHEN p.prodid IS NOT NULL THEN t.UserID END)
INTO #tmpProfileCapture
FROM ProfileReadData.dbo.Users u WITH (NOLOCK)
JOIN WorkDB.dbo.vRegSessionInfo rs ON u.UserID = rs.UserID 
	AND rs.PlatformID = 0
LEFT JOIN WorkDB.dbo.vProfileSubmitSessionInfo pss ON u.UserID = pss.UserID 
	AND pss.PlatformID = 0
	AND pss.SID = rs.SID
LEFT JOIN profilereaddata.dbo.proself ps WITH (NOLOCK) ON ps.userid = u.userid 
	AND ps.CreateDt < DATEADD(MINUTE,90,u.SignupDt)
LEFT JOIN profilereaddata.dbo.proPhoto pp WITH (NOLOCK) ON pp.userid = u.userid		
	AND ps.PhotoID = pp.PhotoID 
	AND pp.UploadDt <= DATEADD(MINUTE,60,pss.FirstSubmitDt) 
	AND ps.photoid > 0
LEFT JOIN billingdata.dbo.acctorder ao WITH (NOLOCK) ON ao.UserID = u.UserID
LEFT JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
LEFT JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
LEFT JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid 
	AND t.lutrxtypeid IN (1, 8) -- Sale
	AND t.lutrxstatusid = 1 -- Success
	AND t.lutrxcategoryid IN (1, 4)
LEFT JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
LEFT JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid 
	AND p.luProdFeatureID = 1 -- Base Feature
WHERE u.signupdt >= @StartDate
	AND u.countrycode = 1 -- US only
	AND u.sitecode = 1 -- US and CA only
	AND u.logindisabled NOT IN (1, 2) -- No Fraud
GROUP BY
	CASE
		WHEN right(left(u.TestingGuid, 11), 1) IN ('A','8') THEN 'v1'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('B','9') THEN 'v2'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('C','E') THEN 'v3'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('D','F') THEN 'v4' 
		ELSE 'Control' 
		END



DELETE FROM WorkDB.dbo.MK_ProfileCapturePhase2;
INSERT INTO WorkDB.dbo.MK_ProfileCapturePhase2 (Cohort,Users,ProfileCreate,ProfileSubmit,ProfileApproved,PhotoApproved,Subs,ProfileCreateRate,ProfileSubmitRate,ProfileApprovedRate,PhotoApprovedRate,SubsPerUserRate)
SELECT
	Cohort
	,Users
	,ProfileCreate
	,ProfileSubmit
	,ProfileApproved
	,PhotoApproved
	,Subs
	,ProfileCreateRate = ISNULL(SUM(NULLIF(ProfileCreate, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,ProfileSubmitRate = ISNULL(SUM(NULLIF(ProfileSubmit, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,ProfileApprovedRate = ISNULL(SUM(NULLIF(ProfileApproved, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,PhotoApprovedRate = ISNULL(SUM(NULLIF(PhotoApproved, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
	,SubsPerUserRate = ISNULL(SUM(NULLIF(Subs, 0.0000)) / CAST(SUM(NULLIF(Users, 0.0000)) AS DECIMAL(10,4)),0.0000)
FROM #tmpProfileCapture
GROUP BY Cohort,Users,ProfileCreate,ProfileSubmit,ProfileApproved,PhotoApproved,Subs
ORDER BY Cohort

SELECT * FROM WorkDB.dbo.MK_ProfileCapturePhase2

DROP TABLE #tmpProfileCapture

--TRUNCATE TABLE WorkDB.dbo.MK_ProfileCapturePhase2;
--DROP TABLE WorkDB.dbo.MK_ProfileCapturePhase2;
--CREATE TABLE WorkDB.dbo.MK_ProfileCapturePhase2 (
--	Cohort VARCHAR(MAX)
--	,Users INT
--	,ProfileCreate INT
--	,ProfileSubmit INT
--	,ProfileApproved INT
--	,PhotoApproved INT
--	,Subs INT
--	,ProfileCreateRate DECIMAL(10,4)
--	,ProfileSubmitRate DECIMAL(10,4)
--	,ProfileApprovedRate DECIMAL(10,4)
--	,PhotoApprovedRate DECIMAL(10,4)
--	,SubsPerUserRate DECIMAL(10,4)
-- );