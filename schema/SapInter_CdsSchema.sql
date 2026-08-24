
USE SNInterDev;
GO

-- Code Delivery System schema
CREATE SCHEMA cds;
GO

CREATE TABLE cds.Machines (
	Id INT IDENTITY(1,1) PRIMARY KEY,
	MachineName VARCHAR(50) NOT NULL,
	Plant VARCHAR(64),
	Bay VARCHAR(64),
	SLoc VARCHAR(4)
);
GO

INSERT INTO cds.Machines (MachineName, Plant, Bay, SLoc)
VALUES
	('Gemini', 'Lancaster', 'Detail', '1W01'),
	('MG_TITAN_GLOBAL', 'Lancaster', 'Detail', '1D01'),
	('MG_OXY_GLOBAL', 'Lancaster', 'Detail', '1D04'),
	('Plant_2_MG_Global', 'Lancaster', 'North', '2N01'),
	('Kinetic_K5000XMC', 'Lancaster', 'South', '2S01'),
	('Plant_3_Farley', 'Williamsport', 'North', NULL),
	('Plant_3_MG_Global', 'Williamsport', 'South', NULL);

CREATE TABLE cds.MaterialPlanner (
	Id INT IDENTITY(1,1) PRIMARY KEY,
	ModifiedDateTime DATETIME DEFAULT CURRENT_TIMESTAMP,
	RequestType VARCHAR(16),	-- Haul In/Out

	-- Haul in only
	ProgramName VARCHAR(50),
	MachineName VARCHAR(50),	-- TODO: (in CleanMP) remove if Bay changes

	ScheduledBurnDate DATE,
	SortOrder INT,
	PreBlast BIT DEFAULT 0,

	-- Haul out only
	SheetName VARCHAR(50),
	Destination VARCHAR(16),

	-- added per shop request
	Notes VARCHAR(1000)
);
GO

CREATE TABLE cds.MaterialPlannerSnapshot (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
	PlannerId INT NOT NULL,
    ModifiedDateTime DATETIME,
    RequestType VARCHAR(16),
    ProgramName VARCHAR(50),
	SheetIndex INT,
	Plant VARCHAR(64),
	Bay VARCHAR(64),
    MachineName VARCHAR(50),
    ScheduledBurnDate DATE,
    Priority INT,
    MaterialMaster VARCHAR(50),
    Batch VARCHAR(10),
    Weight DECIMAL(18, 2),
    Thickness DECIMAL(18, 4),
    Width DECIMAL(18, 4),
    Length DECIMAL(18, 4),
    SLoc VARCHAR(255),
    JobShipment VARCHAR(MAX),
    PreBlast VARCHAR(3), -- 'Yes'/'No'
    Destination VARCHAR(16),
    Notes VARCHAR(1000),
	
    HashValue VARBINARY(32) NOT NULL,
	IsActive BIT DEFAULT 1
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
