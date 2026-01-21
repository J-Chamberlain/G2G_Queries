import pandas as pd
import yaml
import os
import sys

# Add src directory to path so we can import reaf_engine
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from reaf_engine import REAFEngine


def load_config():
    """Load configuration from config.yaml"""
    with open('config.yaml', 'r') as f:
        config = yaml.safe_load(f)
    return config


def select_technologies(config):
    """Interactive menu to select which technologies to run"""
    all_technologies = [(tech['id'], tech['name']) for tech in config['technologies']]
    
    print("\n" + "="*70)
    print("TECHNOLOGY SELECTOR")
    print("="*70)
    print("\nAvailable Technologies:")
    for idx, (tech_id, tech_name) in enumerate(all_technologies, 1):
        print(f"  {idx}. {tech_name} (ID: {tech_id})")
    
    print("\nOptions:")
    print("  Enter numbers separated by commas (e.g., '1,3,5')")
    print("  Enter 'all' to run all technologies")
    print("  Enter 'skip' to run no technologies (initial run only)")
    
    while True:
        user_input = input("\nSelect technologies: ").strip().lower()
        
        if user_input == 'all':
            return all_technologies
        elif user_input == 'skip':
            return []
        else:
            try:
                indices = [int(x.strip()) for x in user_input.split(',')]
                selected = [all_technologies[i-1] for i in indices if 1 <= i <= len(all_technologies)]
                if selected:
                    print(f"\n✓ Selected: {', '.join([name for _, name in selected])}")
                    return selected
                else:
                    print("Invalid selection. Please try again.")
            except (ValueError, IndexError):
                print("Invalid input. Please enter valid numbers separated by commas.")


def main():
    # Load configuration
    config = load_config()
    input_dir = config['paths']['input_dir']
    output_dir = config['paths']['output_dir']
    input_files = config['input_files']
    output_files = config['output_files']
    analysis = config['analysis']
    
    # Loading data from data/raw folder
    print("Loading data sources...")
    try:
        data_sources = {
            'max_output': pd.read_csv(os.path.join(input_dir, input_files['max_output'])),
            'strategies': pd.read_csv(os.path.join(input_dir, input_files['strategies'])),
            'prelim_gaps': pd.read_csv(os.path.join(input_dir, input_files['prelim_gaps'])),
            'strat_tech_cost': pd.read_csv(os.path.join(input_dir, input_files['strat_tech_cost'])),
            'building_summary': pd.read_csv(os.path.join(input_dir, input_files['building_summary']))
        }
    except FileNotFoundError as e:
        print(f"Error: Source data files not found. {e}")
        print(f"Expected files in: {input_dir}/")
        return

    # Initialize Engine
    engine = REAFEngine(data_sources)

    # 1. Refresh Tables
    print("Step 1: Refreshing Tables...")
    engine.refresh_tables()

    # 2. Get user technology selection BEFORE initial run
    technologies = select_technologies(config)
    
    # Only run the initial baseline (all techs) if user selected ALL technologies
    # Otherwise skip it to avoid processing unwanted technologies
    if len(technologies) == len(config['technologies']):  # All technologies selected
        print("\nRunning initial baseline analysis (all technologies)...")
        engine.generate_gap_closure_opportunities(
            tech_id=None,
            reaf_scale='Installation',
            scope_filter='%Installation%',
            min_rel=analysis['min_relevancy_score'],
            min_tech_rel=analysis['min_tech_relevancy_score'],
            clear_data=True
        )
    else:
        # For subset selection, clear the state manually
        engine.state['gap_closure_opportunities'] = pd.DataFrame()
        engine.state['strategy_impact_results'] = pd.DataFrame()
        engine.state['row_counters'] = {'Gap_Closure_Opportunities': 0, 'Strategy_Impact': 0}
    
    if not technologies:
        print("\nNo technologies selected. Skipping technology-specific analysis.")
    else:
        print(f"\nProcessing {len(technologies)} technology(ies)...")
        
        for tech_id, tech_name in technologies:
            print(f"\nProcessing Technology: {tech_name} (ID: {tech_id})")
            
            # Execute for Installation level
            print(f"  -- Executing for Installation level")
            engine.generate_gap_closure_opportunities(
                tech_id=tech_id,
                reaf_scale='Installation',
                scope_filter='%Installation%',
                min_rel=analysis['min_relevancy_score'],
                min_tech_rel=analysis['min_tech_relevancy_score']
            )
            
            # Execute for Building level
            print(f"  -- Executing for Building level")
            engine.generate_gap_closure_opportunities(
                tech_id=tech_id,
                reaf_scale='Building',
                scope_filter='%Installation%',
                min_rel=analysis['min_relevancy_score'],
                min_tech_rel=analysis['min_tech_relevancy_score']
            )
            
            # Update REAF Scores for this tech
            engine.update_reaf_scores(tech_name)

    # 3. Final Outputs
    print("\nProcessing Complete. Generating results...")
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Export results
    engine.state['gap_closure_opportunities'].to_csv(
        os.path.join(output_dir, output_files['gap_closure_opportunities']), 
        index=False
    )
    engine.state['strategy_impact_results'].to_csv(
        os.path.join(output_dir, output_files['strategy_impact']), 
        index=False
    )
    engine.state['technology_updates'].to_csv(
        os.path.join(output_dir, output_files['technology_updates']), 
        index=False
    )
    
    print("Files saved:")
    print(f"  - {output_dir}/{output_files['gap_closure_opportunities']}")
    print(f"  - {output_dir}/{output_files['strategy_impact']}")
    print(f"  - {output_dir}/{output_files['technology_updates']}")

if __name__ == "__main__":
    main()
