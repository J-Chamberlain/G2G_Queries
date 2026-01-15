USE [REAF_Enterprise]
-------------------------------------------------------------
-- 1. First Refresh the tables
-------------------------------------------------------------

 EXEC RefreshStrategyImpactTables;
 --Select top 100* from Strategy_Impact_by_installation order by installation,  Strat_ID;
 --Select top 100* from REAF_Initial_MSS_Scores_by_strategy order by installation, Strat_Id;
 --Select top 10* from REAF_Initial_Scores order by installation; 

  EXEC GenerateGapClosureOpportunities 
     @Technology_id = NULL, -- 'Microgrid', 
	 @REAF_Scale = 'NULL',-- Installation or Building
     @PMRGapScopeFilter = '%NULL%', 
     @PMRGapScopeFilterOperator = 'Like',  -- Use the not equals operator
     @MinRelevancyScore = 75, 
     @MinTechToStratRelevancyScore = 75,
     @ClearExistingData = 1, -- Set to 1 to clear the tables on first run 
     @GenerateStrategyImpact = 1; 

-------------------------------------------------------------
-- 2. Run each batch, one Technology at a time at the Installation and then the Building levels
-------------------------------------------------------------

-- Create a temporary table to hold the technology IDs and names
DECLARE @Technologies TABLE (
    Technology_id INT,
    TechnologyName VARCHAR(100)
);

-- Implement Technologies in the following order 
INSERT INTO @Technologies (Technology_id, TechnologyName)
VALUES
    (12, 'Microgrid'),
    (7, 'Substations'),
    (14, 'Power Quality'),
    (11, 'Generator Reliability'),
    (15, 'Battery Energy Storage Systems (BESS)'),
    (4, 'Uptime Institute Data Center Site Infrastructure Tier Standard'),
    (10, 'Combustion Turbines (CT)'),
    (2, 'Reciprocating Internal Combustion Engines (RICE)'),
    (3, 'Solar Photovoltaic (PV)');
/****** Other Technologies to choose from:
	Technology_id	Technology
	1	Geothermal
	5	Fuel Cells
	6	Hydrogen Production
	8	Industrial Control Systems (ICS) Cybersecurity
	10	Combustion Turbines (CT)
	13	Nuclear Generators
	16	Combined Heat and Power (CHP)
******/

-- Declare a cursor to iterate through the technologies
DECLARE @Technology_id INT;
DECLARE @TechnologyName VARCHAR(100);

-- Declare a cursor to iterate through each technology
DECLARE TechnologyCursor CURSOR FOR
SELECT Technology_id, TechnologyName FROM @Technologies;

-- Open the cursor
OPEN TechnologyCursor;

-- Fetch the first row
FETCH NEXT FROM TechnologyCursor INTO @Technology_id, @TechnologyName;

-- Loop through all technologies
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '-- Processing Technology: ' + @TechnologyName + ' (ID: ' + CAST(@Technology_id AS VARCHAR) + ')';
    
    -- Execute for Installation level
    PRINT '-- Executing for Installation level';
    EXEC GenerateGapClosureOpportunities 
        @Technology_id = @Technology_id,
        @REAF_Scale = 'Installation',
        @PMRGapScopeFilter = '%Installation%', 
        @PMRGapScopeFilterOperator = 'Like',
        @MinRelevancyScore = 75, 
        @MinTechToStratRelevancyScore = 75;
    
    -- Execute for Building level
    PRINT '-- Executing for Building level';
    EXEC GenerateGapClosureOpportunities 
        @Technology_id = @Technology_id,
        @REAF_Scale = 'Building',
        @PMRGapScopeFilter = '%Installation%', 
        @PMRGapScopeFilterOperator = 'Not Like',
        @MinRelevancyScore = 75, 
        @MinTechToStratRelevancyScore = 75;
    
	EXEC dbo.UpdateREAFScores @Technology =  @TechnologyName;
    -- Fetch the next row
    FETCH NEXT FROM TechnologyCursor INTO @Technology_id, @TechnologyName;
END

-- Close and deallocate the cursor
CLOSE TechnologyCursor;
DEALLOCATE TechnologyCursor;

--Select * from Gap_Closure_Opportunities order by  [Installation(s)],  Row_id;
Select * from Strategy_Impact order by  [Installation(s)], Row_id; --, REAF_Scale desc,Strategy_id,
--Select * from Strategy_Impact_by_installation order by installation, Strat_ID;
Select * from REAF_Technology_Updates order by installation, [IEP Pre Update];

Select Sum(REAF_Score_Improvement) as REAF_Score_Improvement from REAF_Technology_Updates
Select sum(Count_of_gaps_closed) as Count_of_gaps_closed from Strategy_Impact

Select Installation, Min([IEP Pre Update]) as Initial_Installation_IEP_Score , Max(Installation_IEP_Score) as Final_Installation_IEP_Score 
From REAF_Technology_Updates
Group by Installation
Order by Installation 
