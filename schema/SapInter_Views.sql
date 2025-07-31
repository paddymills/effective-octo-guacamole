USE SNInterDev;
GO

CREATE OR ALTER VIEW sap.InterCfgState
AS
	SELECT
		CAST(REPLACE(DB_NAME(), 'SNInter', '') AS VARCHAR(3)) AS Environment,
		CONCAT('v', Major, '.', Minor, '.', Patch) AS Version,
		SimTransDistrict,
		LogProcedureCalls
	FROM sap.InterfaceConfig, sap.InterfaceVersion;
GO

CREATE OR ALTER VIEW sap.MatlCompatTable AS
	-- Recusively builds mapping of parent to child
	--       (table)       ->        (view)
	-- +--------+-------+      +--------+-------+
	-- | Parent | Child |      | Parent | Child |
	-- +--------+-------+      +--------+-------+
	-- |   a    |   b   |  ->  |   a    |   b   |
	-- |   b    |   c   |      |   a    |   c   |
	-- +--------+-------+      |   b    |   c   |
	--                         +--------+-------+
	
	WITH
		WithM270Map AS (
			SELECT
				ParentMatl,
				ChildMatl,
				UseIntermediateCompat,
				1 AS UseRecursion
			FROM sap.MatlCompatMap
			UNION
			SELECT
				ChildMatl,
				ParentMatl,
				UseIntermediateCompat,
				0 AS UseRecursion
			FROM sap.MatlCompatMap
			WHERE IsBidirectional = 1
		),
		ExpandedCompat AS (
			SELECT
				ParentMatl,
				ChildMatl,
				UseRecursion
			FROM WithM270Map
			-- so that we can keep intermediate grades from exporting
			WHERE UseIntermediateCompat = 1
			UNION ALL
			SELECT
				BaseCompat.ParentMatl,
				RecursiveCompat.ChildMatl,
				BaseCompat.UseRecursion
			FROM WithM270Map AS BaseCompat
			INNER JOIN ExpandedCompat AS RecursiveCompat
				ON BaseCompat.ChildMatl = RecursiveCompat.ParentMatl
			WHERE BaseCompat.ParentMatl != RecursiveCompat.ChildMatl
			AND RecursiveCompat.UseRecursion = 1
		)
	SELECT DISTINCT
		ParentMatl,
		ChildMatl
	FROM ExpandedCompat;
GO

CREATE OR ALTER VIEW sap.ProgramId
AS
	-- get the ArchivePacketId per any ProgramGUID
	-- this does not assert that the program is the most recent version
	SELECT DISTINCT
		Program.ProgramGUID,
		Program.NestType,
		ChildPlate.AutoID AS ArchivePacketId,
		Program.ProgramName,
		CASE Program.NestType
			WHEN 'Slab' THEN 1
			ELSE ChildPlate.ChildNestRepeatID
		END AS RepeatId
	FROM oys.Program
	INNER JOIN oys.ChildPlate
		ON ChildPlate.ProgramGUID=Program.ProgramGUID
	WHERE ChildPlate.PlateNumber=1;	-- same ID for all slab layouts
GO
CREATE OR ALTER VIEW sap.ProgramStatus
AS
	-- get the last(and current) status of a given ProgramName
	WITH LastStatus AS (
		SELECT
			MAX(Status.AutoId) AS StatusId
		FROM oys.Status
		INNER JOIN oys.Program
			ON Program.ProgramGUID=Status.ProgramGUID
		GROUP BY Program.ProgramName
	)
	SELECT
		StatusId,
		Status.ProgramGUID,
		SigmanestStatus,
		ProgramName
	FROM LastStatus
	INNER JOIN oys.Status
		ON Status.AutoId=LastStatus.StatusId
	INNER JOIN oys.Program
		ON Program.ProgramGUID=Status.ProgramGUID;
GO

