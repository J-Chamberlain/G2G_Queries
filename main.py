import pandas as pd
from reaf_engine import REAFEngine

def main():
    # Loading data from SQL Tables folder
    print("Loading data sources...")
    try:
        data_sources = {
            'max_output': pd.read_csv('SQL Tables\\[MAX_output_for_SQL_2_24].csv'),
            'strategies': pd.read_csv('SQL Tables\\Strategies.csv'),
            'prelim_gaps': pd.read_csv('SQL Tables\\Power_Prelim_to_Library_gaps.csv'),
            'strat_tech_cost': pd.read_csv('SQL Tables\\Gap_Strat_Tech_Cost.csv'),
            'building_summary': pd.read_csv('SQL Tables\\Building_summary_data.csv')
        }
    except FileNotFoundError as e:
        print(f"Error: Source data files not found. {e}")
        return

    # Initialize Engine
    engine = REAFEngine(data_sources)

    # 1. Refresh Tables
    print("Step 1: Refreshing Tables...")
    engine.refresh_tables()

    # Initial Run (All techs set to null)
    engine.generate_gap_closure_opportunities(
        tech_id=None,
        reaf_scale='Installation',
        scope_filter='%Installation%',
        min_rel=75,
        min_tech_rel=75,
        clear_data=True
    )

    # 2. Iterate through Technologies
    technologies = [
        (12, 'Microgrid')#,
      #  (7, 'Substations'),
      #  (14, 'Power Quality'),
      #  (11, 'Generator Reliability'),
      #  (15, 'Battery Energy Storage Systems (BESS)'),
      #  (4, 'Uptime Institute Data Center Site Infrastructure Tier Standard'),
      #  (10, 'Combustion Turbines (CT)'),
      #  (2, 'Reciprocating Internal Combustion Engines (RICE)'),
      #  (3, 'Solar Photovoltaic (PV)')
    ]

    for tech_id, tech_name in technologies:
        print(f"\nProcessing Technology: {tech_name} (ID: {tech_id})")
        
        # Execute for Installation level
        print(f"  -- Executing for Installation level")
        engine.generate_gap_closure_opportunities(
            tech_id=tech_id,
            reaf_scale='Installation',
            scope_filter='%Installation%',
            min_rel=75,
            min_tech_rel=75
        )
        
        # Execute for Building level
        print(f"  -- Executing for Building level")
        engine.generate_gap_closure_opportunities(
            tech_id=tech_id,
            reaf_scale='Building',
            scope_filter='%Installation%', # (This is 'Not Like' in SQL, need to adjust logic if needed)
            min_rel=75,
            min_tech_rel=75
        )
        
        # Update REAF Scores for this tech
        engine.update_reaf_scores(tech_name)

    # 3. Final Outputs
    print("\nProcessing Complete. Generating results...")
    
    # Export results
    engine.state['gap_closure_opportunities'].to_csv('Gap_Closure_Opportunities.csv', index=False)
    engine.state['strategy_impact_results'].to_csv('Strategy_Impact.csv', index=False)
    engine.state['technology_updates'].to_csv('REAF_Technology_Updates.csv', index=False)
    
    print("Files saved:")
    print("- Gap_Closure_Opportunities.csv")
    print("- Strategy_Impact.csv")
    print("- REAF_Technology_Updates.csv")

if __name__ == "__main__":
    main()
