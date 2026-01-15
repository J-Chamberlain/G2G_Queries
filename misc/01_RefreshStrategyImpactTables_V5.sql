CREATE OR ALTER PROCEDURE RefreshStrategyImpactTables
AS
/*****************************************************************************************************************
* PROCEDURE: RefreshStrategyImpactTables
* PURPOSE:   Refreshes several tables related to strategy impact and REAF scores based on MAX Model output data.
* This includes calculating initial scores at various levels (strategy, mission, installation)
* and preparing tables for subsequent updates based on gap closures.
* TABLES CREATED/MODIFIED:
* - REAF_Initial_MSS_Scores_by_Strategy (DROP/CREATE)
* - Strategy_Impact_by_mission_r (DROP/CREATE)
* - Strategy_Impact_by_installation (DROP/CREATE)
* - Power_Prelim_to_Library_gaps_copy (DROP/CREATE)
* - REAF_Initial_MSS_Scores (DROP/CREATE)
* - REAF_Updated_MSS_Scores (DROP/CREATE)
* - REAF_Initial_Scores (DROP/CREATE)
* - REAF_Updated_Scores (DROP/CREATE)
* NOTES:     Uses temporary tables (#TT2, #TT3) for intermediate calculations.
* AUTHOR:    [Josiah Chamberlain/CNA]
* DATE CREATED: [3/30/2025]
* MODIFICATION HISTORY:
* [Date] - [Author] - [Description of Change]
*****************************************************************************************************************/

