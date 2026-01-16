--INSERT INTO oys.Status (
--	DBEntryDateTime,
--	ProgramGUID,
--	StatusGUID,
--	SigmanestStatus,
--	--SAPStatus,
--	Source,
--	UserName
--)
--SELECT
--	GETDATE(),
--	ProgramGUID,
--	NEWID(),
--	'Deleted',
--	--'Skipped',
--	'MSSQL',
--	'pmiller1'
--FROM oys.Status
--where AutoId in (
--4572
--);

with
	Statuses as (
		select distinct
			ProgramName,
			Program.ProgramGUID,
			case Status.SigmanestStatus
				when 'Created' then 'Posted'
				when 'Released' then 'Posted'
				else Status.SigmanestStatus
			end as Status
		from oys.Status
		inner join oys.Program
			on Program.ProgramGUID=Status.ProgramGUID
	),
	Deletes as (
		select ProgramName, COUNT(ProgramName) as DeleteCount
		from Statuses
		where Status = 'Deleted'
		group by ProgramName
	),
	Updates as (
		select ProgramName, COUNT(ProgramName) as UpdateCount
		from Statuses
		where Status = 'Updated'
		group by ProgramName
	),
	Posts as (
		select ProgramName, COUNT(ProgramName) as PostCount
		from Statuses
		where Status = 'Posted'
		group by ProgramName
	)
select distinct
	cast(Posts.ProgramName as int) as ProgramName,
	PostCount,
	isnull(DeleteCount, 0) as DeleteCount,
	isnull(UpdateCount, 0) as UpdateCount
from Posts
left join Deletes
	on Deletes.ProgramName=Posts.ProgramName
left join Updates
	on Updates.ProgramName=Posts.ProgramName
where PostCount-isnull(DeleteCount,0) > 1
and PostCount-isnull(DeleteCount,0)-isnull(UpdateCount,0) > 0
order by ProgramName;


with
	Statuses as (
		select distinct
			ProgramName,
			Program.ProgramGUID,
			case Status.SigmanestStatus
				when 'Created' then 'Posted'
				when 'Released' then 'Posted'
				else Status.SigmanestStatus
			end as Status
		from oys.Status
		inner join oys.Program
			on Program.ProgramGUID=Status.ProgramGUID
	),
	Deletes as (
		select ProgramName, COUNT(ProgramName) as DeleteCount
		from Statuses
		where Status = 'Deleted'
		group by ProgramName
	),
	Updates as (
		select ProgramName, COUNT(ProgramName) as UpdateCount
		from Statuses
		where Status = 'Updated'
		group by ProgramName
	),
	Posts as (
		select ProgramName, COUNT(ProgramName) as PostCount
		from Statuses
		where Status = 'Posted'
		group by ProgramName
	)
select
	Status.AutoId,
	Status.DBEntryDateTime,
	Status.ProgramGUID,
	SigmanestStatus,
	SAPStatus,
	Source,
	UserName,
	ProgramName,
	NestType,
	LayoutNumber,
	TaskName,
	WSName
from oys.Status
inner join oys.Program
	on Program.ProgramGUID=Status.ProgramGUID
where ProgramName in (
	select distinct Posts.ProgramName
	from Posts
	left join Deletes
		on Deletes.ProgramName=Posts.ProgramName
	left join Updates
		on Updates.ProgramName=Posts.ProgramName
	where PostCount-isnull(DeleteCount,0) > 1
	and PostCount-isnull(DeleteCount,0)-isnull(UpdateCount,0) > 0
)
--order by cast(ProgramName as int), status.DBEntryDateTime;\

order by status.DBEntryDateTime;