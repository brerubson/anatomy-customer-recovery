# anatomy-customer-recovery
End-to-end analytics case study: customer recovery and £10m expansion decision for a UK retail brand.
## Business context
Anatomy is UK lifestyle/wellbeing retailer. The brand saw a downturn, then recovery, however, recovery that looks strong in aggregate can hide weak spots. This project tests whether Anatomy's recovery is broad-based across customer segments and product lines, or narrow and fragile, before recommending whether the £10m investment is justified.

## Approach
- **SQL**: cleaned and queried raw customer, product and transaction data (~112,000+ transaction rows) to build the core analysis tables
- **Python**: exploratory analysis, RFM customer segmentation, and scenario modelling
- **Excel**: 10-tab financial model covering historical performance, expansion drivers, revenue and cost modelling, and downside/base/upside scenarios
- **Power BI**: 4-page live dashboard (Executive Overview, Customer Segments, Product Performance, £10m Expansion Case), connected to Postgres

## Key finding
Revenue has recovered to 97% of its pre-downturn peak, but none of the three expansion scenarios repay the £10m within 3 years on operating profit alone. The recovery looks strong on the surface, but the investment case only holds if Anatomy can defend a strategic rationale beyond fast payback.

## Repository structure
- `/sql` — queries used for cleaning and building analysis tables
- `/python` — EDA, segmentation, and scenario modelling scripts/notebooks
- `/charts` — key visualisations generated from the Python analysis

## Tools
SQL · Python · Power BI · DAX · Excel
