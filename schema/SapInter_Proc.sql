-- Purpose: Create stored procedures for interfacing SAP with Sigmanest
USE SNInterDev;
GO

CREATE OR ALTER TRIGGER sap.PostConfigUpdate
ON sap.InterfaceConfig
AFTER UPDATE
NOT FOR REPLICATION
AS
BEGIN
	IF UPDATE(HeatSwapKeyword)
		-- update the HeatSwapKeyword for all current work orders
		-- ensures that Data14 matches the configured keyword
		UPDATE SNDBaseDev.dbo.Part
		SET Part.Data10=inserted.HeatSwapKeyword
		FROM inserted;
END;
GO

CREATE OR ALTER PROCEDURE sap.AddNewMaterials
AS
BEGIN
	-- [0] log procedure call
	INSERT INTO log.SapInventoryCalls(ProcCalled)
	SELECT 'AddNewMaterials'
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] add SN60 to SimTrans if
	--	- Material is not in Sigmanest material list
	--	- an existing SN60 does not exist in the SimTrans
	WITH
		-- Material names to add
		MatlNames AS (
			-- get materials in Queues
			SELECT DISTINCT
				Matl AS MaterialName
			FROM (
				SELECT Matl FROM sap.DemandQueue
				UNION
				SELECT Matl FROM sap.InventoryQueue
			) AS Queues

			-- exclude blank materials
			EXCEPT SELECT NULL
			EXCEPT SELECT ''

			-- exclude existing materials in Sigmanest
			EXCEPT SELECT MaterialType
				FROM SNDBaseDev.dbo.Material

			-- exclude conflicting material additions already in the SimTrans
			EXCEPT SELECT Material
				FROM SNDBaseDev.dbo.TransAct, sap.InterfaceConfig
				WHERE TransType = 'SN60'
				AND District=SimTransDistrict
		),

		-- Assume mild steel: get group name and density
		MildSteelData AS (
			SELECT TOP 1
				MatGroupName, DensityIn
			FROM SNDBaseDev.dbo.Material
			INNER JOIN SNDBaseDev.dbo.MaterialGroup
				ON Material.MatGroupID = MaterialGroup.MatGroupID
			WHERE MatGroupName = 'MS'
		)
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,
		District,
		Material,
		ItemData1,	-- material group name
		Param1		-- material density
	)
	SELECT
		'SN60',
		SimTransDistrict,
		MaterialName,
		MatGroupName,
		DensityIn
	FROM MatlNames, MildSteelData, sap.InterfaceConfig;
END;
GO


-- ********************************************
-- *    Interface 1: Demand                   *
-- ********************************************
CREATE OR ALTER PROCEDURE sap.PushSapDemand
	-- this is the procedure called by Boomi
	@sap_event_id VARCHAR(50) NULL,	-- SAP: numeric 20 positions, no decimal
	@sap_part_name VARCHAR(18),

	@work_order VARCHAR(50),
	@part_name VARCHAR(100),
	@qty INT,
	@matl VARCHAR(50),
	@process VARCHAR(64) = NULL,	-- assembly process (DTE, RA, etc.)

	@state VARCHAR(50) = NULL,
	@dwg VARCHAR(50) = NULL,
	@job VARCHAR(50) = NULL,
	@shipment VARCHAR(50) = NULL,
	@codegen VARCHAR(50) = NULL,	-- autoprocess instruction
	@op1 VARCHAR(50) = NULL,	-- secondary operation 1
	@op2 VARCHAR(50) = NULL,	-- secondary operation 2
	@op3 VARCHAR(50) = NULL,	-- secondary operation 3
	@mark VARCHAR(50) = NULL,	-- part name (Material Master with job removed)
	@raw_mm VARCHAR(50) = NULL,
	@due_date DATE = NULL
AS
SET NOCOUNT ON
BEGIN
	-- [0] log procedure call
	-- [1] pull operations from sap.PartOperations
	-- [2] Queue demand for SimTrans PreExec

	-- [0] log procedure call
	INSERT INTO log.SapDemandCalls (
		ProcCalled,
		sap_event_id,
		sap_part_name,
		work_order,
		part_name,
		qty,
		matl,
		process,
		state,
		dwg,
		codegen,
		job,
		shipment,
		op1,
		op2,
		op3,
		mark,
		raw_mm,
		due_date
	)
	SELECT
		'PushSapDemand',
		@sap_event_id,
		@sap_part_name,
		@work_order,
		@part_name,
		@qty,
		@matl,
		@process,
		@state,
		@dwg,
		@codegen,
		@job,
		@shipment,
		@op1,
		@op2,
		@op3,
		@mark,
		@raw_mm,
		@due_date
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] pull operations from sap.PartOperations
	SELECT
		@codegen = AutoProcessInstruction,
		@op1 = Operation2,
		@op2 = Operation3,
		@op3 = Operation4
	FROM sap.PartOperations
	WHERE PartName=@part_name;
		
	-- [2] Queue demand for SimTrans PreExec
	INSERT INTO sap.DemandQueue (
		SapEventId,
		SapPartName,

		WorkOrder,
		PartName,
		Qty,
		Matl,
		OnHold,

		State,
		Dwg,
		Codegen,
		Job,
		Shipment,
		Op1,
		Op2,
		Op3,
		Mark,
		RawMaterialMaster,
		DueDate
	)
	VALUES (
		@sap_event_id,
		@sap_part_name,

		@work_order,
		@part_name,
		@qty,
		@matl,
		CASE @process
			WHEN 'DTE' THEN 1
			ELSE 0
		END,

		@state,
		@dwg,
		@codegen,	-- autoprocess instruction
		@job,
		@shipment,
		@op1,	-- secondary operation 1
		@op2,	-- secondary operation 2
		@op3,	-- secondary operation 3
		@mark,	-- part name (Material Master with job removed)
		@raw_mm,
		@due_date
	);
