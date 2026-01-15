import pandas as pd
import numpy as np
from typing import Optional, List, Dict

class REAFEngine:
    def __init__(self, data_sources: Dict[str, pd.DataFrame]):
        """
        Initializes the REAF Engine with the required dataframes.
        
        Required keys in data_sources:
        - 'max_output': Source data (MAX_output_for_SQL_2_24)
        - 'strategies': Strategy definition table
        - 'prelim_gaps': Preliminary gaps table (Power_Prelim_to_Library_gaps)
        - 'strat_tech_cost': Mapping table (Gap_Strat_Tech_Cost)
        - 'building_summary': Context data (Building_summary_data)
        """
        self.data = {k: v.copy() for k, v in data_sources.items()}
        
        # Internal state tables that will be updated
        self.state = {
            'updated_mss_by_strategy': None,
            'strategy_impact_by_installation': None,
            'prelim_gaps_working': None,
            'updated_scores': None,
            'gap_closure_opportunities': pd.DataFrame(),
            'strategy_impact_results': pd.DataFrame(),
            'technology_updates': pd.DataFrame(),
            'row_counters': {'Gap_Closure_Opportunities': 0, 'Strategy_Impact': 0}
        }

    def refresh_tables(self):
        """Replicates RefreshStrategyImpactTables"""
        df_max = self.data['max_output']
        
        # STEP 1: Calculate Initial Mission Success Scores (MSS) per Strategy
        # MSS1: Coverage + C1 Contribution
        df_max['MSS1_val'] = df_max.apply(lambda r: (r['Coverage'] + r['C1_App'] / 3.0) if r['C1_App'] != 0 else r['Coverage'], axis=1)
        # MSS2: Coverage + C1 or C2
        df_max['MSS2_val'] = df_max.apply(lambda r: (r['Coverage'] + r['C1_App'] / 3.0) if r['C1_App'] != 0 
                                          else (r['Coverage'] + r['C2_App'] / 3.0) if r['C2_App'] != 0 
                                          else r['Coverage'], axis=1)
        # MSS3: Coverage + C1, C2, or C3
        df_max['MSS3_val'] = df_max.apply(lambda r: (r['Coverage'] + r['C3_App'] / 3.0) if r['C3_App'] != 0 
                                          else (r['Coverage'] + r['C2_App'] / 3.0) if r['C2_App'] != 0 
                                          else (r['Coverage'] + r['C1_App'] / 3.0) if r['C1_App'] != 0 
                                          else r['Coverage'], axis=1)

        grouped = df_max.groupby(['Installation_Cd', 'Installation', 'Mission', 'Strat_ID', 'Resilience Category'])
        
        mss_by_strategy = grouped.apply(lambda x: pd.Series({
            'R_m_IEP_Score': 100 * (x['Adj_Weight'] * x['Coverage'] / x['Min Value']).sum(),
            'MSS1': 100 * (x['Adj_Weight'] * x['MSS1_val'] / x['Min Value']).sum(),
            'MSS2': 100 * (x['Adj_Weight'] * x['MSS2_val'] / x['Min Value']).sum(),
            'MSS3': 100 * (x['Adj_Weight'] * x['MSS3_val'] / x['Min Value']).sum()
        })).reset_index()

        self.state['updated_mss_by_strategy'] = mss_by_strategy.copy()
        self.state['updated_mss_by_strategy']['Gaps_Closed'] = None
        self.state['updated_mss_by_strategy']['Count_of_gaps_closed'] = 0

        # STEP 2 & 3: Strategy Impact Calculations
        strategies = self.data['strategies']
        impact_by_mission = mss_by_strategy.merge(strategies[['S_ID', 'Strategy / Capability', 'Scale']], left_on='Strat_ID', right_on='S_ID')
        impact_by_mission['Delta_uncapped'] = impact_by_mission['MSS3'] - impact_by_mission['R_m_IEP_Score']
        # Note: SQL filters Delta_uncapped > 0
        impact_by_mission = impact_by_mission[impact_by_mission['Delta_uncapped'] > 0]

        building_summary = self.data['building_summary']
        impact_by_installation = impact_by_mission.groupby(['Installation_Cd', 'Installation', 'Strat_ID', 'Strategy / Capability', 'Scale']).agg({
            'Delta_uncapped': 'sum',
            'MSS3': 'sum'
        }).reset_index()
        
        impact_by_installation.rename(columns={'Delta_uncapped': 'Impact_Potential'}, inplace=True)
        impact_by_installation['% Impact_Potential'] = impact_by_installation['Impact_Potential'] / (impact_by_installation['MSS3'].replace(0, np.nan))
        impact_by_installation['% Impact_Potential'] = impact_by_installation['% Impact_Potential'].fillna(0)
        
        impact_by_installation = impact_by_installation.merge(building_summary, on='Installation_Cd')

        self.state['strategy_impact_by_installation'] = impact_by_installation
        self.state['prelim_gaps_working'] = self.data['prelim_gaps'].copy()
        
        # Initial score roll-up
        self._calculate_scores()

    def _calculate_scores(self):
        """Helper to calculate rolling scores (replicates roll-up logic)"""
        mss_detailed = self.state['updated_mss_by_strategy']
        
        # Step 5: Roll up to Mission/Category
        mss_scores = mss_detailed.groupby(['Installation_Cd', 'Installation', 'Mission', 'Resilience Category']).agg({
            'R_m_IEP_Score': 'sum',
            'MSS1': 'sum',
            'MSS2': 'sum',
            'MSS3': 'sum'
        }).reset_index()

        for col in ['R_m_IEP_Score', 'MSS1', 'MSS2', 'MSS3']:
            mss_scores[f'{col}_Capped'] = mss_scores[col].clip(upper=100)

        # Step 6: Mission Roll-up (Avg of capped categories)
        mission_scores = mss_scores.groupby(['Installation_Cd', 'Installation', 'Mission'])['R_m_IEP_Score_Capped'].mean().reset_index()
        mission_scores.rename(columns={'R_m_IEP_Score_Capped': 'Mission_IEP_Score'}, inplace=True)

        # Step 7: Installation Category Roll-up (Avg uncapped, then cap)
        inst_category_scores = mss_scores.groupby(['Installation_Cd', 'Installation', 'Resilience Category'])['R_m_IEP_Score'].mean().reset_index()
        inst_category_scores['Installation_level_R_Score'] = inst_category_scores['R_m_IEP_Score'].clip(upper=100)

        # Step 8: Final Installation Score (Avg of capped category scores)
        # SQL logic: SELECT DISTINCT installation, resilience category, installation_level_R_score FROM #TT3, then average
        final_scores = inst_category_scores.groupby(['Installation_Cd', 'Installation'])['Installation_level_R_Score'].mean().reset_index()
        final_scores.rename(columns={'Installation_level_R_Score': 'Installation_IEP_Score'}, inplace=True)

        # Combine into updated_scores state
        self.state['updated_scores'] = inst_category_scores.merge(mission_scores, on=['Installation_Cd', 'Installation']).merge(final_scores, on=['Installation_Cd', 'Installation'])

    def generate_gap_closure_opportunities(self, tech_id, reaf_scale, scope_filter, min_rel, min_tech_rel, clear_data=False):
        """Replicates GenerateGapClosureOpportunities"""
        if clear_data:
            self.state['gap_closure_opportunities'] = pd.DataFrame()
            self.state['strategy_impact_results'] = pd.DataFrame()
            self.state['row_counters'] = {'Gap_Closure_Opportunities': 0, 'Strategy_Impact': 0}

        p = self.state['prelim_gaps_working']
        c = self.data['strat_tech_cost']
        s = self.state['strategy_impact_by_installation']

        # Join p -> c (gaps to tech/strat) -> s (installation impact)
        merged = p.merge(c, left_on='gap_library_id', right_on='gap_id')
        merged = merged.merge(s, left_on=['strategy_id', 'Installation_Cd'], right_on=['Strat_ID', 'Installation_Cd'], suffixes=('_p', '_s'))

        # Filtering
        if tech_id is not None:
            merged = merged[merged['technology_id'] == tech_id]
        
        merged = merged[merged['Scale'] == reaf_scale] # Scale from strategy impact
        # Scope filter logic (LIKE '%Installation%')
        if scope_filter and '%' in scope_filter:
            pattern = scope_filter.replace('%', '.*')
            merged = merged[merged['Mission or Installation Wide'].str.contains(pattern, na=False, regex=True)]
        
        merged['Combined_Relevency Score'] = merged['relevancy_score'] * merged['TechToStrat_relevancy_score'] / 100
        merged = merged[(merged['relevancy_score'] >= min_rel) & (merged['TechToStrat_relevancy_score'] >= min_tech_rel)]

        if merged.empty:
            return

        # Two-Step Optimization
        # 1. Max Relevancy per Installation/Gap
        max_rel = merged.groupby(['Installation_Cd', 'prelim_gap_id'])['Combined_Relevency Score'].max().reset_index()
        merged = merged.merge(max_rel, on=['Installation_Cd', 'prelim_gap_id', 'Combined_Relevency Score'])

        # 2. Max Impact Potential among best relevancy
        max_impact = merged.groupby(['Installation_Cd', 'prelim_gap_id', 'Combined_Relevency Score'])['Impact_Potential'].max().reset_index()
        winners = merged.merge(max_impact, on=['Installation_Cd', 'prelim_gap_id', 'Combined_Relevency Score', 'Impact_Potential'])

        winners = winners[winners['Impact_Potential'] > 0]
        if winners.empty:
            return

        # Assign Row IDs
        start_id = self.state['row_counters']['Gap_Closure_Opportunities']
        winners['Row_ID'] = range(start_id + 1, start_id + len(winners) + 1)
        self.state['row_counters']['Gap_Closure_Opportunities'] += len(winners)

        # Persist results
        self.state['gap_closure_opportunities'] = pd.concat([self.state['gap_closure_opportunities'], winners])

        # Aggregate Strategy Impact
        strat_impact = winners.groupby(['Installation_Cd', 'Installation', 'strategy_id', 'Strategy / Capability', 'Impact_Potential', 'technology_id', 'Technology', 'Scale', 'Mission or Installation Wide']).agg({
            'Cost Per Building Low ($)': 'mean',
            'Cost Per Building High ($)': 'mean',
            'prelim_gap_id': [lambda x: '; '.join(x.astype(str)), 'count']
        }).reset_index()
        
        strat_impact.columns = ['Installation_Cd', 'Installation', 'Strategy_id', 'Strategy', 'Impact_Potential', 'Technology_id', 'Technology', 'REAF_Scale', 'PMR Gaps Scale', 'Avg_Cost_Low', 'Avg_Cost_High', 'Gaps_Closed', 'Count_of_gaps_closed']
        
        start_strat_id = self.state['row_counters']['Strategy_Impact']
        strat_impact['Row_ID'] = range(start_strat_id + 1, start_strat_id + len(strat_impact) + 1)
        self.state['row_counters']['Strategy_Impact'] += len(strat_impact)
        
        self.state['strategy_impact_results'] = pd.concat([self.state['strategy_impact_results'], strat_impact])

        # MUTATION: Update state for next iterative step
        # 1. Remove closed gaps from working set
        closed_ids = winners['prelim_gap_id'].unique()
        self.state['prelim_gaps_working'] = self.state['prelim_gaps_working'][~self.state['prelim_gaps_working']['prelim_gap_id'].isin(closed_ids)]

        # 2. Reduce impact potential in installation table
        # SQL logic: UPDATE R SET R.Impact_Potential = R.Impact_Potential - s.Impact_Potential
        # We need to be careful with double counting if multiple gaps share a strategy
        deduped_winners = winners[['Installation_Cd', 'strategy_id', 'Impact_Potential']].drop_duplicates()
        for _, row in deduped_winners.iterrows():
            self.state['strategy_impact_by_installation'].loc[
                (self.state['strategy_impact_by_installation']['Installation_Cd'] == row['Installation_Cd']) &
                (self.state['strategy_impact_by_installation']['Strat_ID'] == row['strategy_id']),
                'Impact_Potential'
            ] -= row['Impact_Potential']

    def update_reaf_scores(self, technology_name):
        """Replicates UpdateREAFScores"""
        # Step 1: Update strategy-specific scores based on closures
        impact = self.state['strategy_impact_results']
        impact_tech = impact[impact['Technology'] == technology_name]
        
        mss = self.state['updated_mss_by_strategy']
        
        # Merge closures into MSS
        for _, row in impact_tech.iterrows():
            mask = (mss['Installation_Cd'] == row['Installation_Cd']) & (mss['Strat_ID'] == row['Strategy_id'])
            mss.loc[mask, 'R_m_IEP_Score'] = mss.loc[mask, 'MSS3']
            mss.loc[mask, 'MSS2'] = mss.loc[mask, 'MSS3']
            mss.loc[mask, 'MSS1'] = mss.loc[mask, 'MSS3']
            mss.loc[mask, 'Gaps_Closed'] = row['Gaps_Closed']
            mss.loc[mask, 'Count_of_gaps_closed'] = row['Count_of_gaps_closed']

        # Capture pre-update scores
        if self.state['updated_scores'] is not None:
            pre_update = self.state['updated_scores'][['Installation_Cd', 'Installation_IEP_Score']].drop_duplicates()
        else:
            pre_update = pd.DataFrame()

        # Recalculate everything
        self._calculate_scores()
        
        # Track improvements
        post_update = self.state['updated_scores'][['Installation_Cd', 'Installation', 'Installation_IEP_Score']].drop_duplicates()
        if not pre_update.empty:
            improvement = post_update.merge(pre_update, on='Installation_Cd', suffixes=('', '_pre'))
            improvement['REAF_Score_Improvement'] = improvement['Installation_IEP_Score'] - improvement['Installation_IEP_Score_pre']
            improvement['Technology'] = technology_name
            self.state['technology_updates'] = pd.concat([self.state['technology_updates'], improvement])
        
        return post_update
