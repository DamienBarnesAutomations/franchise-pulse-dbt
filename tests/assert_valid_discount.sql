-- Fails if discount_applied is outside the valid range 0.00 to 1.00
-- 0 = no discount, 1 = 100% discount (free)
SELECT *
FROM {{ ref('fct_sales') }}
WHERE discount_applied < 0
   OR discount_applied > 1