END;
GO
CREATE OR ALTER PROCEDURE sap.SetPartOperations
	@part_name VARCHAR(50),
	@op1 VARCHAR(50) NULL,
	@op2 VARCHAR(50) NULL,
	@op3 VARCHAR(50) NULL
AS
BEGIN
	-- [0] log procedure call
	-- [1] infer AutoProcess instruction
	-- [2] remove existing records to ensure @part_name exists once
	-- [3] push operations

	-- [0] log procedure call
	INSERT INTO log.SapDemandCalls (ProcCalled, part_name, op1, op2, op3)
	SELECT 'SetPartOperations', @part_name, @op1, @op3, @op3
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] infer AutoProcess instruction
	DECLARE @instruction VARCHAR(50) = CASE
		WHEN CONCAT(@op1, '|', @op2, '|', @op3) LIKE '%End Mill%' THEN 'Mill'
		WHEN 'Drill' IN (@op1, @op2, @op3) THEN 'Drill'
		WHEN 'Punch' IN (@op1, @op2, @op3) THEN 'Punch'
		ELSE NULL
	END; 

	-- [2] remove existing records to ensure @part_name exists once
	DELETE FROM sap.PartOperations WHERE PartName = @part_name;

	-- [3] push operations
	INSERT INTO sap.PartOperations (
		PartName,
		Operation2,
		Operation3,
		Operation4,
		AutoProcessInstruction
	)
	VALUES (
		@part_name,
		@op1,
		@op2,
		@op3,
		@instruction
	);

	-- [4] Update any affected work orders
	UPDATE SNDBaseDev.dbo.Part
	SET
		Data4=@op1,
		Data5=@op2,
		Data6=@op3,
		Remark=@instruction
	WHERE PartName=@part_name;
END;
GO
CREATE OR ALTER PROCEDURE sap.PushRenamedDemand
	@event_id VARCHAR(50) NULL,
	@original_part_name VARCHAR(50),
	@new_part_name VARCHAR(50),
	@work_order VARCHAR(50),
	@qty INT
AS
BEGIN
	-- the calling program is responsible to call
	--	the Boomi process to trigger interface 1

	-- [0] log procedure call
	-- [1] update/create allocation
	-- [2] Pre-emptively populate the work order in Sigmanest

	-- [0] log procedure call
	INSERT INTO log.SapDemandCalls (
		ProcCalled,
		sap_event_id,
		sap_part_name,
		part_name,
		work_order,
		qty
	)
	SELECT
		'PushRenamedDemand',
		@event_id,
		@original_part_name,
		@new_part_name,
		@work_order,
		@qty
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] update/create allocation
	UPDATE sap.RenamedDemandAllocation
	SET Qty=Qty + @qty
	WHERE NewPartName=@new_part_name
	AND WorkOrderName=@work_order;
	IF @@ROWCOUNT = 0
	BEGIN
		INSERT INTO sap.RenamedDemandAllocation (
			OriginalPartName,
			NewPartName,
			WorkOrderName,
			Qty
		)
		VALUES (
			@original_part_name,
			@new_part_name,
			@work_order,
			@qty
		)
	END;

	-- [2] Preemptively populate the work order in Sigmanest
	-- (this will overinflate the total demand in Sigmanest,
	--	which is fixed by the Boomi call in [3])
	WITH PartData AS (
		SELECT
			REPLACE(RenamedDemandAllocation.WorkOrderName, '-onhold', '') AS WorkOrder,
			RenamedDemandAllocation.NewPartName,
			RenamedDemandAllocation.Qty,
			Part.Material,
			Part.DrawingNumber,
			Part.Remark,
			Part.Data1 AS Job,
			Part.Data2 AS Shipment,
			Part.Data3 AS RawMM,
			Part.Data4 AS Op1,
			Part.Data5 AS Op2,
			Part.Data6 AS Op3,
			Part.Data9 AS Mark,
			Part.Data17 AS SapPartName
		FROM sap.RenamedDemandAllocation
			INNER JOIN SNDBaseDev.dbo.Part
				ON Part.PartName=RenamedDemandAllocation.OriginalPartName
				AND Part.WONumber=RenamedDemandAllocation.WorkOrderName
		WHERE NewPartName=@new_part_name
		AND WorkOrderName=@work_order
	)
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,  -- `SN81B`
		District,
		OrderNo,	-- work order name
		ItemName,	-- Material Master (part name)
		Qty,
		Material,	-- {spec}-{grade}{test}
		DwgNumber,	-- Drawing name
		Remark,		-- autoprocess instruction
		ItemData1,	-- Job(project)
		ItemData2,	-- Shipment
		ItemData3,	-- Raw material master (from BOM, if exists)
		ItemData4,	-- secondary operation 1
		ItemData5,	-- secondary operation 2
		ItemData6,	-- secondary operation 3
		ItemData9,	-- part name (Material Master with job removed)
		ItemData10,	-- HeatSwap keyword
		ItemData17	-- SAP Part Name (for when PartName needs changed)
	)
	SELECT
		'SN81B',
		SimTransDistrict,
		WorkOrder,
		NewPartName,
		Qty,
		Material,
		DrawingNumber,
		Remark,
		Job,
		Shipment,
		RawMM,
		Op1,
		Op2,
		Op3,
		Mark,
		HeatSwapKeyword,
		SapPartName
	FROM PartData, sap.InterfaceConfig;
END;
GO
CREATE OR ALTER PROCEDURE sap.RemoveRenamedDemand
	@event_id VARCHAR(50) NULL,
	@id INT,
	@qty INT
AS
BEGIN
	-- the calling program is responsible to call
	--	the Boomi process to trigger interface 1

	-- [0] log procedure call
	-- [1] reduce allocation

	-- [0] log procedure call
	INSERT INTO log.SapDemandCalls (
		ProcCalled, sap_event_id, alloc_id, qty
	)
	SELECT
		'RemoveRenamedDemand', @event_id, @id, @qty
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;
	
	-- [1] reduce allocation
	UPDATE sap.RenamedDemandAllocation
	SET Qty = Qty - @qty
	WHERE Id = @id;
