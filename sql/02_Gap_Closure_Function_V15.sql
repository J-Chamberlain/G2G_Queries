

CREATE OR ALTER PROCEDURE GenerateGapClosureOpportunities
    @Technology_id INT,
	@REAF_Scale NVARCHAR(255),
    @PMRGapScopeFilter NVARCHAR(255),
    @PMRGapScopeFilterOperator NVARCHAR(10) = '=', -- Added parameter for operator
    @MinRelevancyScore INT,
    @MinTechToStratRelevancyScore INT,
    @ClearExistingData BIT = 0,
    @GenerateStrategyImpact BIT = 1    -- New parameter to control Strategy_Impact generation
AS
BEGIN
    SET NOCOUNT ON;    

     
	 -- Check if a row counter table exists, create it if it doesn't
	IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Row_Counter')
	BEGIN
		CREATE TABLE Row_Counter (
			Counter_Name NVARCHAR(50) PRIMARY KEY,
			Current_Value INT NOT NULL
		);
        
		-- Initialize counters
		INSERT INTO Row_Counter (Counter_Name, Current_Value) 
		VALUES ('Gap_Closure_Opportunities', 0), ('Strategy_Impact', 0);
        
		PRINT 'Row_Counter table has been created and initialized.';
	END 
    -- Option to clear the permanent table before starting
   
    IF @ClearExistingData = 1
    BEGIN
				
		-- Instead of truncating, we'll drop and recreate the table to ensure proper column order
        IF OBJECT_ID('Gap_Closure_Opportunities', 'U') IS NOT NULL
        BEGIN
            DROP TABLE Gap_Closure_Opportunities;
            PRINT 'Gap_Closure_Opportunities table has been dropped.';
            
            -- Reset the counter for Gap_Closure_Opportunities
            UPDATE Row_Counter SET Current_Value = 0 
            WHERE Counter_Name = 'Gap_Closure_Opportunities';
            PRINT 'Gap_Closure_Opportunities counter has been reset.';
        END
        
        -- Also clear Strategy_Impact if it exists
        IF OBJECT_ID('Strategy_Impact', 'U') IS NOT NULL
        BEGIN
            TRUNCATE TABLE Strategy_Impact;
            PRINT 'Strategy_Impact table has been cleared.';
            
            -- Reset the counter for Strategy_Impact
            UPDATE Row_Counter SET Current_Value = 0 
            WHERE Counter_Name = 'Strategy_Impact';
            PRINT 'Strategy_Impact counter has been reset.';
        END
    END

    -- Check if the permanent table exists, create it if it doesn't
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Gap_Closure_Opportunities')
    BEGIN
        CREATE TABLE Gap_Closure_Opportunities (
            [Row_ID] INT NOT NULL,             -- Now explicitly first column
            [installation(s)] NVARCHAR(255),
            [Installation_Cd] NVARCHAR(50),
            [Combined_Relevency Score] FLOAT,
            [prelim_gap_id] NVARCHAR(50),
            [Specific Problem Statement] NVARCHAR(MAX),
            [General Problem Statement] NVARCHAR(MAX),
            [Strategy_id] INT,
            [Strategy] NVARCHAR(MAX),
			[REAF_Scale] NVARCHAR(255),
            [Impact_Potential] FLOAT,
			[Technology_id] INT,
            [Technology] NVARCHAR(255),
            [PMR Gaps Scale] NVARCHAR(255),
            [Cost Per Building Low ($)] FLOAT,
            [Cost Per Building High ($)] FLOAT,
            [Cost Estimation Logic] NVARCHAR(MAX),
			[Gap_Or_Opportunity?] NVARCHAR(255)
        );
        PRINT 'Gap_Closure_Opportunities table has been created.';
    END
    
    -- Create temporary table for cross-reference impact
    DROP TABLE IF EXISTS #_Cross_reference_Impact_Installation;

    -- Join gap information with strategy impact data based on the provided parameters
    SELECT  
        p.[installation(s)],
        p.[Installation_Cd],
        p.relevancy_score * c.TechToStrat_relevancy_score / 100 AS [Combined_Relevency Score],
        p.prelim_gap_id,
        p.prelim_gap_description AS [Specific Problem Statement],
        p.gap_library_description AS [General Problem Statement],
        c.Strategy_id,
        c.[General Solution Description] AS Strategy,
        s.Impact_Potential,
		c.Technology_id,
        c.Technology,
		s.[Scale] as [REAF_Scale],
        p.[Mission or Installation Wide] as [PMR Gaps Scale],
        c.[Cost Per Building Low ($)],
        c.[Cost Per Building High ($)],
        c.[Cost Estimation Logic],
		p.[Gap_Or_Opportunity?]
    INTO #_Cross_reference_Impact_Installation
    FROM Power_Prelim_to_Library_gaps_copy p 
    INNER JOIN Gap_Strat_Tech_Cost c 
        ON p.gap_library_id = c.gap_id
    INNER JOIN Strategy_Impact_by_installation s 
        ON c.strategy_id = s.Strat_id
        AND p.[Installation_Cd] = s.[Installation_Cd]
    WHERE 
        c.Technology_id = @Technology_id
        AND ((@PMRGapScopeFilterOperator = '=' AND p.[Mission or Installation Wide] = @PMRGapScopeFilter)
             OR (@PMRGapScopeFilterOperator = '!=' AND p.[Mission or Installation Wide] != @PMRGapScopeFilter)
             OR (@PMRGapScopeFilterOperator = 'LIKE' AND p.[Mission or Installation Wide] LIKE @PMRGapScopeFilter)
             OR (@PMRGapScopeFilterOperator = 'NOT LIKE' AND p.[Mission or Installation Wide] NOT LIKE @PMRGapScopeFilter))
        AND p.relevancy_score >= @MinRelevancyScore
        AND c.TechToStrat_relevancy_score >= @MinTechToStratRelevancyScore   
		AND s.[Scale] = @REAF_Scale
	--	AND (p.[Gap_Or_Opportunity?] = 'Resilience Gap' or p.[Gap_Or_Opportunity?] is null) 
    ORDER BY 
        p.[installation(s)], 
        p.prelim_gap_id, 
        c.[General Solution Description], 
        p.relevancy_score DESC, 
        c.Technology;

    -- Create temporary table for distinct highest combined relevancy score
    DROP TABLE IF EXISTS #Distinct_Relevency_Score_Installation;

    -- Find the maximum combined relevancy score for each installation and gap
    SELECT 
        [installation(s)], 
        [Installation_Cd], 
        prelim_gap_id, 
        prelim_gap_description, 
        MAX([Combined_Relevency Score]) AS [Combined_Relevency Score]
    INTO #Distinct_Relevency_Score_Installation
    FROM (
        SELECT DISTINCT 
            p.[installation(s)],
            p.[Installation_Cd], 
            p.prelim_gap_id,
            p.prelim_gap_description, 
            p.relevancy_score * c.TechToStrat_relevancy_score / 100 AS [Combined_Relevency Score]
        FROM Power_Prelim_to_Library_gaps_copy p 
        INNER JOIN Gap_Strat_Tech_Cost c 
            ON p.gap_library_id = c.gap_id
        INNER JOIN Strategy_Impact_by_installation s 
            ON c.strategy_id = s.Strat_id
            AND p.[Installation_Cd] = s.[Installation_Cd]
        WHERE 
            c.Technology_id = @Technology_id 
            AND ((@PMRGapScopeFilterOperator = '=' AND p.[Mission or Installation Wide] = @PMRGapScopeFilter)
                 OR (@PMRGapScopeFilterOperator = '!=' AND p.[Mission or Installation Wide] != @PMRGapScopeFilter)
                 OR (@PMRGapScopeFilterOperator = 'LIKE' AND p.[Mission or Installation Wide] LIKE @PMRGapScopeFilter)
                 OR (@PMRGapScopeFilterOperator = 'NOT LIKE' AND p.[Mission or Installation Wide] NOT LIKE @PMRGapScopeFilter))
            AND p.relevancy_score >= @MinRelevancyScore
            AND c.TechToStrat_relevancy_score >= @MinTechToStratRelevancyScore
			AND s.[Scale] = @REAF_Scale
	--		AND (p.[Gap_Or_Opportunity?] = 'Resilience Gap' or p.[Gap_Or_Opportunity?] is null) 
		   ) n
			GROUP BY 
				[installation(s)], 
				[Installation_Cd], 
				prelim_gap_id, 
				prelim_gap_description;

    -- Create temporary table for maximum impact and relevancy
    DROP TABLE IF EXISTS #Max_impact_and_relevency;

    -- Select the maximum impact potential for each gap and relevancy score
    SELECT 
        c.[installation(s)],
        c.[Installation_Cd], 
        c.prelim_gap_id, 
        c.[Combined_Relevency Score], 
		c.[Gap_Or_Opportunity?],
        MAX(c.Impact_Potential) AS max_impact_potential
    INTO #Max_impact_and_relevency 
    FROM #_Cross_reference_Impact_Installation c 
    INNER JOIN #Distinct_Relevency_Score_Installation d 
        ON c.[Installation_Cd] = d.[Installation_Cd] 
        AND c.[Combined_Relevency Score] = d.[Combined_Relevency Score] 
        AND c.prelim_gap_id = d.prelim_gap_id
    GROUP BY 
        c.[installation(s)], 
        c.[Installation_Cd], 
        c.prelim_gap_id, 
        c.[Combined_Relevency Score],
		c.[Gap_Or_Opportunity?]
    ORDER BY 
        c.[installation(s)], 
        c.[Installation_Cd], 
        c.prelim_gap_id;

    -- Get current counter value for Gap_Closure_Opportunities
    DECLARE @CurrentGapCounter INT;
    SELECT @CurrentGapCounter = Current_Value FROM Row_Counter WHERE Counter_Name = 'Gap_Closure_Opportunities';

    -- Create a temporary table with row numbers
    DROP TABLE IF EXISTS #Numbered_Gap_Opportunities;
    
    SELECT 
        ROW_NUMBER() OVER (ORDER BY c.[installation(s)], c.prelim_gap_id) + @CurrentGapCounter AS Row_ID,
        c.*
    INTO #Numbered_Gap_Opportunities
    FROM #_Cross_reference_Impact_Installation c 
    INNER JOIN #Max_impact_and_relevency d 
        ON c.[Installation_Cd] = d.[Installation_Cd] 
        AND c.[Combined_Relevency Score] = d.[Combined_Relevency Score] 
        AND c.prelim_gap_id = d.prelim_gap_id 
        AND c.Impact_Potential = d.max_impact_potential
	Where c.Impact_Potential > 0 ;

    -- Insert records into the permanent table with row numbers
    INSERT INTO Gap_Closure_Opportunities ([Row_ID], [installation(s)], [Installation_Cd], [Combined_Relevency Score], 
                                          [prelim_gap_id], [Specific Problem Statement], [General Problem Statement], 
                                          [Strategy_id], [Strategy], [Impact_Potential],[Technology_id], [Technology], 
                                          [REAF_Scale],[PMR Gaps Scale], [Cost Per Building Low ($)], 
                                          [Cost Per Building High ($)], [Cost Estimation Logic], [Gap_Or_Opportunity?])
    SELECT Row_ID, [installation(s)], [Installation_Cd], [Combined_Relevency Score], 
           [prelim_gap_id], [Specific Problem Statement], [General Problem Statement], 
           [Strategy_id], [Strategy], [Impact_Potential],[Technology_id], [Technology], 
           [REAF_Scale],[PMR Gaps Scale], [Cost Per Building Low ($)], 
           [Cost Per Building High ($)], [Cost Estimation Logic], [Gap_Or_Opportunity?]
    FROM #Numbered_Gap_Opportunities;
        
    -- Return count of inserted records
    DECLARE @InsertedCount INT = @@ROWCOUNT;
    PRINT CONCAT('Added ', @InsertedCount, ' records to Gap_Closure_Opportunities table.');
    
    -- Update the counter
    UPDATE Row_Counter 
    SET Current_Value = Current_Value + @InsertedCount 
    WHERE Counter_Name = 'Gap_Closure_Opportunities';
    PRINT CONCAT('Gap_Closure_Opportunities counter updated to ', @CurrentGapCounter + @InsertedCount, '.');

	
	    -- Generate Strategy_Impact table
    IF @GenerateStrategyImpact = 1
    BEGIN
        IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Strategy_Impact')
        BEGIN
            CREATE TABLE Strategy_Impact (
                [Row_ID] INT NOT NULL,         -- Explicitly first column
                [Installation_Cd] NVARCHAR(50),
                [installation(s)] NVARCHAR(255),
                [Strategy_id] INT,
                [Strategy] NVARCHAR(MAX),
                [Impact_Potential] FLOAT,
				[Technology_id] INT, 
				[Technology] NVARCHAR(255),
				[REAF_Scale] NVARCHAR(255),
                [PMR Gaps Scale] NVARCHAR(255),
                [Avg Cost Per Building Low ($)] FLOAT,
                [Avg Cost Per Building High ($)] FLOAT,
                [Gaps_Closed] NVARCHAR(4000),
                [Count_of_gaps_closed] int,
				[Technology_REAF_Impact] FLOAT--,
				--[New REAF Score] FLOAT
            );
            PRINT 'Strategy_Impact table has been created.';
        END
   
           -- Get current counter value for Strategy_Impact
        DECLARE @CurrentStrategyCounter INT;
        SELECT @CurrentStrategyCounter = Current_Value FROM Row_Counter WHERE Counter_Name = 'Strategy_Impact';
        
        -- Add to Strategy_Impact table with Row_ID
        INSERT INTO Strategy_Impact
        SELECT 
            ROW_NUMBER() OVER (ORDER BY Installation_Cd, Strategy_id) + @CurrentStrategyCounter AS Row_ID,
			Installation_Cd, 
            [Installation(s)], 
            Strategy_id, 
            Strategy, 
            Impact_Potential,
			[Technology_id], 
			[Technology],
			[REAF_Scale],
            [PMR Gaps Scale],
            AVG([Cost Per Building Low ($)]) AS [Avg Cost Per Building Low ($)],
            AVG([Cost Per Building High ($)]) AS [Avg Cost Per Building High ($)],
            STRING_AGG(prelim_gap_id, '; ') AS Gaps_Closed,
            COUNT(*) AS Count_of_gaps_closed,
			CAST(0.0 as float) as [Technology_REAF_Impact]
        FROM #Numbered_Gap_Opportunities
        GROUP BY 
            Installation_Cd, 
            [Installation(s)], 
            Strategy_id, 
            Strategy, 
			[REAF_Scale],
            [PMR Gaps Scale],
            Impact_Potential,
			[Technology_id], 
			[Technology];
		
		-- Delete gaps that are closed 
		DELETE g
		FROM Power_Prelim_to_Library_gaps_copy g
		INNER JOIN #Numbered_Gap_Opportunities n 
			ON g.prelim_gap_id = n.prelim_gap_id;
		
		--Update Strategy_Impact_by_installation to subtract the potential impact that has been realized by closing the gaps. 
		UPDATE R
		SET R.Impact_Potential = R.Impact_Potential - s.Impact_Potential
		FROM Strategy_Impact_by_installation R
		INNER JOIN (Select Distinct Installation_Cd, Strategy_id, Impact_Potential FROM #Numbered_Gap_Opportunities) s
			ON R.Installation_Cd = s.Installation_Cd
			AND R.Strat_ID = s.Strategy_id;
		  
            
        DECLARE @StrategyImpactCount INT = @@ROWCOUNT;
        PRINT CONCAT('Added ', @StrategyImpactCount, ' records to Strategy_Impact table.');
        
        -- Update the counter
        UPDATE Row_Counter 
        SET Current_Value = Current_Value + @StrategyImpactCount 
        WHERE Counter_Name = 'Strategy_Impact';
        PRINT CONCAT('Strategy_Impact counter updated to ', @CurrentStrategyCounter + @StrategyImpactCount, '.');


    END
    


    -- Clean up temporary tables
    DROP TABLE IF EXISTS #_Cross_reference_Impact_Installation;
    DROP TABLE IF EXISTS #Distinct_Relevency_Score_Installation;
    DROP TABLE IF EXISTS #Max_impact_and_relevency;
    DROP TABLE IF EXISTS #Numbered_Gap_Opportunities;
	DROP TABLE IF EXISTS #Strategy_Impact_temp;
END
GO

-- Example usage:
-- EXEC GenerateGapClosureOpportunities 
--     @Technology_id = 'Microgrid', 
--     @PMRGapScopeFilter = 'Installation', 
--     @MinRelevancyScore = 75, 
--     @MinTechToStratRelevancyScore = 75,
--     @ClearExistingData = 1,
--     @GenerateStrategyImpact = 1;