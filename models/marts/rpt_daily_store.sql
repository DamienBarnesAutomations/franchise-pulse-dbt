WITH sales AS (
    SELECT * FROM {{ ref('fct_sales') }}
),

daily_store_summary AS (
    SELECT
        full_date,
        store_id,
        store_name,
        city,
        region,
        franchise_owner,
        day_name,
        is_weekend,
        month_name,
        quarter_number,
        year_number,
        COUNT(*) AS total_transactions,
        SUM(quantity) AS total_items_sold,
        SUM(gross_revenue) AS gross_revenue,
        SUM(discount_amount) AS total_discounts,
        SUM(net_revenue) AS net_revenue,
        AVG(net_revenue) AS avg_transaction_value,
        COUNT(DISTINCT cashier_id) AS active_cashiers,
        SUM(CASE WHEN is_refund = 1 THEN 1 ELSE 0 END) AS refund_count,
        SUM(CASE WHEN is_refund = 1 THEN net_revenue ELSE 0 END) AS refund_value
    FROM sales
    GROUP BY
        full_date,
        store_id,
        store_name,
        city,
        region,
        franchise_owner,
        day_name,
        is_weekend,
        month_name,
        quarter_number,
        year_number
)

SELECT * FROM daily_store_summary