END;
GO
CREATE OR ALTER PROCEDURE sap.DemandPreExec
AS
BEGIN
	-- called before the SimTrans runs to
	-- [1] add material grades to Sigmanest
	-- [2] delete parts in Sigmanest but not Queue
	-- [3] delete Queue items with no work order
	-- [4] reduce by renamed demand
	-- [5] push data into the SimTrans
	-- [6] clear queue

	-- Note on SimTrans transactions used
	--	- SN81B: sets the "qty to nest"
	--	- SN82: remove the part from the work order
	-- The use of the SN81B means that if the qty is 0, the part remains in the
	--	work order with no demand.

	-- [0] log procedure call
	INSERT INTO log.SapDemandCalls(ProcCalled)
	SELECT 'DemandPreExec'
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;
	
	-- place all this in a transaction for consistency
	BEGIN TRANSACTION
		-- [1] add material grades to Sigmanest
		EXEC sap.AddNewMaterials;

		-- [2] push items not in queue for deletion
		WITH ForDeletion AS (
			SELECT WONumber, PartName
			FROM SNDBaseDev.dbo.Part
			WHERE QtyOrdered > 0
			AND Data17 IN (
				SELECT SapPartName FROM sap.DemandQueue
			)
			EXCEPT
			SELECT WorkOrder, PartName
			FROM sap.DemandQueue
		),
		IdMap AS (
			SELECT DISTINCT
				SapEventId,
				Part.PartName AS IdPartName
			FROM sap.DemandQueue
			INNER JOIN SNDBaseDev.dbo.Part
				ON Part.Data17=DemandQueue.SapPartName
		)
		INSERT INTO sap.DemandQueue(
			SapEventId,
			WorkOrder,
			PartName,
			Qty
		)
		SELECT
			SapEventId,
			WONumber,
			PartName,
			0
		FROM ForDeletion
		LEFT JOIN IdMap
			ON IdMap.IdPartName=ForDeletion.PartName;

		-- [3] delete items with no work order (Qty=0 items from SAP)
		DELETE FROM sap.DemandQueue WHERE WorkOrder IS NULL;

		-- [4] TODO: reduce by renamed demand
		UPDATE sap.DemandQueue
		SET Qty=Qty-ISNULL((
			SELECT SUM(Qty)
			FROM sap.RenamedDemandAllocation
			WHERE OriginalPartName = DemandQueue.PartName
			AND WorkOrderName = DemandQueue.WorkOrder
		), 0);
	
		-- [5] push data into the SimTrans
		WITH DemandAndAlloc AS (
			SELECT
				SapEventId,
				SapPartName,

				ISNULL(Alloc.WorkOrderName, DemandQueue.WorkOrder) AS WorkOrder,
				ISNULL(Alloc.NewPartName, DemandQueue.PartName) AS PartName,
				ISNULL(Alloc.Qty, DemandQueue.Qty) AS Qty,
				Matl,
				OnHold,

				State,
				Dwg,
				Codegen,
				CASE
					-- need to make sure Job(Data1) is in the format {Project}{Structure}
					--	for DetailBayAutoProcess OYS Plugin and to calculate the Mark later
					-- Ensure that
					--	1) Job matches the pattern [A-Z]-\d{7}
					--	2) Job and PartName share the same project
					-- logically, it is important that in
					--	CONCAT(a, REPLICATE(b, x)) and SUBSTRING(JOB, s, y) that
					--		- s == 1 + length(a)
					--		- y == length(b) * x
					WHEN JOB LIKE CONCAT('[A-Z]-', REPLICATE('[0-9]', 7))	-- [A-Z]-\d{7}
					AND  PartName LIKE CONCAT(SUBSTRING(Job, 3, 7), '[A-Z]%')
						THEN LEFT(PartName, 8)
					ELSE Job
				END AS Job,
				Shipment,
				Op1,
				Op2,
				Op3,
				Mark,
				RawMaterialMaster,
				DueDate
			FROM sap.DemandQueue
			LEFT JOIN sap.RenamedDemandAllocation AS Alloc
				ON Alloc.OriginalPartName=DemandQueue.PartName
				AND Alloc.WorkOrderName=DemandQueue.WorkOrder
		)
		INSERT INTO SNDBaseDev.dbo.TransAct (
			TransType,  -- `SN81B`
			District,
			TransID,	-- for logging purposes
			OrderNo,	-- work order name
			ItemName,	-- Material Master (part name)
			OnHold,		-- part is available for nesting
			DueDate,
			Qty,
			Material,	-- {spec}-{grade}{test}
			Customer,	-- State(occurrence)
			DwgNumber,	-- Drawing name
			Remark,		-- autoprocess instruction
			ItemData1,	-- Job(project)
			ItemData2,	-- Shipment
			ItemData3,	-- Raw material master (from BOM, if exists)
			ItemData4,	-- secondary operation 1
			ItemData5,	-- secondary operation 2
			ItemData6,	-- secondary operation 3
			ItemData9,	-- part name (Material Master with job removed)
			ItemData10,	-- HeatSwap keyword
			ItemData17,	-- SAP Part Name (for when PartName needs changed)
			ItemData18	-- SAP event id

			-- Part Data schema
			--	- Data1-9: Primary nesting processes data
			--	- Data10-15: Secondary nesting data (automation required)
			--	- Data16-18: SAP/Ops required metadata
			--	Data1 : Job
			--	Data2 : Shipment
			--	Data3 : Raw material master (from BOM, if exists)
			--	Data4 : Secondary operation 1
			--	Data5 : Secondary operation 2
			--	Data6 : Secondary operation 3
			--	Data7 : <unused>
			--	Data8 : <unused>
			--	Data9 : Part name (Material Master with job removed)
			--	Data10: HeatSwap keyword
			--	Data11: Part requires secondary check (carried from parts list)
			--	Data12: ChildPart relationship (for slabs)
			--	Data13: ChildPart relationship (continued)
			--	Data14: <unused>
			--	Data15: <unused>
			--	Data16: <unused>
			--	Data17: SAP Part Name
			--	Data18: SAP event id

			-- Data{19,20} limitations (as of Sigmanest/SimTrans 24.4)
			--	- exist in database
			--	- cannot be interacted with using SimTrans or the Sigmanest GUI
			--	- cannot be added as auto text on nests
			--	Data19: <unused>
			--	Data20: <unused>
		)
		SELECT
			'SN81B',
			SimTransDistrict,
			-- TransID is VARCHAR(10), but @sap_event_id is 20-digits
			-- The use of this as TransID is purely for diagnostic reasons,
			-- 	so truncating it to the 10 least significant digits is OK.
			RIGHT(SapEventId, 10),

			-- put on-hold parts in their own work order, since on-hold is a
			--	work order level option
			CONCAT(WorkOrder, CHOOSE(OnHold, '-onhold')),
			PartName,
			OnHold,
			DueDate,
			Qty,
			Matl,

			State,
			Dwg,
			Codegen,	-- autoprocess instruction
			Job,
			Shipment,
			RawMaterialMaster,
			Op1,	-- secondary operation 1
			Op2,	-- secondary operation 2
			Op3,	-- secondary operation 3
			CASE
				WHEN Qty=0 THEN NULL
				WHEN NULLIF(Mark, '') IS NULL	-- piece mark
					THEN REPLACE(PartName, CONCAT(Job,'_'), '')
				ELSE Mark
			END,
			HeatSwapKeyword,
			SapPartName,
			SapEventId
		FROM DemandAndAlloc, sap.InterfaceConfig;

		-- [6] clear queue
		DELETE FROM sap.DemandQueue;

	-- end transaction
	COMMIT TRANSACTION;
