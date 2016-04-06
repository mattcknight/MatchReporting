SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT 
	MetricDate = CAST(psc.CreateDt AS DATE)
	,u.GenderGenderSeek
	,GGS = CASE 
		WHEN u.GenderGenderSeek = 1 THEN 'Gay Men'
		WHEN u.GenderGenderSeek = 2 THEN 'Men'
		WHEN u.GenderGenderSeek = 3 THEN 'Gay Women'
		WHEN u.GenderGenderSeek = 4 THEN 'Women'
		END
	,MetricValue = COUNT(*)
from [ProfileReadData].[dbo].[proSelfCommunity] psc with (nolock)
inner join profilereaddata.dbo.users u with (nolock) on psc.userid = u.userid
where psc.cfgCommunityID = 35 -- Mensa
group by 
	CAST(psc.CreateDt AS DATE)
	,u.GenderGenderSeek
	,CASE 
		WHEN u.GenderGenderSeek = 1 THEN 'Gay Men'
		WHEN u.GenderGenderSeek = 2 THEN 'Men'
		WHEN u.GenderGenderSeek = 3 THEN 'Gay Women'
		WHEN u.GenderGenderSeek = 4 THEN 'Women'
		END
order by 1,2



select 
	MetricDate = CAST(psc.CreateDt AS DATE)
	,GGS = CASE 
		WHEN u.GenderGenderSeek = 1 THEN 'Men'
		WHEN u.GenderGenderSeek = 2 THEN 'Men'
		WHEN u.GenderGenderSeek = 3 THEN 'Women'
		WHEN u.GenderGenderSeek = 4 THEN 'Women'
		END
	,MetricValue = COUNT(*)
from [ProfileReadData].[dbo].[proSelfCommunity] psc with (nolock)
inner join profilereaddata.dbo.users u with (nolock) on psc.userid = u.userid
where psc.cfgCommunityID <> 35 -- Not Mensa (MLB)
AND u.LoginDisabled NOT IN (1,2)
and psc.CreateDt >= '2014-02-18'
AND psc.CreateDt < CAST(GETDATE() AS DATE)
group by 
	CAST(psc.CreateDt AS DATE)
	,CASE 
		WHEN u.GenderGenderSeek = 1 THEN 'Men'
		WHEN u.GenderGenderSeek = 2 THEN 'Men'
		WHEN u.GenderGenderSeek = 3 THEN 'Women'
		WHEN u.GenderGenderSeek = 4 THEN 'Women'
		END
order by 1,2