CREATE OR ALTER VIEW sap.ChildNestId
AS
	SELECT 
		ProgramId.ProgramGUID,
		ProgramId.ArchivePacketId,
		ChildPlate.ChildPlateGUID,
		ChildPlate.PlateNumber AS SheetIndex,
		ChildPlate.ChildNestProgramName AS ProgramName,
		ChildPlate.ChildNestRepeatID AS RepeatId
	FROM oys.ChildPlate
	INNER JOIN sap.ProgramId
		ON ProgramId.ProgramGUID=ChildPlate.ProgramGUID
		AND ProgramId.RepeatId=ChildPlate.ChildNestRepeatID;
GO

CREATE OR ALTER VIEW sap.CodeDeliveryList
AS
	SELECT
		StatusId AS Id,
		Program.ProgramName,
		Program.MachineName,
		ParentPart.SNPartName AS ParentPart,
		ParentPart.QtyProgram,
		Job,
		Shipment
	FROM sap.ProgramStatus
	INNER JOIN oys.Program
		ON Program.ProgramGUID=ProgramStatus.ProgramGUID
	INNER JOIN oys.ParentPart
		ON ParentPart.ProgramGUID=ProgramStatus.ProgramGUID
	LEFT JOIN oys.ChildPlate
		ON ChildPlate.ProgramGUID=ProgramStatus.ProgramGUID
	INNER JOIN oys.ChildPart
		ON ChildPart.ChildPlateGUID=ChildPlate.ChildPlateGUID;
GO
CREATE OR ALTER VIEW sap.PartsOnProgram
AS
	SELECT
		ProgramName,
		SigmanestStatus AS ProgramStatus,
		SNPartName AS PartName
	FROM sap.ProgramStatus
	INNER JOIN oys.ChildPlate
		ON ChildPlate.ProgramGUID=ProgramStatus.ProgramGUID
	INNER JOIN oys.ChildPart
		ON ChildPart.ChildPlateGUID=ChildPlate.ChildPlateGUID;
GO

CREATE OR ALTER VIEW sap.ActivePrograms
AS
	WITH ActiveGUID AS (
		SELECT ProgramGUID FROM oys.Status
		EXCEPT
		SELECT ProgramGUID FROM oys.Status
		WHERE SigmanestStatus IN ('Updated', 'Deleted') 
	)
	SELECT
		ProgramId.ArchivePacketId,
		Program.DBEntryDateTime AS PostDateTime,
		Program.ProgramGUID,
		Program.ProgramName,
		Program.MachineName,
		Program.TaskName,
		Program.WSName,
		Program.NestType,

		Status.SigmanestStatus,
		Status.SAPStatus,
		Status.Source,
		Status.UserName
	FROM ActiveGUID
	INNER JOIN oys.Program
		ON Program.ProgramGUID=ActiveGUID.ProgramGUID
	INNER JOIN sap.ProgramId
		ON ProgramId.ProgramGUID=Program.ProgramGUID
	INNER JOIN sap.ProgramStatus
		ON ProgramStatus.ProgramGUID=Program.ProgramGUID
	INNER JOIN oys.Status
		ON Status.AutoId=ProgramStatus.StatusId;
GO

CREATE OR ALTER VIEW sap.RenamedDemandAllocationInProcess
AS
	WITH WorkOrderParts AS (
		SELECT
			WONumber,
			PartName,
			QtyInProcess,
			QtyCompleted
		FROM SNDBaseDev.dbo.PartWithQtyInProcess
	)
	SELECT
		Id,
		OriginalPartName,
		NewPartName,
		WorkOrderName,
		Qty - QtyInProcess - QtyCompleted AS QtyRemaining
	FROM sap.RenamedDemandAllocation AS Alloc
	LEFT JOIN WorkOrderParts
		ON  WorkOrderParts.WONumber=Alloc.WorkOrderName
		AND WorkOrderParts.PartName=Alloc.NewPartName;
GO

CREATE OR ALTER VIEW cds.JobShipments
AS
	SELECT DISTINCT
		CONCAT(Job, '-', Shipment) AS JobShipment,
		Job,
		Shipment
	FROM oys.ChildPart;
GO