END;
GO

-- ********************************************
-- *    Interface 2: Inventory                *
-- ********************************************
CREATE OR ALTER PROCEDURE sap.PushSapInventory
	-- this is the procedure called by Boomi
	@sap_event_id VARCHAR(50) NULL,	-- SAP: numeric 20 positions, no decimal

	@sheet_name VARCHAR(50),
	@sheet_type VARCHAR(64),
	@qty INT,
	@matl VARCHAR(50),
	@thk FLOAT,
	@wid FLOAT,
	@len FLOAT,
	@mm VARCHAR(50),
	@notes1 VARCHAR(50) = NULL,
	@notes2 VARCHAR(50) = NULL,
	@notes3 VARCHAR(50) = NULL,
	@notes4 VARCHAR(50) = NULL
AS
SET NOCOUNT ON
BEGIN
	-- [0] log procedure call
	-- [1] validate SheetName for building DXF path at pre-SimTrans
	-- [2] Queue sheet for SimTrans PreExec

	-- [0] log procedure call
	INSERT INTO log.SapInventoryCalls(
		ProcCalled,
		sap_event_id,
		sheet_name,
		sheet_type,
		qty,
		matl,
		thk,
		wid,
		len,
		mm,
		notes1,
		notes2,
		notes3,
		notes4
	)
	SELECT
		'PushSapInventory',
		@sap_event_id,
		@sheet_name,
		@sheet_type,
		@qty,
		@matl,
		@thk,
		@wid,
		@len,
		@mm,
		@notes1,
		@notes2,
		@notes3,
		@notes4
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] validate SheetName for building DXF path at pre-SimTrans
	--	this way we get errors for Boomi on what will fail later
	IF @sheet_type IN ('Remnant', 'Planned Remnant')
	BEGIN
		-- Having an invalid filepath character in @sheet_name is catastrophic
		--	to the process because we cannot establish a link to the geometry file
		IF @sheet_name LIKE '%[\/:*?"<>|]%'
		BEGIN
			RAISERROR(
				'SheetName `%s` contains an invalid path character',
				16, -- severity
				1,	-- state
				@sheet_name
			);
			-- do not need to ROLLBACK TRANSACTION because nothing changed
			--	and we still want to log the transaction call
			RETURN;
		END;
	END;

	-- [2] Queue sheet for SimTrans PreExec
	INSERT INTO sap.InventoryQueue(
		SapEventId,
		SheetName,	-- SheetName
		SheetType,
		Qty,
		Matl,	-- {spec}-{grade}{test}
		Thk,	-- Thickness batch characteristic
		Width,
		Length,
		MaterialMaster,	-- Material Master
		Notes1,	-- Notes line 1
		Notes2,	-- Notes line 2
		Notes3,	-- Notes line 3
		Notes4	-- Notes line 4
	)
	VALUES (
		@sap_event_id,

		@sheet_name,
		@sheet_type,
		@qty,
		@matl,
		@thk,
		@wid,
		@len,
		@mm,

		-- SAP short text notes
		@notes1,
		@notes2,
		@notes3,
		@notes4
	);
