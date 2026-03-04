WITH validated AS (
    SELECT * FROM {{ ref('int_sales_validated') }}
),

dim_store AS (
    SELECT * FROM {{ source('franchisepulse', 'dim_store') }}
),

dim_product AS (
    SELECT * FROM {{ source('franchisepulse', 'dim_product') }}
),

dim_date AS (
    SELECT * FROM {{ source('franchisepulse', 'dim_date') }}
),

dim_payment_method AS (
    SELECT * FROM {{ source('franchisepulse', 'dim_payment_method') }}
),

enriched AS (
    SELECT
        v.transaction_id,
        v.quantity,
        v.unit_price,
        v.discount_applied,
        v.is_refund,
        v.gross_revenue,
        v.discount_amount,
        v.net_revenue,
        v.cashier_id,
        v.source_file,
        v._loaded_at,

        -- Store Attributes
        s.store_key,
        s.store_id,
        s.store_name,
        s.city,
        s.region,
        s.franchise_owner,

        -- Product Attributes
        p.product_key,
        p.product_sku,
        p.product_name,
        p.category,
        p.standard_price,

        -- Date Attributes
        d.date_key,
        d.full_date,
        d.day_name,
        d.is_weekend,
        d.week_of_year,
        d.month_number,
        d.month_name,
        d.quarter_number,
        d.year_number,

        -- Payment Attributes
        pm.payment_key,
        pm.payment_method

    FROM validated v
    INNER JOIN dim_store s ON v.store_id = s.store_id
    INNER JOIN dim_product p ON v.product_sku = p.product_sku
    INNER JOIN dim_date d ON v.transaction_date_key = d.date_key
    INNER JOIN dim_payment_method pm ON v.payment_method = pm.payment_method
)

SELECT * FROM enriched
