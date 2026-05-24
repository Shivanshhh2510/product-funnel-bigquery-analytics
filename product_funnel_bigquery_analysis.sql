-- =============================================
-- Product Funnel & User Behavior Analytics
-- Google Merchandise Store (Google Analytics Sample Dataset)
-- Platform: Google BigQuery
-- Dataset: bigquery-public-data.google_analytics_sample.ga_sessions_*
-- Analysis Period: August 2016 – August 2017
-- Total Sessions: 903,653 | Unique Visitors: 714,167
-- Author: Shivansh Mishra
-- =============================================
-- 
-- This analysis examines 12 months of Google Merchandise Store web analytics data
-- to understand user purchase behavior, identify conversion funnel bottlenecks,
-- and surface actionable recommendations for revenue growth.
--
-- The dataset uses BigQuery's nested/repeated fields (STRUCT and ARRAY types).
-- Key nested structures:
--   totals.*           -> session-level aggregates (pageviews, transactions, revenue)
--   trafficSource.*    -> where the user came from
--   device.*           -> browser, OS, device type
--   geoNetwork.*       -> country, city, region
--   hits[]             -> ARRAY of every pageview/event in the session (requires UNNEST)
--
-- Revenue is stored in micros (x1,000,000), so we divide by 1000000 throughout.
-- eCommerceAction.action_type values: 2=product view, 3=add to cart, 6=purchase
--
-- =============================================


-- =============================================
-- SECTION 1: OVERALL FUNNEL METRICS
-- Starting with the big picture before drilling down.
-- =============================================


-- Q1: How is the store performing overall?
-- Quick health check: sessions, transactions, revenue, and site-wide conversion rate.

SELECT
  COUNT(*) AS total_sessions,
  SUM(totals.transactions) AS total_transactions,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS total_revenue_usd,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801';

-- Result: 903K sessions, 12,115 transactions, $1.78M revenue, 1.34% conversion rate.
-- That's a fairly standard e-commerce conversion rate, but there's room to push it higher.


-- Q2: Where exactly are users dropping off in the purchase funnel?
-- Tracking unique visitors through: visit → product view → add to cart → purchase.
-- Using UNNEST to flatten the hits array and check eCommerceAction types.

SELECT
  COUNT(DISTINCT fullVisitorId) AS total_visitors,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '2' THEN fullVisitorId 
  END) AS viewed_product,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '3' THEN fullVisitorId 
  END) AS added_to_cart,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
  END) AS completed_purchase
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
  UNNEST(hits) AS hits
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801';

-- Result: 714K → 99K → 40K → 10K
-- The biggest leak is right at the top: 86% of visitors never even look at a product.
-- That's where the highest-leverage optimization opportunity sits.


-- Q3: Calculating the exact drop-off percentages between each funnel stage.
-- Wrapping Q2 in a CTE so we can compute stage-to-stage conversion rates cleanly.

WITH funnel AS (
  SELECT
    COUNT(DISTINCT fullVisitorId) AS total_visitors,
    COUNT(DISTINCT CASE 
      WHEN hits.eCommerceAction.action_type = '2' THEN fullVisitorId 
    END) AS viewed_product,
    COUNT(DISTINCT CASE 
      WHEN hits.eCommerceAction.action_type = '3' THEN fullVisitorId 
    END) AS added_to_cart,
    COUNT(DISTINCT CASE 
      WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
    END) AS completed_purchase
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
    UNNEST(hits) AS hits
  WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
)
SELECT
  total_visitors,
  viewed_product,
  ROUND(viewed_product * 100.0 / total_visitors, 2) AS pct_viewed,
  added_to_cart,
  ROUND(added_to_cart * 100.0 / viewed_product, 2) AS view_to_cart_pct,
  completed_purchase,
  ROUND(completed_purchase * 100.0 / added_to_cart, 2) AS cart_to_purchase_pct,
  ROUND(completed_purchase * 100.0 / total_visitors, 2) AS overall_conversion_pct
FROM funnel;

-- Result: 13.9% view a product → 40.1% of those add to cart → 25.2% of those buy.
-- Overall conversion: 1.4%. The view-to-cart rate (40%) is actually decent.
-- The real problem is getting people to engage with products in the first place.