END;
GO
CREATE OR ALTER PROCEDURE sap.InventoryPreExec
AS
BEGIN
	-- called before the SimTrans runs to
	-- [1] add material grades to Sigmanest
	-- [2] (add to Queue) delete sheets in Sigmanest but not SimTrans
	-- [3] delete Queue items with no SheetName
	-- [4] delete compatible materials for sheet deletions
	-- [5] push data into the SimTrans
	-- [6] clear queue

	-- [0] log procedure call
	INSERT INTO log.SapInventoryCalls(ProcCalled)
	SELECT 'InventoryPreExec'
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- place all this in a transaction for consistency
	BEGIN TRANSACTION
		-- [1] add material grades to Sigmanest
		EXEC sap.AddNewMaterials;

		-- [2] push items not in queue for deletion
		WITH ForDeletion AS (
			SELECT
				SheetName,
				Material,
				Thickness,
				Width,
				Length
			FROM SNDBaseDev.dbo.Stock
			WHERE PrimeCode IN (
				SELECT MaterialMaster FROM sap.InventoryQueue
			)
			AND NOT EXISTS (
				SELECT 1 FROM sap.InventoryQueue
				WHERE InventoryQueue.SheetName=Stock.SheetName
				OR InventoryQueue.SapEventId=Stock.BinNumber
			)
		),
		IdMap AS (
			SELECT DISTINCT
				SapEventId,
				Stock.SheetName AS IdSheetName
			FROM sap.InventoryQueue
			INNER JOIN SNDBaseDev.dbo.Stock
				ON Stock.PrimeCode=InventoryQueue.MaterialMaster
		)
		INSERT INTO sap.InventoryQueue(
			SapEventId, SheetName, Qty, Matl, Thk, Width, Length
		)
		SELECT
			SapEventId,
			SheetName,
			0,
			Material,	-- required for 'SN91A'
			Thickness,	-- required for 'SN91A'
			Width,
			Length
		FROM ForDeletion
		LEFT JOIN IdMap
			ON IdMap.IdSheetName=ForDeletion.SheetName;

		-- [3] delete items with no sheet name (Qty=0 items from SAP)
		DELETE FROM sap.InventoryQueue WHERE SheetName IS NULL;

		-- [4] clear stock compatability for removals
		--	'SN91A' becomes 'SN92' if Qty=0, and 'SN92' fails
		--		if there are compatible materials set
		DELETE from SNDBaseDev.dbo.StockCompatibility
		WHERE SheetName in (
			SELECT SheetName
			FROM sap.InventoryQueue
			WHERE Qty=0
		);

		-- [5] push queued items to SimTrans
		INSERT INTO SNDBaseDev.dbo.TransAct (
			TransType,	-- `SN91A or SN97`
			District,
			TransID,	-- for logging purposes
			ItemName,	-- SheetName
			Qty,
			Material,	-- {spec}-{grade}{test}
			Thickness,	-- Thickness batch characteristic
			Width,
			Length,
			PrimeCode,	-- Material Master
			BinNumber,	-- SAP event id
			ItemData1,	-- Notes line 1
			ItemData2,	-- Notes line 2
			ItemData3,	-- Notes line 3
			ItemData4,	-- Notes line 4
			FileName	-- {remnant geometry folder}\{SheetName}.dxf
		)
		SELECT
			-- SimTrans transaction
			CASE
				WHEN SheetType IN ('Remnant', 'Planned Remnant') THEN 'SN97'
				-- SN91A works for everything, but requires special SimTrans options
				ELSE 'SN91A' -- fails if @qty=0
			END,
			SimTransDistrict,
			-- TransID is VARCHAR(10), but @sap_event_id is 20-digits
			-- The use of this as TransID is purely for diagnostic reasons,
			-- 	so truncating it to the 10 least significant digits is OK.
			RIGHT(SapEventId, 10),

			SheetName,
			Qty,
			Matl,
			Thk,
			ISNULL(Width, 1),
			ISNULL(Length, 1),
			MaterialMaster,
			SapEventId,

			-- SAP short text notes
			Notes1,
			Notes2,
			Notes3,
			Notes4,

			-- sheet geometry DXF file (remnants only)
			CASE
				WHEN SheetType IN ('Remnant', 'Planned Remnant')
					THEN CONCAT(RemnantDxfPath, CHAR(92), SheetName, '.dxf')
				ELSE NULL
			END
		FROM sap.InventoryQueue, sap.InterfaceConfig;

		-- [6] clear queue
		DELETE FROM sap.InventoryQueue;

	-- end transaction
	COMMIT TRANSACTION;
END;
GO
CREATE OR ALTER PROCEDURE sap.InventoryPostExec
AS
BEGIN
	-- [0] log procedure call
	INSERT INTO log.SapInventoryCalls(ProcCalled)
	SELECT 'InventoryPostExec'
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] add material compatability for sheets
	INSERT INTO SNDBaseDev.dbo.StockCompatibility (SheetName, Material)
	SELECT SheetName, MatlCompatTable.ChildMatl
	FROM SNDBaseDev.dbo.Stock
	INNER JOIN sap.MatlCompatTable
		ON MatlCompatTable.ParentMatl=Stock.Material
	EXCEPT
	SELECT SheetName, Material
	FROM SNDBaseDev.dbo.StockCompatibility;

	-- [2] delete orphaned StockCompatibility
	DELETE FROM SNDBaseDev.dbo.StockCompatibility
	WHERE SheetName NOT IN (
		SELECT SheetName FROM SNDBaseDev.dbo.Stock
	);
END;
GO

-- ********************************************
-- *    Interface 3: Create/Delete Nest       *
-- ********************************************
CREATE OR ALTER PROCEDURE sap.ConsolidateFeedback
AS
BEGIN
	-- remove(defer) reposts
	--	- Created -> Deleted
	--	- Released -> Deleted
	--		not (Created: pushed to SAP) -> Released -> Deleted
	--	- Any Program with SigmanestStatus = 'Deleted' and Program not in SAP
	WITH
		Updates AS (
			-- Records that need to be sent to SAP
			SELECT
				ProgramGUID, SigmanestStatus
			FROM oys.Status
			WHERE SapStatus IS NULL
		),
		SentToSap AS (
			-- Records that have been exported* to SAP
			--	*may or may not be successful
			SELECT
				ProgramGUID
			FROM oys.Status
			WHERE SapStatus IN ('Sent', 'Complete')
		)
	UPDATE oys.Status SET SapStatus = 'Skipped'
	WHERE ProgramGUID IN (
		SELECT ProgramGUID FROM Updates WHERE SigmanestStatus = 'Deleted'

		-- remove items in SAP
		EXCEPT SELECT ProgramGUID FROM SentToSap
	);
