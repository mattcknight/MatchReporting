SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

IF object_id('tempdb.dbo.#tmpTransactions') IS NOT NULL DROP TABLE #tmpTransactions
SELECT 
	t.UserID
	,u.LoginDisabled
	,t.TrxID
	,DateKey = cast(t.CreateDt AS DATE)
	,t.luTrxStatusID
	,PaymentAmountKey = floor(t.PreTaxAmt)
	,CardType = apmt.Descr
INTO #tmpTransactions
FROM BillingData.dbo.Trx t
INNER JOIN ProfileReadData.dbo.Users u ON t.UserID = u.UserID
	AND u.SiteCode = 1
INNER JOIN [BillingData].[dbo].[AcctPymtMeth] apm WITH (NOLOCK) ON t.[AcctPymtMethID] = apm.[AcctPymtMethID]
INNER JOIN [BillingData].[dbo].[luAcctPymtMethType] apmt ON apm.[luAcctPymtMethTypeID] = apmt.luAcctPymtMethTypeID
WHERE t.luTrxCategoryID = 1 -- Sale
	AND t.luTrxTypeID = 1 -- Renewal = 2, New Sale = 1
	AND t.CreateDt >= DATEADD(YEAR, -3, GETDATE())
ORDER BY t.TrxID
CREATE CLUSTERED INDEX CX_tmpTransactions ON #tmpTransactions (TrxID)

-- Include Joins To Identify Package
IF object_id('tempdb.dbo.#tmpTransactions2') IS NOT NULL DROP TABLE #tmpTransactions2
SELECT 
	t.UserID
	,t.LoginDisabled
	,t.TrxID
	,t.DateKey
	,t.luTrxStatusID
	,PackageMonthKey = pd.Months
	,RenewalDaysKey = td.DtlDays
	,t.PaymentAmountKey
	,t.CardType
	,st.SubType
	,st.SourceCodeDescr
	,ao.IsResub
INTO #tmpTransactions2
FROM #tmpTransactions t
INNER JOIN BillingData.dbo.TrxDtl td ON t.TrxID = td.TrxID
INNER JOIN BillingData.dbo.AcctDtl ad ON td.AcctDtlID = ad.AcctDtlID
INNER JOIN BillingData.dbo.AcctOrder ao ON ad.AcctOrderID = ao.AcctOrderID
INNER JOIN BillingData.dbo.ProdDtl pd ON ad.ProdDtlID = pd.ProdDtlID
INNER JOIN BillingData.dbo.Prod p ON pd.ProdID = p.ProdID
	AND p.luProdFeatureID = 1 -- Base Feature
LEFT JOIN FinanceReports.dbo.rt_tbl_stage_Transactions st ON t.TrxID = st.TrxID
ORDER BY t.TrxID
CREATE CLUSTERED INDEX CX_Transactions ON #tmpTransactions2 (TrxID)


SELECT 
	DateKey
	,IsResub
	,PackageMonthKey
	,CardType
	,LoginDisabled = CASE WHEN LoginDisabled = 0 THEN 0 ELSE 1 END
	,Cnt_Total = SUM(CASE WHEN luTrxStatusID IN (1,2) THEN 1 ELSE 0 END)
	,Cnt_Failed = SUM(CASE WHEN luTrxStatusID = 2 THEN 1 ELSE 0 END)
FROM #tmpTransactions2
GROUP BY 
	DateKey
	,IsResub
	,PackageMonthKey
	,CardType
	,CASE WHEN LoginDisabled = 0 THEN 0 ELSE 1 END
ORDER BY 
	DateKey
	,IsResub
	,PackageMonthKey
	,CardType
	,CASE WHEN LoginDisabled = 0 THEN 0 ELSE 1 END