-- Q4: What percentage of sessions bounce (single-page visits)?
-- High bounce rate directly explains the top-of-funnel leak we saw above.

SELECT
  COUNT(*) AS total_sessions,
  SUM(totals.bounces) AS bounced_sessions,
  ROUND(SUM(totals.bounces) * 100.0 / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801';

-- Result: 49.87% bounce rate. Nearly half of all traffic leaves after one page.
-- This confirms the funnel issue — most visitors aren't finding what they came for,
-- or the landing experience isn't compelling enough to keep them exploring.


-- Q5: Do returning visitors convert better than first-time visitors?
-- Splitting by new vs returning to understand the value of retention.

SELECT
  CASE WHEN totals.newVisits = 1 THEN 'New Visitor' ELSE 'Returning Visitor' END AS visitor_type,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY visitor_type
ORDER BY revenue_usd DESC;

-- Result: Returning visitors convert at 3.71% vs new visitors at 0.66% — a 5.6x gap.
-- Returning visitors are only 22% of sessions but drive 74.9% of revenue ($1.33M).
-- This is the clearest signal in the data: retention is everything for this store.


-- =============================================
-- SECTION 2: CHANNEL & TRAFFIC SOURCE ANALYSIS
-- Understanding which acquisition channels actually drive revenue,
-- not just traffic volume.
-- =============================================


-- Q6: Which channels bring in the most revenue and convert best?
-- Including average order value (AOV) to see if certain channels attract bigger spenders.

SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000 / NULLIF(SUM(totals.transactions), 0), 2) AS avg_order_value
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY channelGrouping
ORDER BY revenue_usd DESC;

-- Result: Referral leads with 5.29% conversion and $717K revenue.
-- Display has crazy high AOV ($857) but tiny volume — probably bulk/corporate orders.
-- Social brings 226K sessions but only 0.06% conversion. That's a lot of wasted traffic.


-- Q7: Breaking down the full purchase funnel by channel.
-- Which channels leak the most at each stage? This tells us WHERE to fix things per channel.

SELECT
  channelGrouping,
  COUNT(DISTINCT fullVisitorId) AS visitors,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '2' THEN fullVisitorId 
  END) AS viewed_product,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '3' THEN fullVisitorId 
  END) AS added_to_cart,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
  END) AS purchased,
  ROUND(COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
  END) * 100.0 / COUNT(DISTINCT fullVisitorId), 2) AS overall_conv_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
  UNNEST(hits) AS hits
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY channelGrouping
ORDER BY overall_conv_pct DESC;

-- Result: Referral converts 7% of visitors end-to-end. Social converts 0.05%.
-- Organic Search brings 311K visitors but only 1% convert — huge top-of-funnel volume
-- that doesn't translate. The funnel-by-channel view helps pinpoint where each channel fails.


-- Q8: Bounce rate by channel — which sources send the lowest quality traffic?