END;
GO
CREATE OR ALTER PROCEDURE sap.GetFeedback
	@skip_consolidation BIT = 0
AS
BEGIN
	-- log procedure call
	INSERT INTO log.FeedbackCalls (ProcCalled)
	SELECT 'GetFeedback'
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	IF @skip_consolidation = 0
		EXEC sap.ConsolidateFeedback;

	-- set feedback to processing
	-- This ensures that if feedback items are added in the middle of processing,
	--	partial data sets do not get  uploaded to SAP
	--	(i.e. Parts list, but not Program header)
	DECLARE @ExportStatus VARCHAR(16) = 'Processing';
	UPDATE oys.Status SET SapStatus = @ExportStatus
	WHERE SapStatus IS NULL;

	-- update NestType for split plate nests
	WITH ProgramToChildPart AS (
		SELECT
			Program.ProgramGUID,
			ChildPart.SNPartName,
			Program.NestType,
			Status.SapStatus
		FROM oys.Program
		INNER JOIN oys.Status
			ON Program.ProgramGUID=Status.ProgramGUID
		INNER JOIN oys.ChildPlate
			ON Program.ProgramGUID=ChildPlate.ProgramGUID
		INNER JOIN oys.ChildPart
			ON ChildPlate.ChildPlateGUID=ChildPart.ChildPlateGUID
	)
	UPDATE ProgramToChildPart SET NestType='Split'
		WHERE SapStatus = @ExportStatus
		AND SNPartName='GHOST';

	-- program(s)
	INSERT INTO sap.FeedbackQueue (
		DataSet,
		ArchivePacketId,
		Status,
		ProgramName,
		RepeatId,
		MachineName,
		CuttingTime
	) SELECT
		'Program' AS DataSet,
		ProgramId.ArchivePacketId,
		UPPER(SigmanestStatus) AS Status,
		ProgramId.ProgramName,
		ProgramId.RepeatId,
		CASE
			WHEN Program.NestType = 'Split'
				THEN 'SPLIT-' + IIF(MachineName LIKE 'Plant_3_%', 'HS02', 'HS01')
			ELSE UPPER(MachineName)
		END AS MachineName,
		CuttingTime	-- This is seconds, FeedbackQueue will round
	FROM oys.Status
	INNER JOIN oys.Program
		ON Status.ProgramGUID = Program.ProgramGUID
	INNER JOIN sap.ProgramId
		ON Program.ProgramGUID = ProgramId.ProgramGUID
	WHERE Status.SapStatus = @ExportStatus;

	-- set all programs that are in SAP as 'Sent' to skip data sets below
	-- [CRITICAL] this needs to be after program(s), but before sheet(s),
	--	otherwise sheet(s), part(s), remnant(s) will produce unnecessary exports
	UPDATE oys.Status SET SapStatus = 'Sent'
	WHERE SAPStatus=@ExportStatus
	AND Status.ProgramGUID IN (
		SELECT ProgramGUID FROM oys.Status
		WHERE SapStatus IN ('Sent', 'Complete')
	);

	-- sheet(s)
	INSERT INTO sap.FeedbackQueue (
		DataSet,
		ArchivePacketId,
		SheetIndex,
		SheetName,
		MaterialMaster
	) SELECT
		'Sheets' AS DataSet,
		ChildNestId.ArchivePacketId,
		ChildPlate.PlateNumber AS SheetIndex,
		ChildPlate.PlateName AS SheetName,
		ChildPlate.MaterialMaster
	FROM oys.ChildPlate
	INNER JOIN sap.ChildNestId
		ON ChildNestId.ProgramGUID = ChildPlate.ProgramGUID
		AND ChildNestId.RepeatId = ChildPlate.ChildNestRepeatID
	INNER JOIN oys.Status
		ON Status.ProgramGUID=ChildNestId.ProgramGUID
		AND ChildPlate.PlateNumber=ChildNestId.SheetIndex
	WHERE Status.SapStatus = @ExportStatus;

	-- part(s)
	INSERT INTO sap.FeedbackQueue (
		DataSet,
		ArchivePacketId,
		SheetIndex,
		PartName,
		PartQty,
		Job,
		Shipment,
		TrueArea,
		NestedArea
	) SELECT
		'Parts' AS DataSet,
		ChildNestId.ArchivePacketId,
		ChildNestId.SheetIndex,
		ChildPart.SAPPartName AS PartName,
		ChildPart.QtyProgram AS PartQty,
		CASE
			-- revert what was done in interface 1
			WHEN ChildPart.Job LIKE 'D-%' THEN ChildPart.Job
			ELSE CONCAT('D-', LEFT(ChildPart.Job, 7))
		END,
		ChildPart.Shipment,
		ROUND(ChildPart.TrueArea, 3),	-- SAP is 3 decimals
		ROUND(ChildPart.NestedArea, 3)	-- SAP is 3 decimals
	FROM oys.ChildPart
	INNER JOIN sap.ChildNestId
		ON ChildNestId.ChildPlateGUID=ChildPart.ChildPlateGUID
	INNER JOIN oys.Status
		ON Status.ProgramGUID=ChildNestId.ProgramGUID
	WHERE Status.SapStatus = @ExportStatus;

	-- remnant(s)
	INSERT INTO sap.FeedbackQueue (
		DataSet,
		ArchivePacketId,
		SheetIndex,
		RemnantName,
		Width,
		Length,
		Area,
		IsRectangular
	) SELECT
		'Remnants' AS DataSet,
		ChildNestId.ArchivePacketId,
		ChildNestId.SheetIndex,
		Remnant.RemnantName,
		Remnant.RectWidth,	-- for batch reference: FeedbackQueue will round
		Remnant.RectLength,	-- for batch reference: FeedbackQueue will round
		ROUND(Remnant.Area, 3),
		CASE Remnant.IsRectangular
			WHEN 1 THEN 'Y'
			ELSE 'N'
		END
	FROM oys.Remnant
	INNER JOIN sap.ChildNestId
		ON ChildNestId.ChildPlateGUID = Remnant.ChildPlateGUID
	INNER JOIN oys.Status
		ON Status.ProgramGUID=ChildNestId.ProgramGUID
	WHERE Status.SapStatus = @ExportStatus;

	-- mark feedback 'Sent' in Status
	UPDATE oys.Status SET SapStatus = 'Sent'
	WHERE SapStatus = @ExportStatus;

	-- return results
	SELECT * FROM sap.FeedbackQueue;
