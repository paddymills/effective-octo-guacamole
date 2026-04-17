
USE SNInterDev;
GO


CREATE OR ALTER VIEW cds.NestChildPlates
AS
	SELECT
		parent.ProgramGUID,
		child.ChildPlateGUID,

		parent.ProgramName,
		child.PlateNumber AS SheetIndex,
		child.PlateName AS SheetName,
		child.MaterialMaster
	FROM sap.ActivePrograms parent
	INNER JOIN oys.ChildPlate child
		ON child.ProgramGUID=parent.ProgramGUID;
GO

CREATE OR ALTER VIEW cds.RemnantsFromNests
AS
	SELECT
		n.ProgramGUID,
		n.ChildPlateGUID,
		r.RemnantGUID,

		n.ProgramName,
		r.RemnantName
	FROM cds.NestChildPlates n
	INNER JOIN oys.Remnant r
		ON r.ChildPlateGUID=n.ChildPlateGUID;
GO

-- TODO: remove
CREATE OR ALTER VIEW cds.JsonShopNests_Test
AS
	SELECT (
		SELECT
		  -- program header
		  ProgramStatus.ArchivePacketId AS Id,
		  ProgramStatus.SigmanestStatus AS Status,
		  ProgramStatus.ProgramName AS Name,
		  ProgramStatus.RepeatId,
		  Program.MachineName AS Machine,
		  Program.CuttingTime,
		  Program.NestType AS Type,
		  ShopNestData.DatePrinted

		FROM sap.ProgramStatus
		INNER JOIN oys.Program
		  ON Program.ProgramGUID = ProgramStatus.ProgramGUID
		LEFT JOIN cds.ShopNestData
		  ON ShopNestData.ProgramName=ProgramStatus.ProgramName

		WHERE ProgramStatus.SigmanestStatus IN ('Released', 'Created')

		ORDER BY Id
		FOR JSON PATH
	) AS JsonData;
GO

CREATE OR ALTER VIEW cds.ShopNestHeaders
AS
	SELECT
		ProgramStatus.ProgramGUID,
		ProgramStatus.ArchivePacketId AS Id,
		ProgramStatus.SigmanestStatus AS Status,
		ProgramStatus.ProgramName AS Name,
		ProgramStatus.RepeatId,
		Program.MachineName AS Machine,
		Program.CuttingTime,
		Program.NestType AS Type,
		CASE
			WHEN Program.NestType = 'Slab' THEN NULL
			ELSE ParentPlate.Material
		END AS MaterialGrade,
		CASE
			WHEN Program.NestType = 'Slab' THEN NULL
			ELSE ParentPlate.Thickness
		END AS Thickness,
		ShopNestData.DatePrinted
	FROM sap.ProgramStatus
	INNER JOIN oys.Program
	  ON Program.ProgramGUID = ProgramStatus.ProgramGUID
	INNER JOIN oys.ParentPlate
	  ON ParentPlate.ProgramGUID = ProgramStatus.ProgramGUID
	LEFT JOIN cds.ShopNestData
	  ON ShopNestData.ProgramName=ProgramStatus.ProgramName

	WHERE ProgramStatus.SigmanestStatus IN ('Released', 'Created');

	-- ORDER BY Id;
GO

CREATE OR ALTER VIEW cds.ShopNestDetail
AS
	SELECT
		Name,
		(
			SELECT
				-- program header
				JsonLevel.Id,
				JsonLevel.Status,
				JsonLevel.Name,
				JsonLevel.RepeatId,
				JsonLevel.Machine,
				JsonLevel.CuttingTime,
				JsonLevel.Type,
				JsonLevel.DatePrinted,

				-- (parent) part(s)
				(
					SELECT
						SNPartName AS PartName,
						QtyProgram AS Qty
					FROM oys.ParentPart
					WHERE ParentPart.ProgramGUID=JsonLevel.ProgramGUID
					FOR JSON PATH
				) AS Parts,

				-- sheet(s)
				(
					SELECT
						PlateName AS SheetName,
						MaterialMaster,
						Material,
						Thickness,
						(
							SELECT TOP 1
								ActivePrograms.ProgramName
							FROM sap.ActivePrograms
							INNER JOIN oys.ChildPlate AS Linker
								ON Linker.ProgramGUID=ActivePrograms.ProgramGUID
							INNER JOIN oys.Remnant
								ON Remnant.ChildPlateGUID=Linker.ChildPlateGUID
							WHERE Remnant.RemnantName = ChildPlate.PlateName
						) AS RemnantProgramName,

						-- parts(s)
						(
							SELECT
								SNPartName AS PartName,
								QtyProgram AS Qty,
								Job,
								Shipment,
								QNNumber
							FROM oys.ChildPart
							WHERE ChildPart.ChildPlateGUID=ChildPlate.ChildPlateGUID
							ORDER BY SNPartName
							FOR JSON PATH
						) AS Parts,

						-- remnant(s)
						(
							SELECT
								RemnantName,
								RectWidth,
								RectLength,
								IsRectangular
							FROM oys.Remnant
							WHERE Remnant.ChildPlateGUID=ChildPlate.ChildPlateGUID
							ORDER BY RemnantName
							FOR JSON PATH
						) AS Remnants
					FROM oys.ChildPlate
					WHERE ChildPlate.ProgramGUID=JsonLevel.ProgramGUID
					ORDER BY ChildPlate.PlateNumber
					FOR JSON PATH
				) AS Sheets
			FROM cds.ShopNestHeaders AS JsonLevel
			WHERE JsonLevel.ProgramGUID=QueryLevel.ProgramGUID

			ORDER BY Id
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		) AS JsonData
	FROM cds.ShopNestHeaders AS QueryLevel;
