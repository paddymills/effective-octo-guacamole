USE SNInterDev;
GO

CREATE SCHEMA sap;
GO

CREATE SCHEMA archive;
GO

CREATE SCHEMA cds;
GO

DECLARE @district INT = 1;
DECLARE @do_logging BIT = 0;
DECLARE @env_name VARCHAR(8) = 'Qas';
CREATE TABLE sap.InterfaceConfig (
	-- All queries of this configuration table use `SELECT TOP 1` to ensure that
	-- 	that the transaction happens against 1 district. It could be catastrophic
	-- 	to post transactions against multiple Sigmanest databases, since each SAP
	-- 	system will have 1 Sigmanest database synced with it.
	-- Essentially, this table should only have 1 entry. Lock ensures that:
	--	https://stackoverflow.com/a/3971669
	Lock TINYINT NOT NULL DEFAULT 1,
	CONSTRAINT PK_CONFIG PRIMARY KEY (Lock),
	CONSTRAINT CK_CONFIG_LOCKED CHECK (Lock = 1),
	-- SimTrans district (Sigmanest system) involved with SAP system
	SimTransDistrict INT NOT NULL,
	-- Path format template string to build DXF file
	RemnantDxfPath VARCHAR(255),
	-- Path should be to a windows file system folder without trailing \
	--	(as well as other invalid windows folder name characters)
	CONSTRAINT CK_RemnantDxfPath CHECK (RemnantDxfPath NOT LIKE '%[\/:*?"<>|]'),
	-- Placehold word used heat swap (inserted into Data14 in interface 1).
	-- This might be hardcoded in the Sigmanest post, so check before changing.
	-- Changing this also requires changing the HeatSwap configuration.
	-- NOTE: this cannot be more than 12 characters because of the Gemini.
	HeatSwapKeyword VARCHAR(64),
	-- Log procedure calls to log schema for debugging
	-- TODO: logging level instead of on/off
	LogProcedureCalls BIT
);
INSERT INTO
	sap.InterfaceConfig (SimTransDistrict, RemnantDxfPath, HeatSwapKeyword, LogProcedureCalls)
VALUES
	(
		@district,
		'\\hssieng\SNData' + @env_name + '\RemSaveOutput\DXF',
		'HighHeatNum',
		@do_logging
	);
GO

CREATE TABLE sap.InterfaceVersion (
	Lock TINYINT NOT NULL DEFAULT 1,
	CONSTRAINT PK_VERSION PRIMARY KEY (Lock),
	CONSTRAINT CK_VERSION_LOCKED CHECK (Lock = 1),
	-- semver <major>.<minor>.<patch>
	Major INT NOT NULL,
	Minor INT NOT NULL,
	Patch INT NOT NULL
);
INSERT INTO sap.InterfaceVersion (Major, Minor, Patch)
VALUES (0, 0, 0);
GO

CREATE TABLE sap.MatlCompatMap (
	Id INT IDENTITY(1,1) PRIMARY KEY,
	ParentMatl VARCHAR(50),
	ChildMatl VARCHAR(50),
	UseIntermediateCompat BIT,
	IsBidirectional BIT,

	CONSTRAINT ParentChildDiffer
		CHECK (ParentMatl != ChildMatl)
);
INSERT INTO sap.MatlCompatMap (
	ParentMatl, ChildMatl, UseIntermediateCompat, IsBidirectional
)
VALUES
	('50/50WF2',   'A709-50WF2', 1, 0),
	('50/50WF2',   'A709-50F2',  1, 0),
	('50/50WF2',   '50/50WT2',   0, 0),

	('50/50WT2',   'A709-50WT2', 1, 0),
	('50/50WT2',   'A709-50T2',  1, 0),
	('50/50WT2',   '50/50W',     0, 0),

	('50/50W',     'A709-50W',   1, 0),
	('50/50W',     'A709-50',    1, 0),

	('A709-50WF2', 'A709-50WT2', 1, 0),
	('A709-50WT2', 'A709-50W',   1, 0),
	('A709-50F2',  'A709-50T2',  1, 0),
	('A709-50T2',  'A709-50',    1, 0),

	-- A709 -> M270
	('A709-50WF2', 'M270-50WF2', 1, 1),
	('A709-50WT2', 'M270-50WT2', 1, 1),
	('A709-50W',   'M270-50W',   1, 1),
	('A709-50F2',  'M270-50F2',  1, 1),
	('A709-50T2',  'M270-50T2',  1, 1),
	('A709-50',    'M270-50',    1, 1);
