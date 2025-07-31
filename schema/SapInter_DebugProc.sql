
USE SNInterDev;
GO

CREATE OR ALTER PROCEDURE sap.DebugDemand
AS
BEGIN
	-- Queries:
	-- - log
	-- - Queue
	-- - SimTrans
	-- - Part
	-- - Demand Allocation

	DECLARE @start DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME) + '00:00:00';

	SELECT * FROM (SELECT NULL AS Log) AS _, log.SapDemandCalls WHERE LogDate > @start;

	SELECT * FROM (SELECT NULL AS Queue) AS _, sap.DemandQueue;

	SELECT
		NULL AS SimTrans,
		AutoInc,
		TransType,
		District,
		TransID,
		OrderNo AS WorkOrder,
		ItemName AS PartName,
		OnHold,		-- part is available for nesting
		Qty,
		Material,	-- {spec}-{grade}{test}
		Customer,	-- State(occurrence)
		DwgNumber,	-- Drawing name
		Remark,		-- autoprocess instruction
		ItemData1 AS Job,	-- Job(project)
		ItemData2 AS Shipment,	-- Shipment
		ItemData3 AS RawMaterialMaster,
		ItemData4 AS Operation1,
		ItemData5 AS Operation2,
		ItemData6 AS Operation3,
		ItemData9 AS Mark,	-- part name (Material Master with job removed)
		ItemData10 AS HeatSwapKeyword,
		ItemData16 AS PartHoursOrder,
		ItemData17 AS SapPartName,
		ItemData18 AS SapEventId,
		AddedDate
	FROM SNDBaseDev.dbo.TransAct
	WHERE TransType LIKE 'SN8%';

	--SELECT *
	--FROM (SELECT NULL AS Part) AS _, SNDBaseDev.dbo.Part
	--WHERE PartName IN (
	--	SELECT ItemName FROM SNDBaseDev.dbo.TransAct
	--	UNION
	--	SELECT PartName FROM sap.DemandQueue
	--	UNION
	--	SELECT part_name FROM log.SapDemandCalls WHERE LogDate > @start
	--)
	--OR Data17 in (
	--	SELECT ItemData17 FROM SNDBaseDev.dbo.TransAct
	--	UNION
	--	SELECT SapPartName FROM sap.DemandQueue
	--	UNION
	--	SELECT sap_part_name FROM log.SapDemandCalls WHERE LogDate > @start
	--)

	SELECT * FROM (SELECT NULL AS RenamedAlloc) AS _, sap.RenamedDemandAllocation;

END;
GO


CREATE OR ALTER PROCEDURE sap.DebugInventory
AS
BEGIN
	-- Queries:
	-- - log
	-- - Queue
	-- - SimTrans
	-- - Stock
	-- - StockCompatibility

	DECLARE @start DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME) + '00:00:00';

	SELECT * FROM (SELECT NULL AS Log) AS _, log.SapInventoryCalls WHERE LogDate > @start;

	SELECT * FROM (SELECT NULL AS Queue) AS _, sap.InventoryQueue;

	SELECT
		NULL AS SimTrans,
		TransType,
		District,
		TransID,	-- for logging purposes
		ItemName AS SheetName,
		Qty,
		Material,	-- {spec}-{grade}{test}
		Thickness,
		Width,
		Length,
		PrimeCode AS MaterialMaster,
		BinNumber AS SapEventId,	-- SAP event id
		ItemData1 AS Notes1,
		ItemData2 AS Notes2,
		ItemData3 AS Notes3,
		ItemData4 AS Notes4,
		FileName	-- {remnant geometry folder}\{SheetName}.dxf
	FROM SNDBaseDev.dbo.TransAct
		WHERE TransType LIKE 'SN9%'
		OR TransType LIKE 'SN6%'
	;

	SELECT
		NULL AS Stock,
		SheetName,
		Qty,
		QtyAvailable,
		Material,
		Thickness,
		Width,
		Length,
		PrimeCode AS MaterialMaster,
		SheetData1,
		SheetData2,
		SheetData3,
		SheetData4,

		SheetType,
		BinNumber AS SapEventId,
		DateCreated,
		DateCreated
	FROM SNDBaseDev.dbo.Stock
	WHERE SheetName IN (
		SELECT ItemName FROM SNDBaseDev.dbo.TransAct
		UNION
		SELECT SheetName FROM sap.InventoryQueue
		UNION
		SELECT sheet_name FROM log.SapInventoryCalls WHERE LogDate > @start
	)
	OR PrimeCode IN (
		SELECT PrimeCode FROM SNDBaseDev.dbo.TransAct
		UNION
		SELECT MaterialMaster FROM sap.InventoryQueue
		UNION
		SELECT mm FROM log.SapInventoryCalls WHERE LogDate > @start
	);

	SELECT *
	FROM (SELECT NULL AS StockCompatibility) AS _,
		SNDBaseDev.dbo.StockCompatibility
	WHERE SheetName IN (
		SELECT ItemName FROM SNDBaseDev.dbo.TransAct
		UNION
		SELECT SheetName FROM sap.InventoryQueue
		UNION
		SELECT sheet_name FROM log.SapInventoryCalls WHERE LogDate > @start
	);
