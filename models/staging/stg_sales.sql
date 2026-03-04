WITH source AS (
    SELECT * FROM {{ source('franchisepulse', 'stg_sales') }}
),

renamed AS (
    SELECT
        transaction_id,
        store_id,
        CAST(transaction_date AS DATETIME2) AS transaction_date,
        product_sku,
        product_name,
        category,
        CAST(quantity AS SMALLINT) AS quantity,
        CAST(unit_price AS DECIMAL(10,2)) AS unit_price,
        CAST(discount_applied AS DECIMAL(10,2)) AS discount_applied,
        payment_method,
        NULLIF(cashier_id, '') AS cashier_id,
        source_file,
        load_timestamp AS _loaded_at
    FROM source
    WHERE validation_status = 'PASS'
)

SELECT * FROM renamed