SELECT
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(totals.bounces) AS bounced,
  ROUND(SUM(totals.bounces) * 100.0 / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY channelGrouping
ORDER BY bounce_rate_pct DESC;

-- Result: Social has the worst bounce rate at 65.2%, followed by Affiliates at 53%.
-- Referral has the lowest at 26% — which lines up with it having the best conversion.
-- High bounce = wrong audience or broken landing experience for that channel.


-- Q9: Drilling into specific traffic sources (source + medium) to find the top revenue drivers.
-- channelGrouping is Google's pre-built classification. This goes one level deeper.

SELECT
  trafficSource.source,
  trafficSource.medium,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY trafficSource.source, trafficSource.medium
ORDER BY revenue_usd DESC
LIMIT 10;

-- Result: Direct/(none) dominates with $1.33M — people typing the URL or bookmarking it.
-- Google organic is second at $239K. DFA (DoubleClick) CPM ads brought $128K with only 5.7K sessions.
-- mail.google.com referral is interesting — email links driving $24.8K in revenue.


-- Q10: Simplified view — Paid vs Organic vs Direct vs Referral performance.
-- Grouping traffic mediums into broader buckets for the executive summary.

SELECT
  CASE 
    WHEN trafficSource.medium = 'organic' THEN 'Organic'
    WHEN trafficSource.medium IN ('cpc', 'ppc', 'cpm') THEN 'Paid'
    WHEN trafficSource.medium = 'referral' THEN 'Referral'
    WHEN trafficSource.medium = '(none)' THEN 'Direct'
    ELSE 'Other'
  END AS traffic_type,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd,
  ROUND(SUM(totals.bounces) * 100.0 / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY traffic_type
ORDER BY revenue_usd DESC;

-- Result: Direct traffic is the revenue king ($1.33M, 2.47% conversion).
-- Paid converts at 2.07% but drives much less total revenue ($158K).
-- Referral has the highest bounce rate (62.7%) when bucketed this way, but that includes
-- social referrals mixed in. The channelGrouping view (Q8) is more accurate for bounce analysis.


-- =============================================
-- SECTION 3: DEVICE & GEOGRAPHY ANALYSIS
-- Mobile vs Desktop is one of the most actionable dimensions
-- for any e-commerce store.
-- =============================================


-- Q11: How does conversion differ across desktop, mobile, and tablet?

SELECT
  device.deviceCategory,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd,
  ROUND(SUM(totals.bounces) * 100.0 / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY device.deviceCategory
ORDER BY revenue_usd DESC;

-- Result: Desktop generates 96.2% of all revenue ($1.71M) at 1.67% conversion.
-- Mobile converts at just 0.41% despite having 208K sessions (23% of traffic).
-- The mobile experience is clearly underperforming — this is the biggest actionable gap.


-- Q12: Cross-tabulating device type with channel to find specific weak spots.
-- Maybe mobile converts fine for some channels but terribly for others.

SELECT
  device.deviceCategory,
  channelGrouping,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY device.deviceCategory, channelGrouping
HAVING SUM(totals.transactions) > 0
ORDER BY device.deviceCategory, revenue_usd DESC;

-- Result: Desktop Referral is the golden combo (5.58% conversion, $716K revenue).
-- Mobile Direct converts at just 0.46% vs Desktop Direct at 2.22%.
-- Even the best mobile channel (Paid Search at 0.88%) is worse than the worst
-- performing desktop channel. Mobile checkout needs serious attention.


-- Q13: Which countries are driving revenue?
-- This store sells globally but the distribution might be heavily skewed.

SELECT
  geoNetwork.country,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY geoNetwork.country
ORDER BY revenue_usd DESC
LIMIT 10;

-- Result: United States dominates with 93.5% of revenue ($1.66M) and 3.14% conversion.
-- Venezuela is a surprising #2 — only 2K sessions but 7.18% conversion ($36K).
-- Likely bulk/corporate purchases rather than regular consumers.
-- Canada is #3 at $35K but with a much lower 0.77% conversion rate.


-- Q14: Full purchase funnel broken down by device type.
-- Seeing exactly where mobile users drop off compared to desktop.

SELECT
  device.deviceCategory,
  COUNT(DISTINCT fullVisitorId) AS visitors,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '2' THEN fullVisitorId 
  END) AS viewed_product,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '3' THEN fullVisitorId 
  END) AS added_to_cart,
  COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
  END) AS purchased,
  ROUND(COUNT(DISTINCT CASE 
    WHEN hits.eCommerceAction.action_type = '6' THEN fullVisitorId 
  END) * 100.0 / COUNT(DISTINCT fullVisitorId), 2) AS overall_conv_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
  UNNEST(hits) AS hits
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY device.deviceCategory
ORDER BY overall_conv_pct DESC;

-- Result: Desktop converts at 1.73% overall, mobile at 0.49% — a 3.5x gap.
-- Mobile actually gets decent product view rates (13.9% of mobile visitors view a product),
-- but the cart-to-purchase step is where mobile falls apart.


-- Q15: Top 5 browsers by session volume — checking for browser-specific issues.

SELECT
  device.browser,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd,
  ROUND(SUM(totals.bounces) * 100.0 / COUNT(*), 2) AS bounce_rate_pct
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY device.browser
ORDER BY sessions DESC
LIMIT 5;

-- Result: Chrome handles 68.7% of sessions and 87.8% of revenue (1.76% conversion).
-- Safari converts at just 0.43% with a 54% bounce rate — makes sense since Safari = mostly
-- iPhone users, which circles back to the mobile conversion problem.
-- Firefox and IE both have 60%+ bounce rates but low session volume.


