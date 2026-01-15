CREATE OR ALTER PROCEDURE dbo.UpdateREAFScores
    @Technology NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT 'Starting REAF Scores update procedure for technology: ' + @Technology;
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 1: Update Strategy-specific scores based on the provided technology
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 1: Updating strategy-specific scores for ' + @Technology + '...';
    
    UPDATE s
    SET s.[R_m_IEP_Score] = s.[MSS3],
        s.[MSS2] = s.[MSS3],
        s.[MSS1] = s.[MSS3],
        s.[Gaps_Closed] = i.Gaps_Closed,
        s.[Count_of_gaps_closed] = i.[Count_of_gaps_closed]
    FROM REAF_Updated_MSS_Scores_by_Strategy s
    INNER JOIN [Strategy_Impact] i ON s.Installation_cd = i.Installation_Cd AND s.Strat_ID = i.Strategy_id 
    WHERE Technology = @Technology;
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 2: Create REAF_Updated_MSS_Scores
    --         Sum scores per mission/category and apply capping logic
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 2: Creating REAF_Updated_MSS_Scores table...';
    
    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Updated_MSS_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Updated_MSS_Scores;
        PRINT 'Dropped existing REAF_Updated_MSS_Scores table.';
    END;
    
    -- Sum scores per mission/category and apply capping logic
    SELECT
        Installation_cd,
        Installation,
        [Mission],
        [Resilience Category],
        SUM(R_m_IEP_Score) AS R_m_IEP_Score,                                        -- Uncapped baseline score sum
        CASE WHEN SUM(R_m_IEP_Score) > 100 THEN 100 ELSE SUM(R_m_IEP_Score) END AS R_m_IEP_Score_Capped, -- Capped baseline score
        SUM(MSS1) AS MSS1,                                                          -- Uncapped MSS1 sum
        CASE WHEN SUM(MSS1) > 100 THEN 100 ELSE SUM(MSS1) END AS MSS1_Capped,      -- Capped MSS1
        SUM(MSS2) AS MSS2,                                                          -- Uncapped MSS2 sum
        CASE WHEN SUM(MSS2) > 100 THEN 100 ELSE SUM(MSS2) END AS MSS2_Capped,      -- Capped MSS2
        SUM(MSS3) AS MSS3,                                                          -- Uncapped MSS3 sum (Max Potential)
        CASE WHEN SUM(MSS3) > 100 THEN 100 ELSE SUM(MSS3) END AS MSS3_Capped       -- Capped MSS3
    INTO dbo.REAF_Updated_MSS_Scores
    FROM dbo.REAF_Updated_MSS_Scores_by_Strategy
    GROUP BY
        Installation_cd,
        Installation,
        [Mission],
        [Resilience Category]
    ORDER BY
        Installation,
        [Mission],
        [Resilience Category];
    
    PRINT 'Created REAF_Updated_MSS_Scores table.';
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 3: Build #TT2 (Temporary Table: Mission Roll-up Scores)
    --         Calculates the average *capped* Resilience Category score for each Mission.
    --         IEP Score_m0 = Avg(Capped IEP Score_R1A,m0, Capped IEP Score_R1B,m0, ...)
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 3: Calculating mission-level average scores (using #TT2)...';
    
    -- Drop existing temp table if it exists
    IF OBJECT_ID('tempdb..#TT2', 'U') IS NOT NULL
        DROP TABLE #TT2;
    
    -- Calculate average capped score per mission and join back to the detailed data
    SELECT
        a.*,
        b.Mission_IEP_Score
    INTO #TT2
    FROM dbo.REAF_Updated_MSS_Scores AS a
    INNER JOIN (
        SELECT
            Installation,
            [Mission],
            ROUND(AVG(R_m_IEP_Score_Capped), 0) AS Mission_IEP_Score -- Average of *capped* scores
        FROM dbo.REAF_Updated_MSS_Scores
        GROUP BY
            Installation,
            [Mission]
    ) AS b ON a.Installation = b.Installation AND a.Mission = b.Mission;
    
    PRINT 'Created temporary table #TT2 with mission-level scores.';
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 4: Build #TT3 (Temporary Table: Installation Resilience Category Scores)
    --         Calculates the average *uncapped* score across all Missions for a specific Resilience Category
    --         within an Installation, then caps the result at 100.
    --         IEP Score_AvgR1A = MAX(Avg(IEP Score_R1A,m0, IEP Score_R1A,m1, ...), 100)
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 4: Calculating installation-level resilience category scores (using #TT3)...';
    
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
            ROUND(CASE WHEN AVG(R_m_IEP_Score) > 100 THEN 100 ELSE AVG(R_m_IEP_Score) END, 0) AS Installation_level_R_Score
        FROM dbo.REAF_Updated_MSS_Scores -- Base calculation uses the uncapped mission/category scores
        GROUP BY
            Installation,
            [Resilience Category]
    ) AS b ON a.Installation = b.Installation AND a.[Resilience Category] = b.[Resilience Category];
    
    PRINT 'Created temporary table #TT3 with installation-level resilience category scores.';
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 5: Save Pre-Update IEP Scores (for comparison)
    --         Stores the current IEP scores before updating for comparison purposes
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 5: Storing pre-update IEP scores for comparison...';
    
    -- Drop existing temp table if it exists
    IF OBJECT_ID('tempdb..#TT4', 'U') IS NOT NULL
        DROP TABLE #TT4;
    
    -- Store current IEP scores
    SELECT DISTINCT 
        Installation_cd, 
        Installation, 
        Installation_IEP_Score AS [IEP Pre Update]
    INTO #TT4
    FROM REAF_Updated_Scores;
    
    PRINT 'Created temporary table #TT4 with pre-update IEP scores.';
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 6: Build REAF_Updated_Scores (Final Installation Level Score)
    --         Calculates the overall Installation IEP score by averaging the
    --         Installation-level Resilience Category scores (calculated in Step 4)
    --         Installation IEP Score = Avg(IEP Score_AvgR1A, IEP Score_AvgR1B, ...)
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 6: Calculating overall installation scores (REAF_Updated_Scores)...';
    
    -- Drop existing table if it exists
    IF OBJECT_ID('dbo.REAF_Updated_Scores', 'U') IS NOT NULL
    BEGIN
        DROP TABLE dbo.REAF_Updated_Scores;
        PRINT 'Dropped existing REAF_Updated_Scores table.';
    END;
    
    -- Calculate the final installation score by averaging the capped installation-level R scores
    SELECT
        a.*,
        b.Installation_IEP_Score
    INTO dbo.REAF_Updated_Scores
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
    
    PRINT 'Created REAF_Updated_Scores table with overall installation scores.';
    
    ----------------------------------------------------------------------------------------------------
    -- STEP 7: Record Technology Updates
    --         Insert records into REAF_Technology_Updates to track improvements
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 7: Recording technology updates and improvements...';
    
    INSERT INTO REAF_Technology_Updates
    SELECT DISTINCT 
        u.Installation_cd, 
        u.Installation, 
        t.[IEP Pre Update], 
        u.Installation_IEP_Score, 
        u.Installation_IEP_Score - t.[IEP Pre Update] AS REAF_Score_Improvement, 
        @Technology AS [Technology]
    FROM REAF_Updated_Scores u 
    INNER JOIN #TT4 t ON u.Installation_cd = t.Installation_cd;
    
    PRINT 'Updated REAF_Technology_Updates with improvement scores.';

	----------------------------------------------------------------------------------------------------
    -- STEP 8: Record Technology Updates into Strategy_Impact
    ----------------------------------------------------------------------------------------------------

	Update S
	Set Technology_REAF_Impact = REAF_Score_Improvement
	FROM Strategy_Impact s inner join REAF_Technology_Updates r
		on s.Installation_Cd = r.Installation_Cd and s.Technology = r.Technology;
   
   
    ----------------------------------------------------------------------------------------------------
    -- STEP 9: Cleanup Temporary Tables
    ----------------------------------------------------------------------------------------------------
    PRINT 'Step 8: Cleaning up temporary tables...';
    
    IF OBJECT_ID('tempdb..#TT2', 'U') IS NOT NULL
        DROP TABLE #TT2;
    IF OBJECT_ID('tempdb..#TT3', 'U') IS NOT NULL
        DROP TABLE #TT3;
    IF OBJECT_ID('tempdb..#TT4', 'U') IS NOT NULL
        DROP TABLE #TT4;
    
    PRINT 'Temporary tables dropped.';
    PRINT 'Strategy Impact and REAF Score update for technology ' + @Technology + ' completed successfully.';
END