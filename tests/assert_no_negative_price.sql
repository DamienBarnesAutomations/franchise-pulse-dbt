-- Fails if any transaction in fct_sales has a non-positive unit_price
-- unit_price should always be > 0 after validation
SELECT *
FROM {{ ref('fct_sales') }}
WHERE unit_price <= 0