-- =============================================
-- SECTION 4: TIME-BASED ANALYSIS
-- Looking at when users buy — monthly trends, day of week,
-- and hour of day patterns.
-- =============================================


-- Q16: Monthly revenue and conversion trend over the analysis period.
-- Looking for seasonality, growth patterns, or concerning declines.

SELECT
  SUBSTR(_TABLE_SUFFIX, 1, 6) AS year_month,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY year_month
ORDER BY year_month;

-- Result: Clear holiday spike in Dec 2016 ($167K, 1.83% conversion).
-- January 2017 crashed 36.5% — typical post-holiday hangover.
-- April 2017 was the best non-holiday month at $222K. Revenue is quite volatile month-to-month,
-- swinging 20-40% between adjacent months regularly.


-- Q17: Which days of the week generate the most revenue?
-- Using TIMESTAMP_SECONDS to convert the Unix visitStartTime to a readable format.

SELECT
  FORMAT_TIMESTAMP('%A', TIMESTAMP_SECONDS(visitStartTime)) AS day_of_week,
  EXTRACT(DAYOFWEEK FROM TIMESTAMP_SECONDS(visitStartTime)) AS day_num,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY day_of_week, day_num
ORDER BY day_num;

-- Result: Tuesday is the highest revenue day ($366K) and Friday has the best conversion (1.53%).
-- Weekends are dramatically worse — Sunday only does $72K at 0.9% conversion.
-- This is a textbook B2B purchasing pattern: people buy Google merch during work hours.
-- Weekend promotions would likely be wasted spend.


-- Q18: What time of day do purchases happen?
-- Helps with ad scheduling and promotional email timing.

SELECT
  EXTRACT(HOUR FROM TIMESTAMP_SECONDS(visitStartTime)) AS hour_of_day,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Result: Peak purchasing window is 5PM-10PM (hours 17-22) with 1.9-2.07% conversion.
-- Dead zone is 6AM-10AM at 0.15-0.45% conversion — mornings are browsing-only.
-- Interestingly, midnight-2AM still converts well (1.5-1.9%) — probably US West Coast
-- evening shoppers showing up in UTC-shifted timestamps.
-- Best time to run promotions: mid-afternoon to late evening.


-- Q19: Weekly revenue trend to spot seasonality and anomalies.
-- More granular than monthly — helps catch short-term spikes or dips.

SELECT
  FORMAT_TIMESTAMP('%Y-%W', TIMESTAMP_SECONDS(visitStartTime)) AS year_week,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY year_week
ORDER BY year_week;

-- Result: Week 49-50 of 2016 (early December) shows a clear holiday spike at $56-58K/week.
-- Week 52 drops off sharply — Christmas week slowdown.
-- Week 14 of 2017 had an anomalous $84K week — worth investigating what drove that
-- (possible product launch or marketing campaign).


-- Q20: Month-over-month revenue growth using LAG window function.
-- This is the kind of MoM analysis you'd present in an executive review.

WITH monthly AS (
  SELECT
    SUBSTR(_TABLE_SUFFIX, 1, 6) AS year_month,
    ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd,
    SUM(totals.transactions) AS transactions
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
  WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
  GROUP BY year_month
)
SELECT
  year_month,
  revenue_usd,
  transactions,
  LAG(revenue_usd) OVER (ORDER BY year_month) AS prev_month_revenue,
  ROUND((revenue_usd - LAG(revenue_usd) OVER (ORDER BY year_month)) 
    * 100.0 / LAG(revenue_usd) OVER (ORDER BY year_month), 2) AS revenue_growth_pct
FROM monthly
ORDER BY year_month;

-- Result: The biggest swings: Dec 2016 +25.9% (holiday), Jan 2017 -36.5% (post-holiday crash),
-- Apr 2017 +48.3% (best growth month), May 2017 -39% (sharp correction).
-- The volatility suggests this store is event-driven rather than steady-state.
-- A forecasting model would need to account for these seasonal patterns.


-- =============================================
-- SECTION 5: ADVANCED DEEP DIVES
-- Going beyond surface metrics into behavioral patterns,
-- customer segmentation, and page-level analysis.
-- =============================================


-- Q21: How differently do converting sessions behave vs non-converting?
-- Comparing engagement depth: pageviews and time on site.

