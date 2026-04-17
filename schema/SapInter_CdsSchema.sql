
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
	SheetIndex INT,
	ScheduledBurnDate DATE,
	Priority INT,
	Shift INT DEFAULT 1,
	PreBlast BIT DEFAULT 0,

	-- Haul out only
	SheetName VARCHAR(50),
	Destination VARCHAR(16),

	-- added per shop request
	Notes VARCHAR(1000)
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
