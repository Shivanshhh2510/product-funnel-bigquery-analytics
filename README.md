# Product Funnel & User Behavior Analytics — Google Merchandise Store

End-to-end product analytics project analyzing **903,653 web sessions** and **714,167 unique visitors** from the Google Merchandise Store to identify conversion funnel bottlenecks, channel inefficiencies, and revenue optimization opportunities.

## Tools & Stack
| Layer | Tool |
|-------|------|
| SQL & Data Warehouse | Google BigQuery |
| Dataset | Google Analytics Sample (nested/repeated fields) |
| Python | Pandas, Matplotlib, Seaborn (Google Colab) |
| Dashboard | Looker Studio |
| Deliverable | Executive Recommendations Memo |

## Key Findings

- **86% of visitors never view a product** — largest funnel leak; top-of-funnel engagement is the #1 priority
- **Mobile converts 4x worse than desktop** (0.41% vs 1.67%) despite being 23% of traffic
- **Returning visitors drive 75% of revenue** at 5.6x the conversion rate of new visitors
- **Social channel: 226K sessions but only 0.06% conversion** with 65% bounce rate
- **Sessions with 20+ pageviews convert at 29%** and generate 74% of all revenue
- **Top 1% of customers (101 people) drive 32% of revenue**, averaging $5,616 each
- **Tuesday is the peak revenue day** ($367K) while Sunday generates only $72K — clear B2B purchasing pattern
- **Peak buying window: 5PM–10PM** with 2%+ conversion; mornings (6–10AM) convert below 0.5%

## Dashboard

**[Live Looker Studio Dashboard](https://datastudio.google.com/reporting/739705d3-2e06-4ec9-a712-023369b7b867)**

### Page 1 — Funnel Overview
<img width="1198" height="900" alt="image" src="https://github.com/user-attachments/assets/0f17178a-4ab8-431e-b7b3-dec105ecbed2" />

### Page 2 — Device & Geography Performance
<img width="1201" height="897" alt="image" src="https://github.com/user-attachments/assets/190bb316-fcb4-4da6-aa39-19ae270b9569" />

### Page 3 — Time & Behavioral Trends
<img width="1198" height="895" alt="image" src="https://github.com/user-attachments/assets/d112410a-09d7-4f72-ba02-c1cfe3a3cdd3" />

## Analysis Breakdown

### Batch 1: Overall Funnel Metrics
Session-to-purchase conversion funnel with stage-by-stage drop-off rates, bounce rate analysis, and new vs returning visitor segmentation.

### Batch 2: Channel & Traffic Source Analysis
Revenue, conversion rate, AOV, and bounce rate by acquisition channel. Full funnel breakdown per channel. Paid vs organic vs direct comparison.

### Batch 3: Device & Geography
Desktop vs mobile vs tablet performance gap. Device × channel cross-tabulation. Top countries by revenue. Browser-level analysis.

### Batch 4: Time-Based Patterns
Monthly revenue trends with MoM growth (LAG window function). Day-of-week and hour-of-day purchasing behavior. Weekly revenue for anomaly detection.

### Batch 5: Advanced Deep Dives
Converting vs non-converting session behavior. Customer revenue concentration using PERCENT_RANK. Pageview depth vs conversion analysis. Repeat purchase segmentation. Landing page performance.

## Project Structure
```
├── product_funnel_bigquery_analysis.sql       # 25 BigQuery queries across 5 analysis batches
├── Product_Funnel_BigQuery_Analysis.ipynb      # Python notebook — BigQuery → Pandas → visualizations
├── Business_Recommendations_Memo.pdf           # Executive memo with 5 prioritized actions
├── Business_Recommendations_Memo.docx          # Word version
├── screenshots/                                # Dashboard screenshots
│   ├── page1_funnel_overview.png
│   ├── page2_device_geography.png
│   └── page3_time_trends.png
└── README.md
```

## SQL Techniques Used
- UNNEST for flattening nested/repeated fields (hits array)
- CTEs for multi-step funnel calculations
- Window functions: LAG (MoM growth), PERCENT_RANK (customer tiering)
- CASE expressions for custom segmentation
- TIMESTAMP_SECONDS / FORMAT_TIMESTAMP for time analysis
- Wildcard table querying with _TABLE_SUFFIX filtering

## Recommendations Summary

| # | Recommendation | Estimated Impact |
|---|---------------|-----------------|
| 1 | Fix mobile checkout experience | +$200K–400K/year |
| 2 | Improve top-of-funnel product discovery | +$150K–300K/year |
| 3 | Invest in returning visitor retention | +$100K–250K/year |
| 4 | Reallocate social channel budget | Cost savings + reallocation |
| 5 | Optimize ad scheduling for peak windows | +15–25% ROAS |

## Dataset
**Google Analytics Sample Dataset**
`bigquery-public-data.google_analytics_sample.ga_sessions_*`
Period: August 2016 – August 2017 | 903,653 sessions | 714,167 unique visitors | $1.78M revenue
