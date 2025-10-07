
-- columns used (in addition to TransType, District, and TransID)
-- SN60 (add matl): Material, ItemData1, Param1
-- SN81/82 (reduce/delete): OrderNo, ItemName, Qty, ItemData18
-- SN81(add demand): OrderNo, ItemName, OnHold, Qty, Material, Customer, DwgNumber, Remark, ItemData{1-6, 9, 10, 16-18}
-- SN92(reduce inventory): ItemName
-- SN91A/97(add inventory): ItemName, Qty, Material, Thickness, Width, Length, PrimeCode, BinNumber, ItemData{1-4}, FileName
-- SN76 (program update): ProgramName, ProgramRepeat

-- get ids to move (so we can define our filter once)
create table #temp (id int);
insert into #temp(id)
	select AutoInc
	from SNDBaseDev.dbo.TransAct
	where District < 99
	--where TransID like '[1-4]-%'
;

delete from HIISQLSERV5.SNDBasePrd.dbo.TransAct
where District in (3,4) and ErrorTag=1;


-- copy items to move
insert into HIISQLSERV5.SNDBasePrd.dbo.TransAct (
	TransType,
	District,
	TransID,

	OrderNo,
	ItemName,
	OnHold,
	Qty,
	Material,
	Customer,
	DwgNumber,
	Thickness,
	Width,
	Length,
	FileName,
	PrimeCode,
	BinNumber,
	Remark,
	ItemData1,
	ItemData2,
	ItemData3,
	ItemData4,
	ItemData5,
	ItemData6,
	ItemData7,
	ItemData8,
	ItemData9,
	ItemData10,
	ItemData11,
	ItemData12,
	ItemData13,
	ItemData14,
	ItemData15,
	ItemData16,
	ItemData17,
	ItemData18,
	ProgramName,
	ProgramRepeat
)
select
	TransType,
	District,
	TransID,

	OrderNo,
	ItemName,
	OnHold,
	Qty,
	Material,
	Customer,
	DwgNumber,
	Thickness,
	Width,
	Length,
	FileName,
	PrimeCode,
	BinNumber,
	Remark,
	ItemData1,
	ItemData2,
	ItemData3,
	ItemData4,
	ItemData5,
	ItemData6,
	ItemData7,
	ItemData8,
	ItemData9,
	ItemData10,
	ItemData11,
	ItemData12,
	ItemData13,
	ItemData14,
	ItemData15,
	ItemData16,
	ItemData17,
	ItemData18,
	ProgramName,
	ProgramRepeat
from SNDBaseDev.dbo.TransAct
where AutoInc in (select id from #temp);

-- delete sent
delete from SNDBaseDev.dbo.TransAct
where AutoInc in (select id from #temp);

drop table #temp;

update HIISQLSERV5.SNDBasePrd.dbo.TransAct set ErrorTag=0;

-- show results
select * from HIISQLSERV5.SNDBasePrd.dbo.TransAct;
--select * from SNDBaseDev.dbo.TransAct;