END;
GO
CREATE OR ALTER PROCEDURE sap.MarkFeedbackSapUploadComplete
	@archive_packet_id INT
AS
BEGIN
	-- Marks feedback items as successfully uploaded to SAP.
	-- Feedback items that are not removed will continue to push to SAP

	-- log procedure call
	INSERT INTO log.FeedbackCalls (
		ProcCalled, archive_packet_id
	)
	SELECT
		'MarkFeedbackSapUploadComplete', @archive_packet_id
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- Delete feedback item(s) from queue
	DELETE FROM sap.FeedbackQueue WHERE ArchivePacketId=@archive_packet_id;

	-- update SAPStatus to 'Complete'
	--	there could be multiple Status' with the same @archive_packet_id
	--		(i.e. Created & Released), but we'll ignore that.
	UPDATE oys.Status
	SET SAPStatus = 'Complete'
	FROM oys.Status
	INNER JOIN sap.ProgramId
		ON ProgramId.ProgramGUID=Status.ProgramGUID
	WHERE ArchivePacketId = @archive_packet_id
	AND SAPStatus = 'Sent';
END;
GO
CREATE OR ALTER PROCEDURE sap.GenerateFeedbackForArchivePacketId
	@archive_packet_id INT
AS
BEGIN
	-- Sets a feedback packet to be re-sent

	-- log procedure call
	INSERT INTO log.FeedbackCalls (
		ProcCalled, archive_packet_id
	)
	SELECT
		'GenerateFeedbackForArchivePacketId', @archive_packet_id
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- remove any feedback entries that may still be in the queue
	DELETE FROM sap.FeedbackQueue WHERE ArchivePacketId = @archive_packet_id;

	-- push all status entries for a given packet ID
	UPDATE oys.Status
	SET SAPStatus = NULL
	FROM oys.Status
	INNER JOIN sap.ProgramId
		ON ProgramId.ProgramGUID=Status.ProgramGUID
	WHERE ArchivePacketId = @archive_packet_id;

	-- process feedback
	EXEC sap.GetFeedback 1;
END;
GO


-- ***************************************************
-- *    Interface 4: Release/Delete/Update Program   *
-- ***************************************************
CREATE OR ALTER PROCEDURE sap.ReleaseProgram
	@archive_packet_id INT,
	@source VARCHAR(64) = 'CodeMover',
	@username VARCHAR(64) = NULL
AS
SET NOCOUNT ON
BEGIN
	-- [0] log procedure call
	-- [1] Push a new entry into oys.Status with SigmanestStatus = 'Released'

	-- [0] log procedure call
	INSERT INTO log.UpdateProgramCalls (
		ProcCalled, archive_packet_id, source, username
	)
	SELECT
		'ReleaseProgram', @archive_packet_id, @source, @username
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- [1] Push a new entry into oys.Status with SigmanestStatus = 'Released'
	--	to push to SAP
	INSERT INTO oys.Status (
		DBEntryDateTime,
		ProgramGUID,
		StatusGUID,
		SigmanestStatus,
		Source,
		UserName
	)
	SELECT
		GETDATE(),
		ProgramGUID,
		NEWID(),
		'Released',
		@source,
		ISNULL(@username, CURRENT_USER)
	FROM sap.ProgramStatus
	WHERE ProgramStatus.ArchivePacketId = @archive_packet_id
	AND ProgramStatus.SigmanestStatus = 'Created';
END;
GO
CREATE OR ALTER PROCEDURE sap.UpdateProgram
	-- this is the procedure called by Boomi
	@sap_event_id VARCHAR(50) NULL,	-- SAP: numeric 20 positions, no decimal

	@archive_packet_id INT,
	@source VARCHAR(64) = 'Boomi',
	@username VARCHAR(64) = NULL
