
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
				cp.PlateNumber AS SheetIndex,
				cp.PlateName AS SheetName,
				mach.SLoc,
				ROW_NUMBER() OVER (
					PARTITION BY PlateName, SLoc
					ORDER BY
						mp.ScheduledBurnDate,
						mp.MachineName,
						mp.SortOrder
				) AS PartitionId
			FROM cds.MaterialPlanner mp
			INNER JOIN sap.ProgramStatus prog
				ON prog.ProgramName=mp.ProgramName
			INNER JOIN oys.ChildPlate cp
				ON  cp.ProgramGUID = prog.ProgramGUID
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


CREATE OR ALTER VIEW cds.ExpandedMaterialPlanner
AS
	WITH PriorityMap AS (
		SELECT
			ProgramName,
			ROW_NUMBER() OVER(
				PARTITION BY Plant, Bay
				ORDER BY mp.ScheduledBurnDate, mp.MachineName, mp.SortOrder
			) AS Priority
		FROM cds.MaterialPlanner mp
		INNER JOIN cds.Machines m
			ON m.MachineName=mp.MachineName
		WHERE ScheduledBurnDate IS NOT NULL
	), 
	Jobs AS (
		SELECT
			ProgramName,
			STRING_AGG(JobShipment, ',') AS Jobs
		FROM (
			SELECT DISTINCT
				ProgramName,
				CONCAT(ChildPart.Job, '-', ChildPart.Shipment) AS JobShipment
			FROM cds.NestChildPlates
			INNER JOIN oys.ChildPart
				ON ChildPart.ChildPlateGUID=NestChildPlates.ChildPlateGUID
			WHERE ISNULL(ChildPart.Job, '') != ''
		) AS js
		GROUP BY ProgramName
	),
	PlannerState AS (
	SELECT
		mp.Id AS PlannerId,
		mp.ModifiedDateTime,
		RequestType,

		mp.ProgramName,
		ISNULL(cn.SheetIndex, -1) AS SheetIndex,
		m.Plant,
		m.Bay,
		mp.MachineName,
		ScheduledBurnDate,
		Priority,
		Stock.materialMaster,
		CASE
			WHEN Stock.SheetName != Stock.MaterialMaster
				THEN (
					SELECT TOP 1 Batch
					FROM inv.Batches
					WHERE Batches.SheetName=Stock.SheetName
				)
			ELSE ''
		END AS Batch,
		ROUND(Stock.Weight + 100, -2) AS Weight, -- round up to the nearest 100 lbs
		Stock.Thickness,
		Stock.Width,
		Stock.Length,
		ISNULL(SLocMap.Sloc, '') AS SLoc,
		jobs.Jobs AS JobShipment,
		IIF(PreBlast=1, 'Yes', 'No') AS Preblast,
		Destination,
		Notes
	FROM cds.MaterialPlanner mp
	LEFT JOIN PriorityMap
		ON PriorityMap.ProgramName=mp.ProgramName
	LEFT JOIN Jobs
		ON Jobs.ProgramName=mp.ProgramName
	LEFT JOIN cds.Machines m
		ON m.MachineName=mp.MachineName
	LEFT JOIN cds.NestChildPlates cn
		ON cn.ProgramName=mp.ProgramName
	LEFT JOIN inv.SlocMap
		ON SLocMap.SheetName=cn.SheetName
	LEFT JOIN inv.StockWeights Stock
		ON Stock.SheetName=cn.SheetName
	)
	SELECT
		*,

		HASHBYTES(
			'SHA2_256',
			CASE
				-- We are not delimiting values because the chance of that making a difference is unlikely.
				-- We are only going to use Weight as a sheet dimension to sense a difference.
				--	While this is technically innacurate, it is good enough for our use.
				WHEN RequestType = 'Haul In'
					THEN CONCAT(
						CONVERT(NVARCHAR(30), ModifiedDateTime),
						MachineName,
						ISNULL(CONVERT(NVARCHAR(30), ScheduledBurnDate), '<delete>'),
						Priority,
						MaterialMaster,
						Batch,
						Weight,
						Sloc,
						jobShipment,
						preBlast,
						notes
					)
				WHEN RequestType = 'Haul Out'
					THEN CONCAT(
						Batch,
						SLoc,
						Destination
					)
				ELSE CONVERT(NVARCHAR(30), ModifiedDateTime)
			END
		) AS HashValue
	FROM PlannerState;
GO