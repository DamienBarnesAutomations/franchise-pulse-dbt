WITH sales AS (
    SELECT * FROM {{ ref('fct_sales') }}
),

regional_summary AS (
    SELECT
        year_number,
        quarter_number,
        month_name,
        region,
        COUNT(DISTINCT store_id) AS store_count,
        COUNT(DISTINCT full_date) AS trading_days,
        COUNT(*) AS total_transactions,
        SUM(quantity) AS total_items_sold,
        SUM(gross_revenue) AS gross_revenue,
        SUM(discount_amount) AS total_discounts,
        SUM(net_revenue) AS net_revenue,
        ROUND(SUM(net_revenue) / NULLIF(COUNT(DISTINCT store_id), 0), 2) AS net_revenue_per_store,
        ROUND(SUM(net_revenue) / NULLIF(COUNT(DISTINCT full_date), 0), 2) AS net_revenue_per_day,
        AVG(net_revenue) AS avg_transaction_value
    FROM sales
    GROUP BY
        year_number,
        quarter_number,
        month_name,
        region
)

SELECT * FROM regional_summary
