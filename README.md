## Summary: 
This research project identifies mean-reversion opportunities in the CBOE Volatility Index (VIX) by analyzing a decade of seasonal market data. 
The core hypothesis tests the "Summer Volatility Creep"—a recurring phenomenon where equity volatility expands during June/July before structurally contracting.
By benchmarking daily VIX levels against 10-year monthly historical means and standard deviations, this model utilizes Z-scores to distinguish between standard seasonal noise and genuine market panic.
The integration of the VVIX (Volatility of Volatility) serves as a "Bluff Detector," filtering for high-probability "volatility crush" setups where VIX price expansion is unsupported by the options market.
Methodology & Statistical ApproachTime-Series Analysis: 
Processed 10 years of daily CBOE data using R (tidyquant, tidyverse).
## Monthly Normalization: 
Calculated specific means and standard deviations (sigma) for each calendar month to account for structural seasonality (e.g., March mean of $22.90$ vs. July mean of $16.43$).
## Z-Score Modeling:
Generated Z-scores to quantify how many standard deviations the VIX is trading from its seasonal norm, allowing for objective risk assessment.
## Divergence Logic: 
Analyzed the spread between VIX and VVIX rankings.
A rising VIX coupled with a flat or declining VVIX suggests over-hedging and a high probability of mean reversion.
## Visual Dashboard Analysis:
The included Macro Volatility Dashboard provides a dual-pane look at market tension:
## Top Pane (VIX & Seasonal Shadow): 
Tracks raw VIX price against a +/- 1 Standard Deviation ribbon.
When the price breaches the ribbon in summer months without a fundamental catalyst, it signals an overstretched "creep."
## Bottom Pane (VVIX): 
Serves as the confirmation filter. 
Divergence between a rising VIX and a stagnant VVIX is the primary signal for an impending volatility crush, providing a data-driven basis for entering short-volatility positions or selecting VIX Put strikes.
## Practical Application: 
## Strike Selection: 
A key deliverable of this model is Objective Strike Selection.
By utilizing the calculated sd_vix from the provided datasets, traders can select option strikes based on historical "Expected Moves."
## 1-Sigma Discipline: 
Avoids "lottery ticket" strikes by grounding targets in 10-year historical probability.
## Mean Reversion Targets: 
Identifies the monthly average as the high-probability "Gravity" point for exit strategies.
## Repository Structure VIX_Analysis_Script.R: 
The core R engine for data ingestion and statistical processing.
## VIX_Monthly_Benchmarks.csv:
A 10-year summary of monthly means and standard deviations.
## VIX_Daily_Analysis_Full.csv: 
The raw dataset including daily Z-scores and signal strengths.
## LinkedIn_Macro_Volatility.jpg: 
High-resolution dashboard visualization.
