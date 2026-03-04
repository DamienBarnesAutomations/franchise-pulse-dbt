WITH sales AS (
    SELECT * FROM {{ ref('fct_sales') }}
    WHERE is_refund = 0
),

weekly_product_summary AS (
    SELECT
        year_number,
        week_of_year,
        region,
        store_id,
        store_name,
        product_sku,
        product_name,
        category,
        MIN(full_date) AS week_start,
        MAX(full_date) AS week_end,
        COUNT(*) AS times_sold,
        SUM(quantity) AS total_quantity,
        SUM(gross_revenue) AS gross_revenue,
        SUM(discount_amount) AS total_discounts,
        SUM(net_revenue) AS net_revenue,
        ROUND(SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0) * 100, 2) AS discount_rate_pct,
        ROUND(SUM(net_revenue) / NULLIF(SUM(quantity), 0), 2) AS net_revenue_per_unit
    FROM sales
    GROUP BY
        year_number,
        week_of_year,
        region,
        store_id,
        store_name,
        product_sku,
        product_name,
        category
)

SELECT * FROM weekly_product_summary