END;
GO

CREATE OR ALTER PROCEDURE sap.DebugFeedback
AS
BEGIN
	-- Queries:
	-- - log
	-- - Status/Program
	-- - Queue
	DECLARE @start DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME) + '00:00:00';

	SELECT * FROM (SELECT NULL AS Log) AS _, log.FeedbackCalls WHERE LogDate > @start;

	SELECT DISTINCT
		NULL AS Status,
		Status.AutoId AS StatusId,
		Status.DBEntryDateTime,
		Status.SigmanestStatus,
		Status.SapStatus,
		Status.ProgramGUID,
		Program.AutoId AS ProgramId,
		ChildNestId.ArchivePacketId,
		Program.ProgramName,
		Program.NestType,
		Program.TaskName,
		Program.LayoutNumber,
		Program.MachineName,
		Program.WSName,
		Status.Source,
		Status.UserName
	FROM oys.Status
	LEFT JOIN oys.Program
		ON Program.ProgramGUID=Status.ProgramGUID
	LEFT JOIN sap.ChildNestId
		ON ChildNestId.ProgramGUID=Program.ProgramGUID
	WHERE Status.DBEntryDateTime > @start
	OR SapStatus NOT IN ('Complete', 'Skipped')
	ORDER BY Status.AutoId;

	SELECT * FROM (SELECT NULL AS Queue) AS _, sap.FeedbackQueue;
END;
GO

CREATE OR ALTER PROCEDURE sap.DebugExecution
AS
BEGIN
	-- Queries:
	-- - log
	-- - Status/Program
	-- - SimTrans

	DECLARE @start DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME) + '00:00:00';

	SELECT * FROM (SELECT NULL AS Log) AS _, log.UpdateProgramCalls WHERE LogDate > @start;

	SELECT
		NULL AS StatusAndProgram,
		Status.AutoId AS StatusId,
		Status.DBEntryDateTime,
		Status.StatusGUID,
		Status.SigmanestStatus,
		Status.SapStatus,

		Status.ProgramGUID,
		Program.AutoId AS ProgramId,
		ChildNestId.ArchivePacketId,
		Program.ProgramName,
		Program.NestType,
		Program.TaskName,
		Program.LayoutNumber,
		Program.MachineName,
		Program.CuttingTime,
		Program.WSName,
		Status.Source,
		Status.UserName
	FROM oys.Status
	LEFT JOIN oys.Program
		ON Program.ProgramGUID=Status.ProgramGUID
	LEFT JOIN sap.ChildNestId
		ON ChildNestId.ProgramGUID=Program.ProgramGUID
	WHERE Status.DBEntryDateTime > @start
	ORDER BY Status.AutoId;

	SELECT
		NULL AS SimTrans,
		AutoInc,
		TransType,
		District,
		TransID,
		ProgramName,
		ProgramRepeat
	FROM SNDBaseDev.dbo.TransAct
	WHERE TransType LIKE 'SN7%';

END;
GO
