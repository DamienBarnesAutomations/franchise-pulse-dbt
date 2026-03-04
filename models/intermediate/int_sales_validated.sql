WITH staging AS (
    SELECT * FROM {{ ref('stg_sales') }}
),

validated AS (
    SELECT
        *,
        CASE WHEN quantity < 0 THEN 1 ELSE 0 END AS is_refund,
        quantity * unit_price AS gross_revenue,
        quantity * unit_price * discount_applied AS discount_amount,
        quantity * unit_price * (1 - discount_applied) AS net_revenue,
        CONVERT(INT, FORMAT(transaction_date, 'yyyyMMdd')) AS transaction_date_key
    FROM staging
    WHERE unit_price > 0
      AND discount_applied >= 0 AND discount_applied <= 1
      AND transaction_date >= '2024-01-01'
      AND transaction_date <= GETDATE()
)

SELECT * FROM validated