SELECT
  CASE WHEN totals.transactions > 0 THEN 'Converted' ELSE 'Did Not Convert' END AS session_type,
  COUNT(*) AS sessions,
  ROUND(AVG(totals.pageviews), 2) AS avg_pageviews,
  ROUND(AVG(totals.timeOnSite), 2) AS avg_time_on_site_sec,
  ROUND(AVG(totals.timeOnSite) / 60, 2) AS avg_time_on_site_min
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY session_type;

-- Result: Converted sessions average 28.4 pageviews and 17.7 minutes on site.
-- Non-converting sessions average just 3.5 pageviews and 4 minutes.
-- That's an 8x difference in page depth and 4.4x difference in time spent.
-- Buyers are doing serious browsing before purchasing — this isn't impulse buying.
-- Implication: anything that keeps users exploring longer increases purchase probability.


-- Q22: Revenue concentration — how much do top customers contribute?
-- Using PERCENT_RANK to tier customers and see if revenue follows a power law.

WITH customer_revenue AS (
  SELECT
    fullVisitorId,
    SUM(totals.totalTransactionRevenue)/1000000 AS total_revenue,
    COUNT(DISTINCT CONCAT(CAST(visitStartTime AS STRING), fullVisitorId)) AS total_sessions,
    SUM(totals.transactions) AS total_transactions
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
  WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
    AND totals.transactions > 0
  GROUP BY fullVisitorId
),
ranked AS (
  SELECT *,
    PERCENT_RANK() OVER (ORDER BY total_revenue DESC) AS pct_rank
  FROM customer_revenue
)
SELECT
  CASE WHEN pct_rank <= 0.01 THEN 'Top 1%'
       WHEN pct_rank <= 0.10 THEN 'Top 2-10%'
       WHEN pct_rank <= 0.50 THEN 'Top 11-50%'
       ELSE 'Bottom 50%'
  END AS customer_tier,
  COUNT(*) AS customers,
  ROUND(SUM(total_revenue), 2) AS tier_revenue,
  ROUND(AVG(total_revenue), 2) AS avg_revenue_per_customer,
  ROUND(AVG(total_transactions), 2) AS avg_transactions
FROM ranked
GROUP BY customer_tier
ORDER BY tier_revenue DESC;

-- Result: Top 1% (101 customers) generated $567K — 31.9% of all revenue.
-- Average spend per top-1% customer: $5,616 with 5.13 transactions each.
-- Bottom 50% (5,011 customers) only contributed $152K total at $30.67 average.
-- Classic Pareto distribution. The top 10% of buyers drive over 64% of revenue.
-- These high-value customers deserve dedicated retention strategies.


-- Q23: Does browsing more pages actually lead to higher conversion?
-- Bucketing sessions by pageview count to find the engagement sweet spot.

SELECT
  CASE
    WHEN totals.pageviews <= 3 THEN '1-3 pages'
    WHEN totals.pageviews <= 6 THEN '4-6 pages'
    WHEN totals.pageviews <= 10 THEN '7-10 pages'
    WHEN totals.pageviews <= 20 THEN '11-20 pages'
    ELSE '20+ pages'
  END AS pageview_bucket,
  COUNT(*) AS sessions,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(*), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
GROUP BY pageview_bucket
ORDER BY conversion_rate_pct DESC;

-- Result: 20+ page sessions convert at 29% and drive $1.32M (74.2% of total revenue).
-- 11-20 pages converts at 9%. Below 6 pages, conversion is essentially zero (0.03%).
-- 1-3 page sessions are 74% of all traffic but generate almost no revenue ($1.4K).
-- Takeaway: the store needs to get users past the 10-page threshold.
-- Features like "recommended products" or "recently viewed" could help extend sessions.


-- Q24: How valuable are repeat buyers compared to one-time purchasers?
-- Segmenting customers by number of purchase sessions.

