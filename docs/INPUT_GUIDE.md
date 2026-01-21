# Input Data Guide

This document describes the structure and requirements for all input CSV files used by the G2G analysis.

## File Locations
All input files must be placed in the `data/raw/` directory.

## Required Input Files

### 1. [MAX_output_for_SQL_2_24].csv
**Purpose**: Primary source data containing facility performance metrics and strategy effectiveness

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| Index_column | int | Unique row identifier |
| Installation_Cd | str | Facility code (e.g., "FTEV") |
| Installation | str | Facility name (e.g., "Hurlburt Field") |
| Strat_ID | int | Strategy identifier |
| Coverage | float | Current coverage score (0-100) |
| Adj_Weight | float | Adjustment weight for calculation |
| Min Value | float | Minimum threshold value |
| C1_App, C2_App, C3_App | float | Category contribution levels |
| Resilience Category | str | Category classification |
| Mission | str | Mission assignment |
| Status | str | Current status indicator |

**Requirements:**
- Must contain coverage values for MSS baseline calculation
- Adjustment weights must be non-zero for valid calculations
- All C1/C2/C3 values must be numeric (0 if not applicable)

---

### 2. Strategies.csv
**Purpose**: Defines all available strategies and their characteristics

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| S_ID | int | Strategy identifier (matches Strat_ID in MAX_output) |
| Strategy / Capability | str | Full strategy name/description |
| Scale | str | Implementation scale ("Installation" or "Building") |

**Requirements:**
- Every Strat_ID in MAX_output must have a corresponding S_ID
- Scale must be exactly "Installation" or "Building" (case-sensitive)
- No duplicate S_IDs

**Example:**
```
S_ID,Strategy / Capability,Scale
7,Substations,Installation
12,Microgrid,Installation
```

---

### 3. Power_Prelim_to_Library_gaps.csv
**Purpose**: Preliminary gap definitions linked to a gap library

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| prelim_gap_id | int | Preliminary gap identifier |
| gap_library_id | int | Gap library reference |
| prelim_gap_description | str | Gap description |
| gap_library_description | str | Standardized gap description |
| relevancy_score | float | Gap relevancy to resilience (0-100) |
| Installation_Cd | str | Facility code |
| Mission | str | Mission assignment |
| Mission or Installation Wide | str | Scope ("Mission" or "Installation") |
| Resource Category | str | Resource type (e.g., "Power") |

**Requirements:**
- Relevancy scores must be 0-100
- Installation_Cd must match Installation_Cd in other files
- Mission or Installation Wide must be exactly as specified
- All gap IDs must be unique

---

### 4. Gap_Strat_Tech_Cost.csv
**Purpose**: Maps gaps to strategies and technologies with relevancy and cost data

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| gap_id | int | Maps to gap_library_id |
| strategy_id | int | Maps to Strat_ID |
| technology_id | int | Technology identifier |
| Technology | str | Technology name |
| TechToStrat_relevancy_score | float | Tech-strategy alignment (0-100) |
| Cost Per Building Low ($) | float | Low-end implementation cost |
| Cost Per Building High ($) | float | High-end implementation cost |
| General Solution Description | str | Implementation approach |

**Requirements:**
- Technology IDs must be consistent (same ID = same technology)
- Relevancy scores must be 0-100
- Cost ranges must have Low ≤ High
- All gap_id values must exist in Power_Prelim_to_Library_gaps
- All strategy_id values must exist in Strategies

**Example:**
```
gap_id,strategy_id,technology_id,Technology,TechToStrat_relevancy_score,Cost Per Building Low ($),Cost Per Building High ($)
1,7,15,BESS,95.0,200000.0,450000.0
```

---

### 5. Building_summary_data.csv
**Purpose**: Installation-level context and summary information

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| Installation_Cd | str | Facility code (must match other files) |
| Installation | str | Facility name |
| [additional context columns] | various | Site-specific information |

**Requirements:**
- Every Installation_Cd in MAX_output must have an entry
- Installation names must match across all files
- No duplicate Installation_Cds

---

## Data Validation Checklist

Before running analysis, verify:

- [ ] All five CSV files present in `data/raw/`
- [ ] All file names match exactly (including brackets in [MAX_output_for_SQL_2_24].csv)
- [ ] No missing required columns in any file
- [ ] All numeric fields (coverage, relevancy, costs) are valid numbers
- [ ] No NaN/NULL values in critical columns
- [ ] Installation_Cd is consistent across all files
- [ ] Strat_ID/S_ID cross-reference is complete
- [ ] Technology IDs are consistent
- [ ] Relevancy scores are 0-100 range
- [ ] Cost ranges are valid (Low ≤ High)
- [ ] Scale values are exactly "Installation" or "Building"

## Common Issues & Solutions

### Issue: "FileNotFoundError: [MAX_output_for_SQL_2_24].csv"
**Solution**: Verify file name includes brackets exactly as shown. Windows is case-insensitive but name must be exact.

### Issue: "KeyError: 'Installation_Cd'"
**Solution**: Check that column names match exactly, including capitalization and spacing.

### Issue: "ValueError: could not convert string to float"
**Solution**: Ensure numeric columns contain only valid numbers, not text. Check for "N/A" or other non-numeric values.

### Issue: Results appear incomplete or empty
**Solution**: 
1. Verify relevancy threshold settings in `config.yaml`
2. Check that strategies have positive impact potential (MSS3 > current score)
3. Confirm technology-strategy relevancy scores meet thresholds

## Performance Considerations

- **File Size**: Tested with MAX_output files containing 50,000+ rows
- **Memory**: Requires ~1GB RAM for typical dataset sizes
- **Processing Time**: Single technology analysis typically completes in 30-60 seconds
- **All Technologies**: Full 9-technology analysis takes 5-15 minutes

## Data Update Procedure

To update analysis with new data:

1. Backup existing `data/raw/` folder
2. Export fresh CSV files from source database
3. Place new files in `data/raw/` (overwrite existing)
4. Verify all five files are present
5. Run `python main.py` and select desired technologies

All previous results in `data/processed/` will be overwritten on next run.
