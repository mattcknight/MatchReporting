SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

SELECT SUM(t.PreTaxAmt)
FROM billingdata.dbo.acctorder ao WITH (NOLOCK)
INNER JOIN billingdata.dbo.acctdtl ad WITH (NOLOCK) ON ao.acctorderid = ad.acctorderid
INNER JOIN billingdata.dbo.trxdtl td WITH (NOLOCK) ON td.acctdtlid = ad.acctdtlid
INNER JOIN billingdata.dbo.trx t WITH (NOLOCK) ON t.trxid = td.trxid AND t.lutrxtypeid = 14 AND t.lutrxstatusid = 1 AND t.lutrxcategoryid IN (1, 4)
INNER JOIN billingdata.dbo.proddtl pd WITH (NOLOCK) ON pd.proddtlid = ad.proddtlid
INNER JOIN billingdata.dbo.prod p WITH (NOLOCK) ON p.prodid = pd.prodid AND p.luProdFeatureID = 26 -- TopSpot