GO

CREATE OR ALTER VIEW cds.ShopNests
AS
	SELECT (
		SELECT
		  -- program header
		  ProgramStatus.ArchivePacketId AS Id,
		  ProgramStatus.SigmanestStatus AS Status,
		  ProgramStatus.ProgramName AS Name,
		  ProgramStatus.RepeatId,
		  Program.MachineName AS Machine,
		  Program.CuttingTime,
		  Program.NestType AS Type,
		  ShopNestData.DatePrinted,

		  -- (parent) part(s)
		  (
			SELECT
			  SNPartName AS PartName,
			  QtyProgram AS Qty
			FROM oys.ParentPart
			WHERE ParentPart.ProgramGUID=ProgramStatus.ProgramGUID
			FOR JSON PATH
		  ) AS Parts,

		  -- sheet(s)
		  (
			SELECT
			  PlateName AS SheetName,
			  MaterialMaster,
			  Material,
			  Thickness,
			  (
				SELECT TOP 1
				  ActivePrograms.ProgramName
				FROM sap.ActivePrograms
				INNER JOIN oys.ChildPlate AS Linker
				  ON Linker.ProgramGUID=ActivePrograms.ProgramGUID
				INNER JOIN oys.Remnant
				  ON Remnant.ChildPlateGUID=Linker.ChildPlateGUID
				WHERE Remnant.RemnantName = ChildPlate.PlateName
			  ) AS RemnantProgramName,

			  -- parts(s)
			  (
				SELECT
				  SNPartName AS PartName,
				  QtyProgram AS Qty,
				  Job,
				  Shipment,
				  QNNumber
				FROM oys.ChildPart
				WHERE ChildPart.ChildPlateGUID=ChildPlate.ChildPlateGUID
				ORDER BY SNPartName
				FOR JSON PATH
			  ) AS Parts,

			  -- remnant(s)
			  (
				SELECT
				  RemnantName,
				  RectWidth,
				  RectLength,
				  IsRectangular
				FROM oys.Remnant
				WHERE Remnant.ChildPlateGUID=ChildPlate.ChildPlateGUID
				ORDER BY RemnantName
				FOR JSON PATH
			  ) AS Remnants
			FROM oys.ChildPlate
			WHERE ChildPlate.ProgramGUID=ProgramStatus.ProgramGUID
			ORDER BY ChildPlate.PlateNumber
			FOR JSON PATH
		  ) AS Sheets
		FROM sap.ProgramStatus
		INNER JOIN oys.Program
		  ON Program.ProgramGUID = ProgramStatus.ProgramGUID
		LEFT JOIN cds.ShopNestData
		  ON ShopNestData.ProgramName=ProgramStatus.ProgramName

		WHERE ProgramStatus.SigmanestStatus IN ('Released', 'Created')

		ORDER BY Id
		FOR JSON PATH
	) AS JsonData;
GO

-- TODO: remove
CREATE OR ALTER VIEW inv.GetAllBatches
AS
	SELECT (
		SELECT
			Batch, SheetType, SheetName, MaterialMaster, Plant, SLoc
		FROM inv.Batches
		FOR JSON PATH
	) AS JsonView;
GO

-- TODO: remove
CREATE OR ALTER VIEW cds.GetSchedules
AS
	SELECT (
		SELECT
			Id, Priority, ProgramName, ScheduledBurnDate, Shift, PreBlast
		FROM cds.MaterialPlanner
		FOR JSON PATH
	) AS JsonView;
GO


