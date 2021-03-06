﻿SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

-- Profile completeness per user
IF object_id('tempdb.dbo.#tmpProfileCapture') IS NOT NULL DROP TABLE #tmpProfileCapture;
SELECT
	Cohort = CASE 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('F', '2') THEN 'v1' 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('4', '3') THEN 'v2' 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('0', 'E') THEN 'v3' 
		ELSE 'Control' 
		END
	,Users = COUNT(DISTINCT u.UserID)
	,ProfileCreate = COUNT(DISTINCT ps.UserID)
	,ProfileSubmit = COUNT(DISTINCT CASE WHEN ps.firstsubmitdt IS NOT NULL THEN ps.UserID END)
	,ProfileApproved = COUNT(DISTINCT CASE WHEN ps.firstapproveddt IS NOT NULL THEN ps.UserID END)
	,PhotoApproved = COUNT(DISTINCT CASE WHEN ps.photoid > 0 AND ps.firstapproveddt IS NOT NULL THEN ps.UserID END)
	,Subs = COUNT(DISTINCT CASE WHEN p.prodid IS NOT NULL THEN t.UserID END)
INTO #tmpProfileCapture
FROM ProfileReadData.dbo.Users u WITH (NOLOCK)
LEFT JOIN profilereaddata.dbo.proself ps WITH (NOLOCK) ON ps.userid = u.userid
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
WHERE u.signupdt >= cast('2014-05-19 14:00:00.000' AS DATETIME) -- Prop Date/Time
	AND u.signupdt < cast('2014-05-29 12:30:00.000' AS DATETIME)
	AND u.countrycode = 1 -- US only
	AND u.sitecode = 1 -- US and CA only
	AND u.logindisabled NOT IN (1, 2) -- No Fraud
GROUP BY
	CASE
		WHEN right(left(u.TestingGuid, 11), 1) IN ('F', '2') THEN 'v1' 
		WHEN right(left(u.TestingGuid, 11), 1) IN ('4', '3') THEN 'v2'
		WHEN right(left(u.TestingGuid, 11), 1) IN ('0', 'E') THEN 'v3' 
		ELSE 'Control' 
		END

SELECT
	Cohort
	,Users
	,ProfileCreate
	,ProfileSubmit
	,ProfileApproved
	,PhotoApproved
	,Subs
	,ProfileCreateRate = ISNULL(SUM(NULLIF(ProfileCreate, 0.00)) / CAST(SUM(NULLIF(Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,ProfileSubmitRate = ISNULL(SUM(NULLIF(ProfileSubmit, 0.00)) / CAST(SUM(NULLIF(Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,ProfileApprovedRate = ISNULL(SUM(NULLIF(ProfileApproved, 0.00)) / CAST(SUM(NULLIF(Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,PhotoApprovedRate = ISNULL(SUM(NULLIF(PhotoApproved, 0.00)) / CAST(SUM(NULLIF(Users, 0.00)) AS DECIMAL(10,2)),0.00)
	,SubsPerUserRate = ISNULL(SUM(NULLIF(Subs, 0.00)) / CAST(SUM(NULLIF(Users, 0.00)) AS DECIMAL(10,2)),0.00)
FROM #tmpProfileCapture
GROUP BY Cohort,Users,ProfileCreate,ProfileSubmit,ProfileApproved,PhotoApproved,Subs
ORDER BY Cohort