BEGIN
    -- Suppress 'xx rows affected' messages for cleaner output and potentially minor performance gain
    SET NOCOUNT ON;

    PRINT 'Starting refresh of Strategy Impact and REAF Score tables...';

    ----------------------------------------------------------------------------------------------------
    -- STEP 1: Calculate Initial Mission Success Scores (MSS) per Strategy
    --         Aggregates raw data to get baseline and potential scores for each strategy/mission/category.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 1: Calculating initial MSS scores by strategy...';

    -- Drop existing intermediate table if it exists
    IF OBJECT_ID('dbo.REAF_Initial_MSS_Scores_by_Strategy', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Initial_MSS_Scores_by_Strategy;
        PRINT 'Dropped existing REAF_Initial_MSS_Scores_by_Strategy table.';
    END;

    -- Calculate baseline (R_m_IEP_Score) and potential scores (MSS1, MSS2, MSS3)
    SELECT
        Installation_cd,
        Installation,
        [Mission],
        Strat_ID,
        [Resilience Category],
        100 * SUM(Adj_weight * coverage / [Min Value]) AS R_m_IEP_Score,
        -- MSS1: Considers Coverage + C1 Contribution
        100 * SUM(CASE WHEN [C1_App] != 0 THEN (coverage + C1_App / 3.0) ELSE coverage END * Adj_weight / [Min Value]) AS MSS1,
        -- MSS2: Considers Coverage + C1 or C2 Contribution
        100 * SUM(CASE WHEN [C1_App] != 0 THEN (coverage + C1_App / 3.0) WHEN [C2_App] != 0 THEN (coverage + C2_App / 3.0) ELSE coverage END * Adj_weight / [Min Value]) AS MSS2,
        -- MSS3: Considers Coverage + C1, C2, or C3 Contribution (Highest Potential)
        100 * SUM(CASE WHEN [C3_App] != 0 THEN (coverage + C3_App / 3.0) WHEN [C2_App] != 0 THEN (coverage + C2_App / 3.0) WHEN [C1_App] != 0 THEN (coverage + C1_App / 3.0) ELSE coverage END * Adj_weight / [Min Value]) AS MSS3
    INTO dbo.REAF_Initial_MSS_Scores_by_Strategy
    FROM dbo.[MAX_output_for_SQL_2_24] -- Source data table
    GROUP BY
        Installation_cd,
        Installation,
        [Mission],
        Strat_ID,
        [Resilience Category]
    ORDER BY
        Installation,
        [Mission],
        Strat_ID,
        [Resilience Category];

    PRINT 'Created REAF_Initial_MSS_Scores_by_Strategy table.';

	----------------------------------------------------------------------------------------------------
    -- STEP 1.5: Create REAF_Updated_MSS_Scores_by_Strategy Table (Copy of Initial)
    --           This table will be modified later as gaps are closed.
    ----------------------------------------------------------------------------------------------------

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Updated_MSS_Scores_by_Strategy', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Updated_MSS_Scores_by_Strategy;
        PRINT 'Dropped existing REAF_Updated_MSS_Scores_by_Strategy table.';
    END;

    -- Create a direct copy of the initial scores table
    SELECT *, Cast(NULL as nvarchar(4000)) as [Gaps_Closed], Cast(NULL as int) as [Count_of_gaps_closed]
    INTO dbo.REAF_Updated_MSS_Scores_by_Strategy
    FROM dbo.REAF_Initial_MSS_Scores_by_Strategy;

    PRINT 'Created REAF_Updated_MSS_Scores_by_Strategy table (copy of initial).';

	
    ----------------------------------------------------------------------------------------------------
    -- STEP 2: Create Mission-Level Strategy Impact Table
    --         Joins strategy details and calculates the potential delta (improvement) from baseline.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 2: Creating mission-level strategy impact table (Strategy_Impact_by_mission_r)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.Strategy_Impact_by_mission_r', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.Strategy_Impact_by_mission_r;
        PRINT 'Dropped existing Strategy_Impact_by_mission_r table.';
    END;

    -- Aggregate impact metrics, join with Strategies table, calculate delta
    SELECT
        r.Installation_Cd,
        r.Installation,
        r.Mission,
        r.[Resilience Category],
        r.Strat_ID,
        s.[Strategy / Capability],
        s.[Scale],
        r.R_m_IEP_Score,            -- Baseline score for this strategy/mission/category
        r.MSS3,                     -- Max potential score (using C1, C2, or C3)
        r.MSS3 - r.R_m_IEP_Score AS Delta_uncapped -- Potential improvement
    INTO dbo.Strategy_Impact_by_mission_r
    FROM dbo.Strategies AS s
    INNER JOIN dbo.REAF_Initial_MSS_Scores_by_Strategy AS r
        ON s.S_ID = r.Strat_ID
    WHERE
        (r.MSS3 - r.R_m_IEP_Score) > 0 -- Only include strategies with potential positive impact
    ORDER BY
        r.Installation,
        s.[Strategy / Capability],
        r.[Resilience Category],
        r.Mission;

    DECLARE @MissionRowCount INT = @@ROWCOUNT;
    PRINT CONCAT('Created Strategy_Impact_by_mission_r table with ', @MissionRowCount, ' rows.');

    ----------------------------------------------------------------------------------------------------
    -- STEP 3: Create Installation-Level Strategy Impact Table
    --         Aggregates mission-level impacts to the installation level and joins facility data.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 3: Creating installation-level strategy impact table (Strategy_Impact_by_installation)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.Strategy_Impact_by_installation', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.Strategy_Impact_by_installation;
        PRINT 'Dropped existing Strategy_Impact_by_installation table.';
    END;

    -- Aggregate potential impact from mission level to installation level
    SELECT
        m.Installation_Cd,
        m.Installation,
        m.Strat_ID,
        m.[Strategy / Capability],
        m.[Scale],
        SUM(m.Delta_uncapped) AS Impact_Potential, -- Total score points potential increase
        -- Calculate percentage impact relative to the max potential score (MSS3)
        CASE WHEN SUM(m.MSS3) = 0 THEN 0 ELSE SUM(m.Delta_uncapped) / SUM(m.MSS3) END AS [% Impact_Potential],
        b.Million_BTU_FY24_AEPRR,
        b.Total_Facility_SF,
        b.Building_Count
    INTO dbo.Strategy_Impact_by_installation
    FROM dbo.Strategy_Impact_by_mission_r AS m
    -- Joining with PMR lists primarily to ensure alignment or potentially filter (using Installation_Cd)
    LEFT JOIN dbo.[PMR_Installation_Lists] AS p
        ON m.Installation_Cd = p.Installation_Cd -- Switched to Installation_Cd as per original code logic
    -- Joining with building summary data for additional context
    INNER JOIN dbo.Building_summary_data AS b
        ON m.Installation_Cd = b.Installation_Cd
    GROUP BY
        m.Installation_Cd,
        m.Installation,
        m.Strat_ID,
        m.[Strategy / Capability],
        m.[Scale],
        b.Million_BTU_FY24_AEPRR,
        b.Total_Facility_SF,
        b.Building_Count;

    DECLARE @InstallationRowCount INT = @@ROWCOUNT;
    PRINT CONCAT('Created Strategy_Impact_by_installation table with ', @InstallationRowCount, ' rows.');

    ----------------------------------------------------------------------------------------------------
    -- STEP 4: Create a Copy of the Preliminary Gaps Table
    --         Used for tracking changes or as a baseline before further processing.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 4: Creating a copy of the preliminary gaps table (Power_Prelim_to_Library_gaps_copy)...';

    DROP TABLE IF EXISTS dbo.Power_Prelim_to_Library_gaps_copy;

    SELECT *
    INTO dbo.Power_Prelim_to_Library_gaps_copy
    FROM dbo.Power_Prelim_to_Library_gaps;

    PRINT 'Created Power_Prelim_to_Library_gaps_copy table.';

    ----------------------------------------------------------------------------------------------------------------
    -- SECTION B: Calculate Initial REAF Scores (Baseline before Gap Closures)
    --            These steps roll up the strategy-level scores to mission and installation levels.
    ----------------------------------------------------------------------------------------------------------------
    PRINT 'SECTION B: Calculating Initial REAF Scores...';

    ----------------------------------------------------------------------------------------------------
    -- STEP 5: Build REAF_Initial_MSS_Scores (Mission/Resilience Category Level Aggregation)
    --         Aggregates scores from the strategy level (Step 1) to the mission/category level, applying capping at 100.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 5: Aggregating MSS scores to mission/resilience category level (REAF_Initial_MSS_Scores)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Initial_MSS_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Initial_MSS_Scores;
        PRINT 'Dropped existing REAF_Initial_MSS_Scores table.';
    END;

    -- Sum scores per mission/category and apply capping logic
    SELECT
        Installation_cd,
        Installation,
        [Mission],
        [Resilience Category],
        SUM(R_m_IEP_Score) AS R_m_IEP_Score,                       -- Uncapped baseline score sum
        CASE WHEN SUM(R_m_IEP_Score) > 100 THEN 100 ELSE SUM(R_m_IEP_Score) END AS R_m_IEP_Score_Capped, -- Capped baseline score
        SUM(MSS1) AS MSS1,                                         -- Uncapped MSS1 sum
        CASE WHEN SUM(MSS1) > 100 THEN 100 ELSE SUM(MSS1) END AS MSS1_Capped,               -- Capped MSS1
        SUM(MSS2) AS MSS2,                                         -- Uncapped MSS2 sum
        CASE WHEN SUM(MSS2) > 100 THEN 100 ELSE SUM(MSS2) END AS MSS2_Capped,               -- Capped MSS2
        SUM(MSS3) AS MSS3,                                         -- Uncapped MSS3 sum (Max Potential)
        CASE WHEN SUM(MSS3) > 100 THEN 100 ELSE SUM(MSS3) END AS MSS3_Capped                -- Capped MSS3
    INTO dbo.REAF_Initial_MSS_Scores
    FROM dbo.REAF_Initial_MSS_Scores_by_Strategy
    GROUP BY
        Installation_cd,
        Installation,
        [Mission],
        [Resilience Category]
    ORDER BY
        Installation,
        [Mission],
        [Resilience Category];

    PRINT 'Created REAF_Initial_MSS_Scores table.';

    ----------------------------------------------------------------------------------------------------
    -- STEP 5.5: Create REAF_Updated_MSS_Scores Table (Copy of Initial)
    --           This table will be modified later as gaps are hypothetically closed.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 5.5: Creating placeholder for updated MSS scores (REAF_Updated_MSS_Scores)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Updated_MSS_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Updated_MSS_Scores;
        PRINT 'Dropped existing REAF_Updated_MSS_Scores table.';
    END;

    -- Create a direct copy of the initial scores table
    SELECT *
    INTO dbo.REAF_Updated_MSS_Scores
    FROM dbo.REAF_Initial_MSS_Scores;

    PRINT 'Created REAF_Updated_MSS_Scores table (copy of initial).';

    ----------------------------------------------------------------------------------------------------
    -- STEP 6: Build #TT2 (Temporary Table: Mission Roll-up Scores)
    --         Calculates the average *capped* Resilience Category score for each Mission.
    --         IEP Score_m0 = Avg(Capped IEP Score_R1A,m0, Capped IEP Score_R1B,m0, ...)
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 6: Calculating mission-level average scores (using #TT2)...';

    -- Drop existing temp table if it exists
    IF OBJECT_ID('tempdb..#TT2', 'U') IS NOT NULL
        DROP TABLE #TT2;

    -- Calculate average capped score per mission and join back to the detailed data
    SELECT
        a.*,
        b.Mission_IEP_Score
    INTO #TT2
    FROM dbo.REAF_Initial_MSS_Scores AS a
    INNER JOIN (
        SELECT
            Installation,
            [Mission],
            --ROUND(AVG(R_m_IEP_Score_Capped), 0) AS Mission_IEP_Score -- Average of *capped* scores
			AVG(R_m_IEP_Score_Capped) AS Mission_IEP_Score 
        FROM dbo.REAF_Initial_MSS_Scores
        GROUP BY
            Installation,
            [Mission]
    ) AS b ON a.Installation = b.Installation AND a.Mission = b.Mission;

    PRINT 'Created temporary table #TT2 with mission-level scores.';

    ----------------------------------------------------------------------------------------------------
    -- STEP 7: Build #TT3 (Temporary Table: Installation Resilience Category Scores)
    --         Calculates the average *uncapped* score across all Missions for a specific Resilience Category
    --         within an Installation, then caps the result at 100.
    --         IEP Score_AvgR1A = MAX(Avg(IEP Score_R1A,m0, IEP Score_R1A,m1, ...), 100)
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 7: Calculating installation-level resilience category scores (using #TT3)...';

    -- Drop existing temp table if it exists
    IF OBJECT_ID('tempdb..#TT3', 'U') IS NOT NULL
        DROP TABLE #TT3;

    -- Calculate average *uncapped* score per Resilience Category across missions, then cap
    SELECT
        a.*,
        b.Installation_level_R_Score
    INTO #TT3
    FROM #TT2 AS a -- Use data from previous step (#TT2 includes Mission_IEP_Score)
    INNER JOIN (
        SELECT
            Installation,
            [Resilience Category],
            -- Average the *uncapped* mission scores for the category, then cap the average at 100
            --ROUND(CASE WHEN AVG(R_m_IEP_Score) > 100 THEN 100 ELSE AVG(R_m_IEP_Score) END, 0) AS Installation_level_R_Score
			CASE WHEN AVG(R_m_IEP_Score) > 100 THEN 100 ELSE AVG(R_m_IEP_Score) END AS Installation_level_R_Score
        FROM dbo.REAF_Initial_MSS_Scores -- Base calculation uses the uncapped mission/category scores
        GROUP BY
            Installation,
            [Resilience Category]
    ) AS b ON a.Installation = b.Installation AND a.[Resilience Category] = b.[Resilience Category];

    PRINT 'Created temporary table #TT3 with installation-level resilience category scores.';

    ----------------------------------------------------------------------------------------------------
    -- STEP 8: Build REAF_Initial_Scores (Final Installation Level Score)
    --         Calculates the overall Installation IEP score by averaging the
    --         Installation-level Resilience Category scores (calculated in Step 7), capping is inherent.
    --         Installation IEP Score = Avg(IEP Score_AvgR1A, IEP Score_AvgR1B, ...)
    --         Note: The source query averaged Installation_level_R_Score which was already capped.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 8: Calculating overall installation scores (REAF_Initial_Scores)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Initial_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Initial_Scores;
        PRINT 'Dropped existing REAF_Initial_Scores table.';
    END;

    -- Calculate the final installation score by averaging the capped installation-level R scores
    SELECT
        a.*,
        b.Installation_IEP_Score
    INTO dbo.REAF_Initial_Scores
    FROM #TT3 AS a -- Use data from previous step (#TT3 includes Mission & Installation R-Category scores)
    INNER JOIN (
        SELECT
            Installation,
            -- Average the already-calculated (and capped) Installation_level_R_Score values
            --ROUND(AVG(Installation_level_R_Score), 0) AS Installation_IEP_Score
			AVG(Installation_level_R_Score) AS Installation_IEP_Score
        FROM ( -- Subquery to get the distinct Installation_level_R_Score per Installation/Category
            SELECT DISTINCT
                 Installation,
                 [Resilience Category],
                 Installation_level_R_Score
            FROM #TT3
             ) AS n
        GROUP BY
            Installation
    ) AS b ON a.Installation = b.Installation;

    PRINT 'Created REAF_Initial_Scores table with overall installation scores.';

    ----------------------------------------------------------------------------------------------------
    -- STEP 8.5: Create REAF_Updated_Scores Table (Copy of Initial)
    --           This table will be modified later as gaps are hypothetically closed.
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 8.5: Creating placeholder for updated overall scores (REAF_Updated_Scores)...';

    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Updated_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Updated_Scores;
        PRINT 'Dropped existing REAF_Updated_Scores table.';
    END;

    -- Create a direct copy of the initial scores table
    SELECT *
    INTO dbo.REAF_Updated_Scores
    FROM dbo.REAF_Initial_Scores;

    PRINT 'Created REAF_Updated_Scores table (copy of initial).';

	   ----------------------------------------------------------------------------------------------------
    -- STEP 0: Create REAF_Technology_Updates Table 
    --           This table will be modified later as gaps are closed.
    ----------------------------------------------------------------------------------------------------

	  -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Technology_Updates', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Technology_Updates;
        PRINT 'Dropped existing REAF_Updated_MSS_Scores table.';
    END;

	 CREATE TABLE REAF_Technology_Updates (
                [Installation_Cd] NVARCHAR(50),
                [Installation] NVARCHAR(255),
				[IEP Pre Update] FLOAT,
				[Installation_IEP_Score] FLOAT,
				[REAF_Score_Improvement] FLOAT,
				[Technology] NVARCHAR(255) NULL
                );
    ----------------------------------------------------------------------------------------------------
    -- Cleanup Temporary Tables (optional but good practice)
    ----------------------------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#TT2', 'U') IS NOT NULL
        DROP TABLE #TT2;
    IF OBJECT_ID('tempdb..#TT3', 'U') IS NOT NULL
        DROP TABLE #TT3;

    PRINT 'Temporary tables dropped.';
    PRINT 'Strategy Impact and REAF Score tables refresh completed successfully.';

END;
GO

-- Example usage:
-- EXEC dbo.RefreshStrategyImpactTables;