CREATE OR ALTER VIEW inv.StockWeights
AS
	SELECT
		SheetName,
		PrimeCode AS MaterialMaster,
		Material,
		Thickness,
		Width,
		Length,
		CASE CalculatedWeight
			WHEN 1 THEN Weight
			ELSE Material.Densityin * Thickness * Area
		END AS Weight

	FROM SNDBaseDev.dbo.Stock
	LEFT JOIN SNDBaseDev.dbo.Material
		ON Material.MaterialType=Stock.Material;
GO

CREATE OR ALTER VIEW inv.SLocMap
AS
	-- A mapping of { [SheetName]: [StorageLocation(Count)] }
	SELECT DISTINCT
		SheetName,
		CASE
			WHEN SheetName != MaterialMaster THEN SLoc
			ELSE (
				SELECT STRING_AGG(
					CONCAT(sloc_value, '(', sloc_count, ')'),
					','
				)
				FROM (
					SELECT
						SLoc as sloc_value,
						COUNT(*) as sloc_count
					FROM inv.Batches b2
					WHERE b2.SLoc NOT LIKE 'T%'
						AND b2.SLoc != 'RAIL'
						AND b2.SLoc NOT IN (SELECT ISNULL(SLoc, '') from cds.Machines)
						AND b2.SheetName = b1.SheetName
						AND b2.MaterialMaster = b1.MaterialMaster
						AND b2.SheetName = b2.MaterialMaster
					GROUP BY SLoc
				) counts
			)
		END AS SLoc
	FROM inv.Batches b1;
GO

CREATE OR ALTER VIEW inv.PlateCounts
AS
	WITH InvCount AS (
		SELECT
			SheetName,
			COUNT(SheetName) AS TotalQty
		FROM inv.Batches
		WHERE SLoc != 'RAIL'
		GROUP BY SheetName
	),
	ScheduledPlates AS (
		SELECT
			nests.SheetName,
			COUNT(nests.SheetName) AS ScheduledQty
		FROM cds.MaterialPlanner
		INNER JOIN cds.NestChildPlates AS nests
			ON nests.ProgramName=MaterialPlanner.ProgramName
		GROUP BY nests.SheetName
	)
	SELECT
		InvCount.SheetName,
		InvCount.TotalQty - ISNULL(ScheduledPlates.ScheduledQty, 0) AS AvailableQty,
		ISNULL(ScheduledPlates.ScheduledQty, 0) AS ScheduledQty,
		InvCount.TotalQty
	FROM InvCount
	LEFT JOIN ScheduledPlates
		ON ScheduledPlates.SheetName=InvCount.SheetName;
GO

CREATE OR ALTER VIEW inv.ProgramSheetCounts
AS
	SELECT
		nests.ProgramName,
		nests.SheetName,
		COUNT(nests.SheetName) AS QtyRequired
	FROM cds.NestChildPlates AS nests
	GROUP BY nests.ProgramName, nests.SheetName;
GO

CREATE OR ALTER VIEW cds.ScheduleNestInvAlloc
AS
	WITH
		RankedRequirements AS (
			SELECT
				mp.ProgramName,
				mp.SheetIndex,
				cp.PlateName AS SheetName,
				mach.SLoc,
				ROW_NUMBER() OVER (
					PARTITION BY PlateName, SLoc
					ORDER BY Priority
				) AS PartitionId
			FROM cds.MaterialPlanner mp
			INNER JOIN sap.ProgramStatus prog
				ON prog.ProgramName=mp.ProgramName
			INNER JOIN oys.ChildPlate cp
				ON  cp.ProgramGUID = prog.ProgramGUID
				AND cp.PlateNumber = mp.SheetIndex
			INNER JOIN cds.Machines mach
				ON mach.MachineName = prog.MachineName
			WHERE mp.RequestType = 'Haul In'
		),
		RankedReservations AS (
			SELECT
				b.SheetName,
				b.SLoc,
				ROW_NUMBER() OVER (
					PARTITION BY SheetName, SLoc
					ORDER BY Batch
				) AS PartitionId
			FROM inv.Batches b
			WHERE b.SLoc IN (SELECT SLoc FROM cds.Machines)
		)
	SELECT
		req.ProgramName,
		req.SheetIndex,
		CAST(CASE
			WHEN res.SheetName IS NULL THEN 0
			ELSE 1
		END AS BIT) AS InventoryLoaded
	FROM RankedRequirements req
	LEFT JOIN RankedReservations res
		ON  res.SheetName   = req.SheetName
		AND res.SLoc        = req.SLoc
		AND res.PartitionId = req.PartitionId;
GO