AS
SET NOCOUNT ON
BEGIN
	-- [0] log procedure call
	-- [1] delete remnants from nest
	-- [2] Update program (child programs in case of a slab)
	-- [3] delete slab sheet (if slab)
	-- [4] Push a new entry into oys.Status with SigmanestStatus = 'Updated'
	-- [5] add to move queue

	-- Expected Condition:
	-- 	It is expected that the program with the given AutoId exists.
	-- 	If program update in Sigmanest is disabled and all Interface 3
	-- 		transactions have posted, then this should hold
	--	For a slab nest, we only have to update the child nests, because the slab
	--		nest has no work order parts and therefore was not written to the database

	-- [0] log procedure call
	INSERT INTO log.UpdateProgramCalls (
		ProcCalled, sap_event_id, archive_packet_id, source, username
	)
	SELECT
		'UpdateProgram', @sap_event_id, @archive_packet_id, @source, @username
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- load SimTrans district from configuration
	DECLARE @simtrans_district INT = (
		SELECT TOP 1 SimTransDistrict
		FROM sap.InterfaceConfig
	);

	-- TransID is VARCHAR(10), but @sap_event_id is 20-digits
	-- The use of this as TransID is purely for diagnostic reasons,
	-- 	so truncating it to the 10 least significant digits is OK.
	DECLARE @trans_id VARCHAR(10) = RIGHT(@sap_event_id, 10);

	-- [1] delete remnants from nest
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,		-- `SN76`
		District,
		TransID,		-- for logging purposes
		ProgramName,	-- Program name/number
		ProgramRepeat	-- Repeat ID of the program
	)
	SELECT
		'SN76',
		SimTransDistrict,
		@trans_id,
		ProgramName,
		RepeatId
	FROM sap.ChildNestId, sap.InterfaceConfig
	WHERE ArchivePacketId = @archive_packet_id

	-- [2] Update program (child programs in case of a slab)
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,		-- `SN70`
		District,
		TransID,		-- for logging purposes
		ProgramName,	-- Program name/number
		ProgramRepeat	-- Repeat ID of the program
	)
	SELECT
		'SN70',
		SimTransDistrict,
		@trans_id,
		ProgramName,
		RepeatId
	FROM sap.ChildNestId, sap.InterfaceConfig
	WHERE ArchivePacketId = @archive_packet_id;

	-- [3] delete slab sheet (if slab)
	WITH SlabNests AS (
		SELECT DISTINCT
			ArchivePacketId,
			ParentPlate.PlateName AS SheetName
		FROM oys.ParentPlate
		INNER JOIN sap.ProgramId
			ON ProgramId.ProgramGUID=ParentPlate.ProgramGUID
		WHERE ProgramId.NestType='Slab'
	)
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,		-- `SN92`
		District,
		TransID,		-- for logging purposes
		ItemName		-- sheet name
	)
	SELECT DISTINCT
		'SN92',
		SimTransDistrict,
		@trans_id,
		SheetName
	FROM SlabNests, sap.InterfaceConfig
	WHERE ArchivePacketId=@archive_packet_id
	-- Delete compatible materials
	DELETE FROM SNDBaseDev.dbo.StockCompatibility
	WHERE SheetName IN (
		SELECT DISTINCT ItemName
		FROM SNDBaseDev.dbo.TransAct, sap.InterfaceConfig
		WHERE TransType='SN92'
		AND District=SimTransDistrict
	)

	-- [4] Push a new entry into oys.Status with SigmanestStatus = 'Updated'
	--	to simulate a program update
	INSERT INTO oys.Status (
		DBEntryDateTime,
		ProgramGUID,
		StatusGUID,
		SigmanestStatus,
		SAPStatus,
		Source,
		UserName
	)
	SELECT
		GETDATE(),
		ProgramGUID,
		NEWID(),
		'Updated',
		'Complete',
		@source,
		ISNULL(@username, CURRENT_USER)
	FROM sap.ProgramId
	WHERE ArchivePacketId = @archive_packet_id;

	-- [5] add to move queue
	INSERT INTO sap.MoveCodeQueue (
		MachineName,
		ProgramName
	)
	SELECT DISTINCT
		Program.MachineName,
		Program.ProgramName
	FROM sap.ChildNestId
	INNER JOIN oys.Program
		ON Program.ProgramGUID=ChildNestId.ProgramGUID
	WHERE ChildNestId.ArchivePacketId = @archive_packet_id

END;
GO
CREATE OR ALTER PROCEDURE sap.DeleteProgram
	@sap_event_id VARCHAR(50) NULL,	-- SAP: numeric 20 positions, no decimal

	@archive_packet_id INT,
	@source VARCHAR(64) = 'ProgramDelete',
	@username VARCHAR(64) = NULL
AS
SET NOCOUNT ON
BEGIN
	-- [0] log procedure call
	-- [1] Delete program (child programs in case of a slab)
	-- [2] Push a new entry into oys.Status with SigmanestStatus = 'Deleted'

	-- [0] log procedure call
	INSERT INTO log.UpdateProgramCalls (
		ProcCalled, sap_event_id, archive_packet_id, source, username
	)
	SELECT
		'DeleteProgram', @sap_event_id, @archive_packet_id, @source, @username
	FROM sap.InterfaceConfig
	WHERE LogProcedureCalls = 1;

	-- TransID is VARCHAR(10), but @sap_event_id is 20-digits
	-- The use of this as TransID is purely for diagnostic reasons,
	-- 	so truncating it to the 10 least significant digits is OK.
	DECLARE @trans_id VARCHAR(10) = RIGHT(@sap_event_id, 10);

	-- [1] Delete program (child programs in case of a slab)
	INSERT INTO SNDBaseDev.dbo.TransAct (
		TransType,		-- `SN76`
		District,
		TransID,		-- for logging purposes
		ProgramName,	-- Program name/number
		ProgramRepeat	-- Repeat ID of the program
	)
	SELECT
		'SN74',
		SimTransDistrict,
		@trans_id,
		ProgramName,
		RepeatId
	FROM sap.ChildNestId, sap.InterfaceConfig
	WHERE ArchivePacketId = @archive_packet_id;

	-- [2] Push a new entry into oys.Status with SigmanestStatus = 'Deleted'
	--	to simulate a program delete
	INSERT INTO oys.Status (
		DBEntryDateTime,
		ProgramGUID,
		StatusGUID,
		SigmanestStatus,
		Source,
		UserName
	)
	SELECT
		GETDATE(),
		ProgramGUID,
		NEWID(),
		'Deleted',
		@source,
		ISNULL(@username, CURRENT_USER)
	FROM sap.ProgramId
	WHERE ProgramId.ArchivePacketId = @archive_packet_id;
END;
GO

-- ***************************************************
-- *    SimTrans: Runs before/after SimTrans runs    *
-- ***************************************************
CREATE OR ALTER PROCEDURE sap.SimTransPreExec
AS BEGIN
	-- moved to Boomi
	-- TODO: remove from SimTrans configuration
	SELECT 1;
END;
GO
CREATE OR ALTER PROCEDURE sap.SimTransPostExec
AS BEGIN
	EXEC sap.InventoryPostExec;
END;
GO
