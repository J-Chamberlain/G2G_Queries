# GenerateGapClosureOpportunities – SQL Explanation

## Overview

`GenerateGapClosureOpportunities` is a stored procedure that identifies and persists the **highest-value strategy and technology combinations** for closing PMR gaps at specific installations. It calculates relevancy and impact scores, selects optimal strategies per gap, and optionally aggregates results at the strategy level while mutating upstream data to reflect closed gaps.

---

## Input Parameters

- **@Technology_id**  
  Filters all results to a specific technology.

- **@REAF_Scale**  
  Restricts strategies to a specific REAF scale.

- **@PMRGapScopeFilter**  
  Value used to filter gaps by scope (e.g., Installation-wide vs Mission-wide).

- **@PMRGapScopeFilterOperator**  
  Operator applied to the PMR scope filter (`=`, `!=`, `LIKE`, `NOT LIKE`).

- **@MinRelevancyScore**  
  Minimum PMR gap relevancy score required.

- **@MinTechToStratRelevancyScore**  
  Minimum technology-to-strategy relevancy score required.

- **@ClearExistingData**  
  When set to `1`, output tables are cleared and counters reset.

- **@GenerateStrategyImpact**  
  Controls whether aggregated strategy-level results are generated.

---

## Row Counter Management

The procedure uses a persistent `Row_Counter` table to maintain deterministic row IDs across executions.

- If the table does not exist, it is created.
- Counters are maintained separately for:
  - `Gap_Closure_Opportunities`
  - `Strategy_Impact`

This avoids reusing row identifiers when the procedure is run incrementally.

---

## Output Table Initialization

### Gap_Closure_Opportunities
If the table does not exist, it is created with `Row_ID` as the first column to ensure consistent ordering.

When `@ClearExistingData = 1`:
- The table is dropped and recreated.
- The associated row counter is reset.

### Strategy_Impact
If enabled and missing, the table is created to store aggregated strategy-level results.

---

## Cross-Reference Dataset Creation

A temporary table (`#_Cross_reference_Impact_Installation`) is built by joining:

- Preliminary PMR gaps
- Gap–strategy–technology mappings
- Strategy impact by installation

A **combined relevancy score** is calculated as

[PMR gap relevancy × technology-to-strategy relevancy] / 100


Only rows meeting all filters (technology, REAF scale, scope, and minimum scores) are included.

---

## Highest Relevancy Selection

A second temporary table (`#Distinct_Relevency_Score_Installation`) determines the **maximum combined relevancy score** for each:

- Installation
- Preliminary gap

This ensures only the strongest strategy alignment per gap is considered.

---

## Maximum Impact Selection

A third temporary table (`#Max_impact_and_relevency`) selects the strategy with the **highest impact potential** among those with the maximum combined relevancy score.

This enforces a two-step optimization:
1. Best fit (relevancy)
2. Highest payoff (impact)

---

## Row Number Assignment

A numbered temporary table (`#Numbered_Gap_Opportunities`) assigns unique `Row_ID` values using:

- `ROW_NUMBER()`
- The current value from `Row_Counter`

Only rows with positive impact potential are retained.

---

## Persisting Gap Closure Opportunities

The selected rows are inserted into `Gap_Closure_Opportunities`.

After insertion:
- The number of inserted rows is captured.
- The row counter is incremented accordingly.

Each record represents a single gap closure opportunity for a specific installation, strategy, and technology.

---

## Strategy Impact Generation (Optional)

When `@GenerateStrategyImpact = 1`, the procedure:

1. Aggregates gap closure results by:
   - Installation
   - Strategy
   - Technology
2. Computes:
   - Average cost per building
   - Number of gaps closed
   - Concatenated list of closed gaps
3. Inserts the results into `Strategy_Impact` with persistent row IDs.

---

## State Updates

After strategy impact generation:

- Closed gaps are removed from the preliminary gap table.
- Remaining strategy impact potential is reduced to reflect realized impact.

This prevents gaps and impact from being counted multiple times in future runs.

---

## Cleanup

All temporary tables are dropped before the procedure exits.

---

## Summary

This stored procedure functions as a **decision pipeline** that:
- Scores and ranks gap–strategy–technology combinations
- Selects the optimal strategy per gap and installation
- Persists actionable results
- Updates upstream data to reflect progress over time

It is designed for **incremental execution with stateful side effects**, not ad-hoc reporting.