WITH visitor_transactions AS (
  SELECT
    fullVisitorId,
    COUNT(DISTINCT CONCAT(CAST(visitStartTime AS STRING), fullVisitorId)) AS purchase_sessions,
    SUM(totals.transactions) AS total_transactions,
    ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS total_revenue
  FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`
  WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
    AND totals.transactions > 0
  GROUP BY fullVisitorId
)
SELECT
  CASE
    WHEN purchase_sessions = 1 THEN 'One-time buyer'
    WHEN purchase_sessions BETWEEN 2 AND 3 THEN '2-3 purchases'
    WHEN purchase_sessions BETWEEN 4 AND 10 THEN '4-10 purchases'
    ELSE '10+ purchases'
  END AS buyer_segment,
  COUNT(*) AS customers,
  ROUND(SUM(total_revenue), 2) AS segment_revenue,
  ROUND(AVG(total_revenue), 2) AS avg_revenue_per_customer,
  ROUND(SUM(total_revenue) * 100.0 / (SELECT SUM(total_revenue) FROM visitor_transactions), 2) AS pct_of_total_revenue
FROM visitor_transactions
GROUP BY buyer_segment
ORDER BY segment_revenue DESC;

-- Result: One-time buyers are 90.3% of all customers but only 57.8% of revenue.
-- The 8 customers with 10+ purchase sessions generated $161K (9.1% of revenue)
-- at an average of $20,226 per customer. That's 178x more than a one-time buyer.
-- Even moving 5% of one-time buyers into the "2-3 purchases" tier would add ~$150K
-- in annual revenue. Re-engagement email campaigns targeting first-time purchasers
-- would have massive ROI.


-- Q25: Which landing pages drive the most revenue and convert best?
-- Using hits.hitNumber = 1 to identify the first page a user sees.
-- Only including pages with 100+ visitors to filter out noise.

SELECT
  hits.page.pagePath AS landing_page,
  COUNT(DISTINCT fullVisitorId) AS visitors,
  SUM(totals.transactions) AS transactions,
  ROUND(SUM(totals.transactions) * 100.0 / COUNT(DISTINCT fullVisitorId), 2) AS conversion_rate_pct,
  ROUND(SUM(totals.totalTransactionRevenue)/1000000, 2) AS revenue_usd
FROM `bigquery-public-data.google_analytics_sample.ga_sessions_*`,
  UNNEST(hits) AS hits
WHERE _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
  AND hits.hitNumber = 1
GROUP BY landing_page
HAVING COUNT(DISTINCT fullVisitorId) > 100
ORDER BY revenue_usd DESC
LIMIT 15;

-- Result: /home is the top landing page by volume (516K visitors) but converts at just 1.39%.
-- /basket.html converts at 11.12% — people landing directly on the cart page are 8x
-- more likely to buy (these are probably returning users with saved carts).
-- /store.html converts at 10.04% — direct store page access also converts very well.
-- The product category pages (/google+redesign/apparel, /bags, /office) have moderate
-- conversion rates around 1-3%.
-- Recommendation: create direct-to-store and direct-to-category landing pages for ads
-- instead of sending all traffic to the homepage.


-- =============================================
-- END OF ANALYSIS
-- =============================================
--
-- KEY FINDINGS SUMMARY:
--
-- 1. FUNNEL: 86% of visitors never view a product. The biggest opportunity is
--    getting visitors to engage with products, not optimizing the checkout.
--
-- 2. MOBILE GAP: Desktop converts at 1.67% vs mobile at 0.41% (4x gap).
--    Desktop drives 96.2% of revenue. Mobile checkout is the #1 fix.
--
-- 3. RETURNING VISITORS: Convert 5.6x better than new visitors and drive 75% of revenue.
--    Retention investment has the highest ROI of any strategy.
--
-- 4. CHANNEL EFFICIENCY: Referral converts at 5.29% with the lowest bounce rate (26%).
--    Social brings massive traffic (226K sessions) but converts at 0.06% — likely
--    not worth continued investment without a strategy overhaul.
--
-- 5. TIME PATTERNS: Weekday, afternoon-to-evening purchases dominate (B2B pattern).
--    Tuesday is the peak revenue day. Weekends underperform by 3-4x.
--
-- 6. ENGAGEMENT THRESHOLD: Sessions with 20+ pageviews convert at 29% and generate
--    74% of revenue. Getting users past 10 pages is the inflection point.
--
-- 7. CUSTOMER CONCENTRATION: Top 1% of customers (101 people) drive 31.9% of revenue.
--    8 customers with 10+ purchases average $20K each.
--
-- 8. LANDING PAGES: Direct-to-store pages convert 7-8x better than homepage.
--    Ad campaigns should target store/category pages, not homepage.
--
-- =============================================