GO

-- ********************************************
-- *    Interface 1: Demand                   *
-- ********************************************
CREATE TABLE sap.DemandQueue (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	SapEventId VARCHAR(50) NULL,	-- SAP: numeric 20 positions, no decimal
	SapPartName VARCHAR(18),

	WorkOrder VARCHAR(50),
	PartName VARCHAR(100),
	Qty INT,
	Matl VARCHAR(50),
	OnHold BIT,

	State VARCHAR(50),
	Dwg VARCHAR(50),
	Codegen VARCHAR(50),	-- autoprocess instruction
	Job VARCHAR(50),
	Shipment VARCHAR(50),
	Op1 VARCHAR(50),	-- secondary operation 1
	Op2 VARCHAR(50),	-- secondary operation 2
	Op3 VARCHAR(50),	-- secondary operation 3
	Mark VARCHAR(50),	-- part name (Material Master with job removed)
	RawMaterialMaster VARCHAR(50),
	DueDate DATE
);
GO
CREATE TABLE sap.RenamedDemandAllocation (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	OriginalPartName VARCHAR(50),
	NewPartName VARCHAR(50),
	WorkOrderName VARCHAR(50),
	Qty INT,

	-- required or sap.PushSapDemand could result
	--	in an endless recursive loop
	CONSTRAINT PartNamesDiffer
		CHECK (OriginalPartName != NewPartName)
);
GO
CREATE TABLE sap.PartOperations (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	PartName VARCHAR(50),
	Operation2 VARCHAR(50),
	Operation3 VARCHAR(50),
	Operation4 VARCHAR(50),
	AutoProcessInstruction VARCHAR(50)
);
GO

-- ********************************************
-- *    Interface 2: Inventory                *
-- ********************************************
CREATE TABLE sap.InventoryQueue (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	SapEventId VARCHAR(50),	-- SAP: numeric 20 positions, no decimal
	SheetName VARCHAR(50),
	SheetType VARCHAR(64),
	Qty INT,
	Matl VARCHAR(50),
	Thk FLOAT,
	Width FLOAT,
	Length FLOAT,
	MaterialMaster VARCHAR(50),
	Notes1 VARCHAR(50),
	Notes2 VARCHAR(50),
	Notes3 VARCHAR(50),
	Notes4 VARCHAR(50)
);
GO

-- ********************************************
-- *    Interface 3: Create/Delete Nest       *
-- ********************************************
-- Boomi table for results
CREATE TABLE sap.FeedbackQueue (
	FeedBackId BIGINT IDENTITY(1,1) PRIMARY KEY,
	DataSet VARCHAR(64),

	-- Program
	ArchivePacketId BIGINT,
	Status VARCHAR(64),
	ProgramName VARCHAR(50),
	RepeatId INT,
	MachineName VARCHAR(50),
	CuttingTime INT,

	-- Sheet(s)
	SheetIndex INT,
	SheetName VARCHAR(50),
	MaterialMaster VARCHAR(50),

	-- Part(s)
	PartName VARCHAR(100),
	PartQty INT,
	Job VARCHAR(50),
	Shipment VARCHAR(50),
	TrueArea FLOAT,
	NestedArea FLOAT,

	-- Remnant(s)
	RemnantName VARCHAR(50),
	Length INT,
	Width INT,
	Area FLOAT,
	IsRectangular CHAR
);
GO
CREATE TABLE cds.ShopNestData (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	ProgramName VARCHAR(50),
	DatePrinted DATETIME,
	PrintedBy VARCHAR(255)
);
GO
CREATE TABLE archive.ShopNestData (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	ArcDateTime DATETIME DEFAULT CURRENT_TIMESTAMP, 
	ProgramName VARCHAR(50),
	DatePrinted DATETIME,
	PrintedBy VARCHAR(255)
);
GO

-- ********************************************
-- *    Interface 4: Move Code                *
-- ********************************************
CREATE TABLE sap.MoveCodeQueue (
	Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	MachineName VARCHAR(50),
	ProgramName VARCHAR(50)
);
GO
