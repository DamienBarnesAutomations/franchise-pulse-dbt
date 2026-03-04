{{ config(
    materialized='incremental',
    unique_key='transaction_id'
) }}

WITH enriched AS (
    SELECT * FROM {{ ref('int_sales_enriched') }}
)

SELECT
    transaction_id,
    date_key,
    store_key,
    product_key,
    payment_key,
    store_id,
    store_name,
    city,
    region,
    franchise_owner,
    product_sku,
    product_name,
    category,
    full_date,
    day_name,
    is_weekend,
    week_of_year,
    month_name,
    quarter_number,
    year_number,
    payment_method,
    cashier_id,
    quantity,
    unit_price,
    discount_applied,
    is_refund,
    gross_revenue,
    discount_amount,
    net_revenue,
    source_file,
    _loaded_at
FROM enriched

{% if is_incremental() %}
    -- Only insert rows that don't already exist in the target table
    WHERE transaction_id NOT IN (SELECT transaction_id FROM {{ this }})
{% endif %}
