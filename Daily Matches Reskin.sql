SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpD5Subs') IS NOT NULL
	DROP TABLE  #tmpD5Subs

SELECT 				
	TestCase = CASE 
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9') AND t.statusdt >= '2014-02-27 13:00' AND t.StatusDt < '2014-03-11 13:00' THEN 'Test'
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9','A','B','C','D') AND t.statusdt >= '2014-03-11 14:00' THEN 'Test'
		ELSE 'Control' 
		END
	,Cnt = COUNT(distinct t.userid)
INTO #tmpD5Subs
FROM billingdata.dbo.trx t WITH (NOLOCK)
JOIN billingdata.dbo.trxdtl td (nolock) on t.trxid = td.trxid
JOIN billingdata.dbo.acctdtl ad (nolock) on ad.acctdtlid = td.acctdtlid
JOIN billingdata.dbo.acctorder ao (nolock) on ao.acctorderid = ad.acctorderid
JOIN billingdata.dbo.ProdDtl pd (nolock) on pd.proddtlid = ad.proddtlid
JOIN billingdata.dbo.prod p (nolock) on p.prodid = pd.prodid  and (p.luProdFeatureID = 1)
JOIN ProfileReadData.dbo.users u (nolock) on u.userid = t.UserID and u.LoginDisabled != 2
WHERE t.lutrxtypeid in (1,8,12,14)
AND t.lutrxcategoryid in (0,1,4)
AND t.lutrxstatusid in (1)
AND t.countrycode = 1
AND t.statusdt >= '2014-02-27 13:00'
GROUP BY
	CASE
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9') AND t.statusdt >= '2014-02-27 13:00' AND t.StatusDt < '2014-03-11 13:00' THEN 'Test'
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9','A','B','C','D') AND t.statusdt >= '2014-03-11 14:00' THEN 'Test'
		ELSE 'Control' 
		END

SELECT 
	Control = SUM(CASE WHEN TestCase = 'Control' THEN Cnt END)
	,Control_indx = SUM(CASE WHEN TestCase = 'Control' THEN CONVERT(DECIMAL(10,0),Cnt * .33333,0) END)
	,Test = SUM(CASE WHEN TestCase = 'Test' THEN Cnt END)
FROM #tmpD5Subs

DROP TABLE #tmpD5Subs

---------


SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#tmpD5Raters') IS NOT NULL
	DROP TABLE  #tmpD5Raters

SELECT 
	d5.UserID
	,TestCase = CASE
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9') AND d5.DateMatched >= '2014-02-27 13:00' AND d5.DateMatched < '2014-03-11 13:00' THEN 'Test'
		WHEN RIGHT(LEFT(u.testingGuid, 29),1) IN ('5','6','8','9','A','B','C','D') AND d5.DateMatched >= '2014-03-11 14:00' THEN 'Test'
		ELSE 'Control' 
		END
	,d5.PickedCode
INTO #tmpD5Raters
FROM [SearchData].[dbo].[d5Match] d5 WITH (NOLOCK)
JOIN [ProfileReadData].[dbo].[Users] u WITH (NOLOCK) ON d5.UserID = u.UserID
WHERE d5.DateMatched >= '2014-02-27 13:00'

IF OBJECT_ID('tempdb..#tmpD5Reskin') IS NOT NULL
	DROP TABLE  #tmpD5Reskin

SELECT 
	u.TestCase
	,u.PickedCode
	,Cnt = COUNT(1)
INTO #tmpD5Reskin
FROM #tmpD5Raters u
GROUP BY 
	u.TestCase
	,u.PickedCode
ORDER BY 1,2

SELECT 
	PickedCode
	,Control = SUM(CASE WHEN TestCase = 'Control' THEN Cnt END)
	,Control_indx = SUM(CASE WHEN TestCase = 'Control' THEN CONVERT(DECIMAL(10,0),Cnt * .33333,0) END)
	,Test = SUM(CASE WHEN TestCase = 'Test' THEN Cnt END)
FROM #tmpD5Reskin
GROUP BY 
	PickedCode

DROP TABLE #tmpD5Raters
DROP TABLE #tmpD5Reskin