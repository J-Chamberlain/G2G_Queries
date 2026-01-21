# G2G Queries - Gap to Gap Analysis Framework

## Overview

The Gap-to-Gap (G2G) Analysis Framework is a data-driven system for identifying optimal technology implementations to close infrastructure resilience gaps. It matches preliminary facility gaps with candidate technologies, evaluates strategic alignment, calculates implementation costs, and quantifies resilience score improvements.

**Use Case**: Strategic planning for infrastructure resilience initiatives where budget is constrained and technology selection must be optimized for maximum impact.

---

## Quick Start

### 1. Install Dependencies
```powershell
pip install -r requirements.txt
```

### 2. Prepare Input Data
Place CSV files in `data/raw/`:
- [MAX_output_for_SQL_2_24].csv
- Strategies.csv
- Power_Prelim_to_Library_gaps.csv
- Gap_Strat_Tech_Cost.csv
- Building_summary_data.csv

(See [docs/INPUT_GUIDE.md](docs/INPUT_GUIDE.md) for file specifications)

### 3. Run Analysis
```powershell
python main.py
```

### 4. Select Technologies
When prompted, choose which technologies to analyze:
```
Select technologies: 1,3,5
✓ Selected: Microgrid, Power Quality, Battery Energy Storage Systems (BESS)
```

### 5. View Results
Results saved to `data/processed/`:
- Gap_Closure_Opportunities.csv
- Strategy_Impact.csv
- REAF_Technology_Updates.csv

---

## Project Structure

```
G2G_Queries/
├── README.md                          # This file
├── config.yaml                        # Analysis configuration & parameters
├── requirements.txt                   # Python dependencies
├── .gitignore                         # Git ignore rules
│
├── src/                               # Source code
│   ├── __init__.py
│   ├── main.py                        # Main entry point
│   └── reaf_engine.py                 # REAF engine implementation
│
├── data/
│   ├── raw/                           # INPUT - Original CSV files
│   │   ├── [MAX_output_for_SQL_2_24].csv
│   │   ├── Strategies.csv
│   │   ├── Power_Prelim_to_Library_gaps.csv
│   │   ├── Gap_Strat_Tech_Cost.csv
│   │   └── Building_summary_data.csv
│   │
│   └── processed/                     # OUTPUT - Analysis results
│       ├── Gap_Closure_Opportunities.csv
│       ├── Strategy_Impact.csv
│       └── REAF_Technology_Updates.csv
│
├── sql/                               # SQL scripts (reference)
│   ├── RefreshStrategyImpactTables.sql
│   ├── REAF_Impact_Calculation.sql
│   └── Gap_Closure_Function.sql
│
└── docs/                              # Documentation
    ├── METHODOLOGY.md                 # Analysis methodology
    └── INPUT_GUIDE.md                 # Input file specifications
```

---

## Configuration

Edit `config.yaml` to customize analysis parameters:

```yaml
analysis:
  min_relevancy_score: 75              # Min gap-strategy match (%)
  min_tech_relevancy_score: 75         # Min technology-strategy match (%)
```

Lower thresholds = more opportunities but may reduce quality
Higher thresholds = fewer, higher-quality opportunities

---

## Running the Analysis

### Interactive Technology Selection

```powershell
python main.py
```

**Selection Options:**
| Input | Result |
|-------|--------|
| `1` | Microgrid only |
| `1,3,5` | Microgrid, Power Quality, BESS |
| `all` | All 9 technologies + baseline |
| `skip` | Baseline analysis only |

### Available Technologies

1. Microgrid
2. Substations
3. Power Quality
4. Generator Reliability
5. Battery Energy Storage Systems (BESS)
6. Uptime Institute Data Center Site Infrastructure Tier Standard
7. Combustion Turbines (CT)
8. Reciprocating Internal Combustion Engines (RICE)
9. Solar Photovoltaic (PV)

---

## Understanding the Results

### Gap_Closure_Opportunities.csv
**What it shows**: Each viable gap + technology + strategy combination

**Key Columns:**
- `Installation`: Facility name
- `prelim_gap_id`: Gap identifier
- `Technology`: Proposed solution
- `Impact_Potential`: Expected resilience improvement
- `Combined_Relevency Score`: Suitability (0-100)
- `Cost Per Building Low/High`: Implementation cost estimate

**Use**: Identify specific gap closure projects with cost and impact metrics

---

### Strategy_Impact.csv
**What it shows**: Aggregated impact by strategy and technology

**Key Columns:**
- `Installation`: Facility name
- `Strategy`: Strategic approach
- `Technology`: Implementation technology
- `Gaps_Closed`: Number of gaps addressed
- `Avg_Cost_Low/High`: Average cost range
- `REAF_Scale`: Installation vs. Building level

**Use**: Compare strategies and technologies for portfolio decisions

---

### REAF_Technology_Updates.csv
**What it shows**: Resilience score improvements by technology

**Key Columns:**
- `Installation`: Facility name
- `Technology`: Implemented technology
- `Installation_IEP_Score` (pre/post): Resilience score change
- `REAF_Score_Improvement`: Net improvement

**Use**: Quantify resilience gains from technology investments

---

## Analysis Methodology

The analysis follows a five-step pipeline:

1. **Data Refresh**: Calculate baseline Mission Success Scores for all strategies
2. **Gap Analysis**: Match preliminary gaps to strategy-technology combinations
3. **Filtering**: Apply relevancy thresholds and scope constraints
4. **Optimization**: Select best technology per gap (max relevancy × impact)
5. **Score Update**: Recalculate resilience metrics after technology closure

See [docs/METHODOLOGY.md](docs/METHODOLOGY.md) for detailed explanation.

---

## Troubleshooting

### "FileNotFoundError: data/raw/..."
**Solution**: Ensure all five CSV files are in `data/raw/` folder with exact names

### "ValueError: could not convert string to float"
**Solution**: Check input files for non-numeric values in numeric columns

### Results are empty or incomplete
**Solution**: 
- Lower `min_relevancy_score` in `config.yaml` (currently 75%)
- Verify input data has strategies with positive impact potential
- Check that technologies have entries in Gap_Strat_Tech_Cost.csv

### Script runs very slowly
**Solution**:
- Running all 9 technologies is normal (5-15 min)
- Single technology should complete in 30-60 seconds
- Large files (100K+ rows) may require optimization

---

## Documentation

- **[METHODOLOGY.md](docs/METHODOLOGY.md)** - How the analysis works
- **[INPUT_GUIDE.md](docs/INPUT_GUIDE.md)** - Data file specifications & requirements
- **[config.yaml](config.yaml)** - Configurable parameters

---

## Requirements

- Python 3.12+
- pandas 2.1.4+
- numpy 1.26.3+
- PyYAML 6.0.1+

Install with: `pip install -r requirements.txt`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-21 | Initial release with full refactor |

---

## Support

For issues or questions:
1. Check [docs/](docs/) for detailed documentation
2. Verify input data with [docs/INPUT_GUIDE.md](docs/INPUT_GUIDE.md)
3. Review [docs/METHODOLOGY.md](docs/METHODOLOGY.md) for analysis details

---

## License

Internal Use Only - Booz Allen Hamilton