# G2G Analysis Methodology

## Overview
The Gap-to-Gap (G2G) analysis framework identifies optimal technology implementations to close infrastructure resilience gaps. The analysis matches preliminary gaps with candidate technologies, evaluates their strategic alignment, and calculates resilience score improvements.

## Analysis Pipeline

### 1. Data Preparation
- **Input**: Raw CSV files containing gap, strategy, and technology data
- **Process**: Load and validate input data, initialize REAF engine state
- **Output**: Normalized data ready for analysis

### 2. Table Refresh (RefreshStrategyImpactTables)
Calculates baseline Mission Success Scores (MSS) for each strategy:

**MSS Calculations:**
- **MSS1**: Coverage + C1 Contribution (if any)
- **MSS2**: Coverage + max(C1, C2) Contribution
- **MSS3**: Coverage + max(C1, C2, C3) Contribution (full potential)

**Roll-up Chain:**
1. Strategy-level MSS → Weighted by Adj_Weight / Min_Value
2. Group by Installation + Mission + Resilience Category
3. Calculate Impact_Potential = MSS3 - Current_Score
4. Filter for positive impact (MSS3 > R_m_IEP_Score)

### 3. Technology Selection
User interactively selects which technologies to analyze:
- Single: `1` (Microgrid only)
- Multiple: `1,3,5` (specific technologies)
- All: `all` (complete analysis)
- Baseline: `skip` (initial analysis only)

### 4. Gap Closure Opportunity Generation

For each selected technology at each scale (Installation/Building):

#### Step A: Data Merge
Combine:
- Preliminary gaps (with relevancy scores)
- Technology-Strategy mappings (with costs and relevancy)
- Strategy impact by installation (with impact potential)

#### Step B: Filtering
Apply constraints:
- Technology ID matches (if specified)
- REAF Scale matches (Installation or Building)
- Scope filter matches (Mission or Installation-wide)
- Relevancy thresholds:
  - Gap-to-Strategy ≥ min_relevancy_score (default: 75%)
  - Technology-to-Strategy ≥ min_tech_relevancy_score (default: 75%)

#### Step C: Two-Step Optimization
1. **Max Relevancy**: For each installation-gap pair, select the strategy with highest combined relevancy score
   - Combined_Relevency = (Gap_Relevancy × Tech_Relevancy) / 100
2. **Max Impact**: Among remaining candidates, select the option with highest impact potential

#### Step D: Result Persistence
- Add Row_ID and track counts
- Concatenate to gap_closure_opportunities results
- Update strategy impact aggregate

#### Step E: State Mutation (for next iteration)
- Remove closed gaps from working set
- Reduce impact potential for affected strategies
- Prevents double-counting in iterative analysis

### 5. REAF Score Updates (UpdateREAFScores)

After each technology iteration:

1. **Update MSS scores** for affected strategies:
   - Set R_m_IEP_Score = MSS3 (fully realized potential)
   - Set MSS1, MSS2 = MSS3 (no further improvement possible)
   - Record gaps closed and count

2. **Recalculate roll-ups:**
   - Mission/Category level scores
   - Installation-level scores
   - Track improvements vs. baseline

3. **Capture improvement metrics:**
   - Pre-update Installation_IEP_Score
   - Post-update Installation_IEP_Score
   - Calculate REAF_Score_Improvement
   - Attribute to technology

## Analysis Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `min_relevancy_score` | 75 | Minimum gap-strategy relevancy (%) |
| `min_tech_relevancy_score` | 75 | Minimum technology-strategy relevancy (%) |

Adjust in `config.yaml` to change analysis sensitivity.

## Output Interpretation

### Gap_Closure_Opportunities.csv
Detailed record of each viable gap-technology-strategy match:
- **Installation_Cd, Installation**: Facility identification
- **prelim_gap_id, gap_library_id**: Gap reference
- **strategy_id, Strategy / Capability**: Strategy reference
- **technology_id, Technology**: Technology reference
- **Impact_Potential**: Resilience improvement value
- **Combined_Relevency Score**: Suitability metric (0-100)
- **Cost Per Building Low/High**: Implementation cost estimate

### Strategy_Impact.csv
Aggregated technology impact by strategy and installation:
- Installation and strategy combination
- Total gap count addressed
- Average implementation cost range
- REAF scale (Installation or Building level)
- Row_ID for result tracking

### REAF_Technology_Updates.csv
Resilience score improvements by technology:
- Installation identification
- Technology implemented
- Pre-implementation Installation_IEP_Score
- Post-implementation Installation_IEP_Score
- **REAF_Score_Improvement**: Net gain in resilience

## Key Assumptions

1. **State Mutations Are Sequential**: Each technology iteration modifies state for the next, preventing double-counting
2. **Relevancy Is Multiplicative**: Combined relevancy = (Gap_Rel × Tech_Rel) / 100
3. **MSS3 Represents Full Potential**: Once gaps closed, maximum possible score is reached
4. **Installation Level Analysis First**: Building-level results are secondary
5. **Cost Estimates Are Averages**: Per-building costs averaged across installations

## Limitations & Considerations

- **Data Quality**: Results depend on quality of input relevancy scores
- **Cost Variability**: Implementation costs averaged; actual may vary by site
- **Technology Interdependencies**: Current model treats technologies independently
- **Scalability**: Large datasets may require optimization for performance
- **Geographic Specificity**: Costs and feasibility may vary by region

## Future Enhancements

- Technology portfolio optimization (select best combinations)
- Budget constraint optimization
- Technology deployment sequencing
- Geographic cost adjustment factors
- Scenario analysis (what-if modeling)
