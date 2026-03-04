# FranchisePulse dbt Transformation Layer
## Full Project Specification

**Project:** franchise-pulse-dbt
**Author:** Damo's Data Solutions
**Version:** 1.0
**Stack:** dbt Core, SQL Server 2022, Python 3.12, Docker

---

## 1. Project Overview

### 1.1 What This Project Is

FranchisePulse dbt is a modern data transformation layer built on top of a
retail sales pipeline for a fictional 12-location Irish coffee franchise.

Raw POS sales data is ingested daily from CSV files into a SQL Server staging
table. This project takes that staged raw data and transforms it into a clean,
tested, documented, reporting-ready data model using dbt Core.

The project demonstrates the full dbt workflow:
- Layered transformation architecture (staging → intermediate → marts)
- Data quality testing at every layer
- Column-level documentation
- Auto-generated lineage documentation
- Exposures documenting downstream consumers
- Incremental materialisation for fact tables

### 1.2 Business Context

FranchisePulse is a fictional coffee franchise operating 12 locations across
Ireland. Each location runs a POS system that exports a daily CSV file
containing transaction-level sales data. The data engineering challenge is:

- 12 stores × ~300 transactions/day = ~3,600 rows/day
- Files arrive with inconsistent quality (malformed prices, duplicates,
  encoding issues, missing files)
- Finance and operations teams need clean, aggregated reporting data
- The transformation layer must be trustworthy, testable, and documented

### 1.3 Scope

**In scope:**
- dbt staging, intermediate, and mart models
- Generic and custom data quality tests
- Column-level documentation for all models
- Lineage graph from source to consumer
- Exposures for downstream consumers
- Incremental fact table loading
- README and project documentation

**Out of scope:**
- CSV ingestion (handled by a separate Airflow pipeline)
- Dimension table management (pre-populated, static for this project)
- BI tool integration (documented as future state via exposures)
- dbt Cloud deployment (local dbt Core only)

---

## 2. Data Context

### 2.1 Source Data

The source for all dbt models is the `dbo.stg_sales` table in SQL Server.
This table is populated by an external ingestion process (Airflow + Python)
that reads daily CSV files and loads them as raw VARCHAR rows.

**stg_sales schema:**

| Column | Type | Notes |
|---|---|---|
| stg_id | BIGINT | Auto-generated staging ID |
| transaction_id | VARCHAR(50) | Natural key — format S01-20251201-00001 |
| store_id | VARCHAR(10) | Store identifier e.g. S01 |
| transaction_date | VARCHAR(30) | Raw datetime string |
| product_sku | VARCHAR(20) | Product identifier e.g. HOT001 |
| product_name | VARCHAR(100) | Product display name |
| category | VARCHAR(50) | Hot Drinks, Cold Drinks, Food, Merch |
| quantity | VARCHAR(10) | May be negative (refunds) |
| unit_price | VARCHAR(20) | May be malformed e.g. 3.80X |
| discount_applied | VARCHAR(10) | Decimal 0.00–1.00 |
| payment_method | VARCHAR(50) | Card, Cash, Contactless, Apple Pay, Google Pay |
| cashier_id | VARCHAR(20) | May be null (~1% of rows) |
| source_file | VARCHAR(255) | Originating filename |
| load_timestamp | DATETIME2 | When row was staged |
| row_hash | CHAR(64) | SHA2_256 hash for deduplication |
| validation_status | VARCHAR(10) | PASS, FAIL, or PENDING |
| rejection_reason | VARCHAR(500) | Populated for FAIL rows |

**Key characteristic:** All source columns are VARCHAR. Type casting and
validation happen in the dbt transformation layer.

### 2.2 Reference Tables

These tables are pre-populated and treated as dbt sources:

**dbo.dim_store** — 12 franchise locations

| Column | Type |
|---|---|
| store_key | INT (PK) |
| store_id | VARCHAR(10) |
| store_name | VARCHAR(100) |
| city | VARCHAR(50) |
| region | VARCHAR(50) — Leinster, Munster, Connacht |
| franchise_owner | VARCHAR(100) |
| is_active | BIT |

**dbo.dim_product** — 17 products across 4 categories

| Column | Type |
|---|---|
| product_key | INT (PK) |
| product_sku | VARCHAR(20) |
| product_name | VARCHAR(100) |
| category | VARCHAR(50) |
| standard_price | DECIMAL(10,2) |
| is_active | BIT |

**dbo.dim_date** — Calendar table 2024-01-01 to 2027-12-31

| Column | Type |
|---|---|
| date_key | INT (PK) — YYYYMMDD format |
| full_date | DATE |
| day_of_week | TINYINT — 1=Monday, 7=Sunday |
| day_name | VARCHAR(10) |
| is_weekend | BIT |
| week_of_year | TINYINT |
| month_number | TINYINT |
| month_name | VARCHAR(10) |
| quarter_number | TINYINT |
| year_number | SMALLINT |

**dbo.dim_payment_method** — 5 payment types

| Column | Type |
|---|---|
| payment_key | INT (PK) |
| payment_method | VARCHAR(50) |

### 2.3 Known Data Quality Issues

The source data contains intentional quality issues that the transformation
layer must handle:

| Issue | Source | Frequency |
|---|---|---|
| Malformed unit_price (e.g. 3.80X) | Store S03 Cork City | ~2% of rows |
| Duplicate rows (resent files) | Store S11 Sligo | ~2% of rows |
| UTF-16 encoding | Store S09 Kilkenny | All rows (handled at ingest) |
| Missing files | Store S07 Limerick | 3 days in sample data |
| Null cashier_id | All stores | ~1% of rows — valid, not an error |
| Negative quantity (refunds) | All stores | ~0.5% of rows — valid, not an error |

dbt models filter out FAIL rows from staging. The transformation layer works
only with rows where `validation_status = 'PASS'`.

---

## 3. Architecture

### 3.1 Layered Model Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  SOURCE LAYER                                               │
│  dbo.stg_sales (raw staged data, loaded by Airflow)         │
│  dbo.dim_store, dim_product, dim_date, dim_payment_method   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGING LAYER          models/staging/                     │
│                                                             │
│  stg_sales.sql                                              │
│  └─ Filter PASS rows only                                   │
│  └─ Cast VARCHAR columns to proper types                    │
│  └─ Standardise nulls                                       │
│  └─ Add audit columns                                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  INTERMEDIATE LAYER     models/intermediate/                │
│                                                             │
│  int_sales_validated.sql                                    │
│  └─ Apply business validation rules as SQL filters          │
│  └─ Add calculated measures (gross/net revenue)             │
│  └─ Flag refund transactions                                │
│                                                             │
│  int_sales_enriched.sql                                     │
│  └─ Join to all four dimension tables                       │
│  └─ Resolve natural keys to surrogate keys                  │
│  └─ Produce fully analysis-ready dataset                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  MART LAYER             models/marts/                       │
│                                                             │
│  fct_sales.sql          ← Incremental fact table            │
│  rpt_daily_store.sql    ← Daily store performance           │
│  rpt_weekly_product.sql ← Weekly product mix                │
│  rpt_regional_summary.sql ← Regional revenue rollup        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  CONSUMPTION LAYER      exposures/reporting.yml             │
│                                                             │
│  Operations Dashboard   → rpt_daily_store                   │
│  Finance Reporting      → rpt_weekly_product                │
│                           rpt_regional_summary              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Materialisation Strategy

| Model | Materialisation | Reason |
|---|---|---|
| stg_sales | view | Always fresh, no storage cost |
| int_sales_validated | view | Intermediate, no need to persist |
| int_sales_enriched | view | Intermediate, no need to persist |
| fct_sales | incremental table | Persistent fact table, append-only |
| rpt_daily_store | view | Reads from fct_sales, always fresh |
| rpt_weekly_product | view | Reads from fct_sales, always fresh |
| rpt_regional_summary | view | Reads from fct_sales, always fresh |

### 3.3 Dependency Graph

```
stg_sales (staging)
    └── int_sales_validated (intermediate)
            └── int_sales_enriched (intermediate)
                    └── fct_sales (mart)
                            ├── rpt_daily_store (mart)
                            ├── rpt_weekly_product (mart)
                            └── rpt_regional_summary (mart)
```

dim tables are referenced directly in int_sales_enriched as dbt sources.

---

## 4. Model Specifications

### 4.1 staging/stg_sales.sql

**Purpose:**
Clean entry point for all downstream models. Reads from `dbo.stg_sales`,
filters to validated rows only, and casts all columns to their correct types.
This model is the single point of contact with the raw source data.

**Source:** `dbo.stg_sales`

**Filter:** `WHERE validation_status = 'PASS'`

**Transformations:**

| Source Column | Target Column | Cast / Transform |
|---|---|---|
| transaction_id | transaction_id | VARCHAR — no change |
| store_id | store_id | VARCHAR — no change |
| transaction_date | transaction_date | CAST to DATETIME2 |
| product_sku | product_sku | VARCHAR — no change |
| product_name | product_name | VARCHAR — no change |
| category | category | VARCHAR — no change |
| quantity | quantity | CAST to SMALLINT |
| unit_price | unit_price | CAST to DECIMAL(10,2) |
| discount_applied | discount_applied | CAST to DECIMAL(10,2) |
| payment_method | payment_method | VARCHAR — no change |
| cashier_id | cashier_id | NULLIF('', cashier_id) |
| source_file | source_file | VARCHAR — no change |
| load_timestamp | _loaded_at | Rename for dbt convention |

**Output columns:** 13 columns as above.

**Materialisation:** view

**Tests (schema.yml):**
- `transaction_id` — not_null, unique
- `store_id` — not_null
- `transaction_date` — not_null
- `product_sku` — not_null
- `unit_price` — not_null
- `quantity` — not_null
- `payment_method` — not_null, accepted_values (Card, Cash, Contactless, Apple Pay, Google Pay)
- `category` — not_null, accepted_values (Hot Drinks, Cold Drinks, Food, Merch)

---

### 4.2 intermediate/int_sales_validated.sql

**Purpose:**
Apply business validation rules as declarative SQL filters. Rows that fail
business rules are excluded from all downstream models. Add calculated
revenue measures and business flags.

**Source:** `{{ ref('stg_sales') }}`

**Filters applied (rows excluded if):**
- `unit_price <= 0`
- `discount_applied < 0 OR discount_applied > 1`
- `transaction_date < '2024-01-01'` (outside dim_date range)
- `transaction_date > GETDATE()` (future dates)

**Calculated columns added:**

| Column | Calculation | Notes |
|---|---|---|
| is_refund | CASE WHEN quantity < 0 THEN 1 ELSE 0 END | BIT flag |
| gross_revenue | quantity * unit_price | Before discount |
| discount_amount | quantity * unit_price * discount_applied | Discount value |
| net_revenue | quantity * unit_price * (1 - discount_applied) | After discount |
| transaction_date_key | CONVERT(INT, FORMAT(transaction_date, 'yyyyMMdd')) | For dim_date join |

**Materialisation:** view

**Tests (schema.yml):**
- `transaction_id` — not_null, unique
- `unit_price` — not_null
- `net_revenue` — not_null
- `gross_revenue` — not_null
- `is_refund` — accepted_values (0, 1)

---

### 4.3 intermediate/int_sales_enriched.sql

**Purpose:**
Join validated sales rows to all four dimension tables. Resolve all natural
keys (store_id, product_sku, payment_method, date) to surrogate keys and
carry through all dimension attributes needed by downstream mart models.
This is the fully denormalised, analysis-ready dataset.

**Source:** `{{ ref('int_sales_validated') }}`

**Joins:**

| Join | Type | On |
|---|---|---|
| dim_store | INNER | dim_store.store_id = int_sales_validated.store_id |
| dim_product | INNER | dim_product.product_sku = int_sales_validated.product_sku |
| dim_date | INNER | dim_date.date_key = int_sales_validated.transaction_date_key |
| dim_payment_method | INNER | dim_payment_method.payment_method = int_sales_validated.payment_method |

**Output columns (selected):**

From sales: `transaction_id`, `quantity`, `unit_price`, `discount_applied`,
`is_refund`, `gross_revenue`, `discount_amount`, `net_revenue`, `cashier_id`,
`source_file`, `_loaded_at`

From dim_store: `store_key`, `store_id`, `store_name`, `city`, `region`,
`franchise_owner`

From dim_product: `product_key`, `product_sku`, `product_name`, `category`,
`standard_price`

From dim_date: `date_key`, `full_date`, `day_name`, `is_weekend`,
`week_of_year`, `month_number`, `month_name`, `quarter_number`, `year_number`

From dim_payment_method: `payment_key`, `payment_method`

**Materialisation:** view

**Tests (schema.yml):**
- `transaction_id` — not_null, unique
- `store_key` — not_null (unmatched store_ids produce nulls via INNER JOIN)
- `product_key` — not_null
- `date_key` — not_null
- `payment_key` — not_null
- `net_revenue` — not_null

---

### 4.4 marts/fct_sales.sql

**Purpose:**
Persistent fact table. The single source of truth for all sales transactions.
Loaded incrementally — on each dbt run, only rows with `transaction_id` values
not already present in the table are inserted. This is the core technical
demonstration of dbt's incremental materialisation pattern.

**Source:** `{{ ref('int_sales_enriched') }}`

**Incremental logic:**
```sql
{{ config(materialized='incremental', unique_key='transaction_id') }}

SELECT ...
FROM {{ ref('int_sales_enriched') }}

{% if is_incremental() %}
WHERE transaction_id NOT IN (SELECT transaction_id FROM {{ this }})
{% endif %}
```

**Output columns:**

| Column | Type | Source |
|---|---|---|
| transaction_id | VARCHAR(50) | Natural key, unique constraint |
| date_key | INT | FK → dim_date |
| store_key | INT | FK → dim_store |
| product_key | INT | FK → dim_product |
| payment_key | INT | FK → dim_payment_method |
| store_id | VARCHAR(10) | Carried for convenience |
| store_name | VARCHAR(100) | Carried for convenience |
| city | VARCHAR(50) | Carried for convenience |
| region | VARCHAR(50) | Carried for convenience |
| franchise_owner | VARCHAR(100) | Carried for convenience |
| product_sku | VARCHAR(20) | Carried for convenience |
| product_name | VARCHAR(100) | Carried for convenience |
| category | VARCHAR(50) | Carried for convenience |
| full_date | DATE | Carried for convenience |
| day_name | VARCHAR(10) | Carried for convenience |
| is_weekend | BIT | Carried for convenience |
| month_name | VARCHAR(10) | Carried for convenience |
| quarter_number | TINYINT | Carried for convenience |
| year_number | SMALLINT | Carried for convenience |
| payment_method | VARCHAR(50) | Carried for convenience |
| cashier_id | VARCHAR(20) | Nullable |
| quantity | SMALLINT | Signed — negative = refund |
| unit_price | DECIMAL(10,2) | Validated positive |
| discount_applied | DECIMAL(10,2) | 0.00–1.00 |
| is_refund | BIT | 1 if quantity < 0 |
| gross_revenue | DECIMAL(10,4) | quantity * unit_price |
| discount_amount | DECIMAL(10,4) | gross_revenue * discount_applied |
| net_revenue | DECIMAL(10,4) | gross_revenue * (1 - discount_applied) |
| source_file | VARCHAR(255) | Audit |
| _loaded_at | DATETIME2 | Audit |

**Note on denormalisation:** `fct_sales` carries dimension attributes directly
(store_name, region, product_name etc.) rather than requiring joins at query
time. This is a deliberate trade-off for query performance on the reporting
layer. The surrogate keys are still present for relational integrity.

**Materialisation:** incremental table

**Tests (schema.yml):**
- `transaction_id` — not_null, unique
- `store_key` — not_null, relationships to dim_store
- `product_key` — not_null, relationships to dim_product
- `date_key` — not_null, relationships to dim_date
- `payment_key` — not_null, relationships to dim_payment_method
- `net_revenue` — not_null
- `unit_price` — not_null
- `quantity` — not_null
- `is_refund` — accepted_values (0, 1)

---

### 4.5 marts/rpt_daily_store.sql

**Purpose:**
Daily store performance summary. One row per store per day. Primary
operational reporting model — answers "how did each store perform today?"

**Source:** `{{ ref('fct_sales') }}`

**Group by:** `full_date`, `store_id`, `store_name`, `city`, `region`,
`franchise_owner`, `day_name`, `is_weekend`, `week_of_year`, `month_name`,
`quarter_number`, `year_number`

**Aggregated columns:**

| Column | Calculation |
|---|---|
| total_transactions | COUNT(*) |
| total_items_sold | SUM(quantity) |
| gross_revenue | SUM(gross_revenue) |
| total_discounts | SUM(discount_amount) |
| net_revenue | SUM(net_revenue) |
| avg_transaction_value | AVG(net_revenue) |
| active_cashiers | COUNT(DISTINCT cashier_id) |
| refund_count | SUM(CASE WHEN is_refund = 1 THEN 1 ELSE 0 END) |
| refund_value | SUM(CASE WHEN is_refund = 1 THEN net_revenue ELSE 0 END) |

**Materialisation:** view

**Tests (schema.yml):**
- `net_revenue` — not_null
- `total_transactions` — not_null

---

### 4.6 marts/rpt_weekly_product.sql

**Purpose:**
Weekly product mix analysis. One row per product per store per week. Finance
team uses this for margin analysis and promotional planning.

**Source:** `{{ ref('fct_sales') }}`

**Filter:** `WHERE is_refund = 0` — exclude refunds from product mix analysis

**Group by:** `year_number`, `week_of_year`, `region`, `store_id`, `store_name`,
`product_sku`, `product_name`, `category`, `standard_price`

**Aggregated columns:**

| Column | Calculation |
|---|---|
| week_start | MIN(full_date) |
| week_end | MAX(full_date) |
| times_sold | COUNT(*) |
| total_quantity | SUM(quantity) |
| gross_revenue | SUM(gross_revenue) |
| total_discounts | SUM(discount_amount) |
| net_revenue | SUM(net_revenue) |
| discount_rate_pct | ROUND(SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0) * 100, 2) |
| net_revenue_per_unit | ROUND(SUM(net_revenue) / NULLIF(SUM(quantity), 0), 2) |

**Materialisation:** view

**Tests (schema.yml):**
- `net_revenue` — not_null
- `total_quantity` — not_null

---

### 4.7 marts/rpt_regional_summary.sql

**Purpose:**
Monthly regional revenue summary. One row per region per month. Executive
summary level. Normalises revenue per store so regions of different sizes
are directly comparable.

**Source:** `{{ ref('fct_sales') }}`

**Group by:** `year_number`, `quarter_number`, `month_number`, `month_name`,
`region`

**Aggregated columns:**

| Column | Calculation |
|---|---|
| store_count | COUNT(DISTINCT store_id) |
| trading_days | COUNT(DISTINCT full_date) |
| total_transactions | COUNT(*) |
| total_items_sold | SUM(quantity) |
| gross_revenue | SUM(gross_revenue) |
| total_discounts | SUM(discount_amount) |
| net_revenue | SUM(net_revenue) |
| net_revenue_per_store | ROUND(SUM(net_revenue) / NULLIF(COUNT(DISTINCT store_id), 0), 2) |
| net_revenue_per_day | ROUND(SUM(net_revenue) / NULLIF(COUNT(DISTINCT full_date), 0), 2) |
| avg_transaction_value | AVG(net_revenue) |

**Materialisation:** view

**Tests (schema.yml):**
- `net_revenue` — not_null
- `store_count` — not_null

---

## 5. Data Quality Tests

### 5.1 Generic Tests

Defined in `schema.yml` files. Run automatically on `dbt test`.

**not_null** — Applied to every key column and every measure column across
all models. Any null in a measure column indicates a join failure or
calculation error.

**unique** — Applied to `transaction_id` in stg_sales, int_sales_validated,
int_sales_enriched, and fct_sales. Ensures no duplicate rows survive to the
fact table.

**relationships** — Applied to all surrogate keys in fct_sales. Validates
that every `store_key` exists in `dim_store`, every `product_key` in
`dim_product` etc. Catches referential integrity issues at transformation time.

**accepted_values** — Applied to `payment_method`, `category`, `is_refund`,
`validation_status`. Catches unexpected values from source.

### 5.2 Custom Singular Tests

Defined in `tests/`. Each test is a SQL query that returns rows on failure
and zero rows on success. dbt fails the run if any test returns rows.

**tests/assert_no_negative_price.sql**
```sql
-- Fails if any transaction in fct_sales has a non-positive unit_price
-- unit_price should always be > 0 after validation
SELECT *
FROM {{ ref('fct_sales') }}
WHERE unit_price <= 0
```

**tests/assert_valid_discount.sql**
```sql
-- Fails if discount_applied is outside the valid range 0.00 to 1.00
-- 0 = no discount, 1 = 100% discount (free)
SELECT *
FROM {{ ref('fct_sales') }}
WHERE discount_applied < 0
   OR discount_applied > 1
```

### 5.3 Test Execution

```bash
dbt test                          # Run all tests
dbt test --select staging         # Run staging tests only
dbt test --select fct_sales       # Run fct_sales tests only
dbt build                         # Run models AND tests together
```

---

## 6. Documentation

### 6.1 Schema Documentation

Every model and every column gets a description in `schema.yml`.

Example:
```yaml
models:
  - name: fct_sales
    description: >
      Core fact table. One row per transaction line item across all 12
      FranchisePulse locations. Loaded incrementally — new transaction_ids
      are appended on each dbt run, existing rows are never modified.
      Denormalised to include key dimension attributes for query convenience.
    columns:
      - name: transaction_id
        description: >
          Natural key from the source POS system.
          Format: STORE_ID-YYYYMMDD-SEQUENCE e.g. S01-20251201-00042.
          Unique across all stores and dates.
        tests:
          - not_null
          - unique
      - name: net_revenue
        description: >
          Revenue after discount. Calculated as quantity * unit_price *
          (1 - discount_applied). Negative values represent refund
          transactions where quantity < 0.
        tests:
          - not_null
```

### 6.2 Source Documentation

Sources defined in `models/staging/sources.yml`:

```yaml
sources:
  - name: franchisepulse
    database: FranchisePulse
    schema: dbo
    description: FranchisePulse SQL Server database
    tables:
      - name: stg_sales
        description: Raw staged sales data loaded by Airflow ingestion pipeline
        columns:
          - name: validation_status
            description: PASS rows are clean. FAIL rows are quarantined with rejection_reason.
      - name: dim_store
        description: Franchise location reference data. 12 active stores.
      - name: dim_product
        description: Product catalogue. 17 SKUs across 4 categories.
      - name: dim_date
        description: Calendar table covering 2024-01-01 to 2027-12-31.
      - name: dim_payment_method
        description: Payment method lookup. 5 methods.
```

### 6.3 Generating Documentation

```bash
dbt docs generate    # Builds documentation from schema.yml files
dbt docs serve       # Serves documentation at http://localhost:8080
```

The documentation site includes:
- Model descriptions and column definitions
- Full lineage graph (DAG visualisation)
- Test results
- Source definitions

---

## 7. Exposures

Defined in `exposures/reporting.yml`. Documents what downstream systems
consume the mart models. Exposures appear in the lineage graph extending
the chain from raw source all the way to business consumer.

```yaml
version: 2

exposures:

  - name: operations_dashboard
    type: dashboard
    maturity: medium
    url: https://dashboard.damosdatasolutions.com
    description: >
      Daily store performance dashboard for operations team.
      Shows transaction counts, revenue, and refund rates per store per day.
      Refreshed daily after pipeline run completes.
    depends_on:
      - ref('rpt_daily_store')
    owner:
      name: Operations Team
      email: ops@franchisepulse.ie

  - name: finance_weekly_reporting
    type: ml model
    maturity: high
    description: >
      Weekly product mix and regional revenue reports for finance team.
      Used for margin analysis, promotional planning, and regional
      performance review. Distributed as Excel export every Monday.
    depends_on:
      - ref('rpt_weekly_product')
      - ref('rpt_regional_summary')
    owner:
      name: Finance Team
      email: finance@franchisepulse.ie
```

---

## 8. Project Configuration

### 8.1 dbt_project.yml

```yaml
name: franchise_pulse_dbt
version: '1.0.0'
config-version: 2

profile: franchise_pulse

model-paths: ["models"]
test-paths: ["tests"]
macro-paths: ["macros"]
analysis-paths: ["analyses"]

models:
  franchise_pulse_dbt:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: view
      +schema: intermediate
    marts:
      +materialized: view
      +schema: marts
      fct_sales:
        +materialized: incremental
```

### 8.2 profiles.yml (gitignored)

```yaml
franchise_pulse:
  target: dev
  outputs:
    dev:
      type: sqlserver
      driver: "ODBC Driver 18 for SQL Server"
      server: localhost
      port: 1433
      database: FranchisePulse
      schema: dbt
      username: sa
      password: FranchisePulse2024!
      trust_cert: true
```

### 8.3 packages.yml

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```

---

## 9. Repository Structure

```
franchise-pulse-dbt/
├── models/
│   ├── staging/
│   │   ├── sources.yml
│   │   ├── stg_sales.sql
│   │   └── schema.yml
│   ├── intermediate/
│   │   ├── int_sales_validated.sql
│   │   ├── int_sales_enriched.sql
│   │   └── schema.yml
│   └── marts/
│       ├── fct_sales.sql
│       ├── rpt_daily_store.sql
│       ├── rpt_weekly_product.sql
│       ├── rpt_regional_summary.sql
│       └── schema.yml
├── tests/
│   ├── assert_no_negative_price.sql
│   └── assert_valid_discount.sql
├── analyses/
│   └── rejection_summary.sql
├── macros/
│   └── safe_divide.sql
├── exposures/
│   └── reporting.yml
├── docs/
│   └── SPECIFICATION.md
├── dbt_project.yml
├── packages.yml
├── profiles.yml            ← gitignored
├── .gitignore
└── README.md
```

---

## 10. Implementation Phases

### Phase 1 — Environment Setup
**Goal:** dbt installed, connected to SQL Server, debug passing.

Tasks:
1. Create `franchise-pulse-dbt` GitHub repository
2. Clone locally
3. Install dbt Core: `pip install dbt-core dbt-sqlserver`
4. Run `dbt init franchise_pulse_dbt`
5. Configure `profiles.yml` to connect to SQL Server
6. Run `dbt debug` — confirm all checks pass
7. Install packages: `dbt deps`
8. Create `.gitignore` — exclude `profiles.yml`, `target/`, `dbt_packages/`
9. Initial commit

**Deliverable:** `dbt debug` returns all green. Repository exists on GitHub.

---

### Phase 2 — Sources and Staging Model
**Goal:** First model running, first tests passing.

Tasks:
1. Create `models/staging/sources.yml` — define all source tables
2. Write `models/staging/stg_sales.sql`
3. Write `models/staging/schema.yml` — all column descriptions and tests
4. Run `dbt run --select stg_sales`
5. Run `dbt test --select stg_sales`
6. Verify row count matches source PASS rows
7. Commit

**Deliverable:** `stg_sales` view exists in SQL Server. All tests green.

---

### Phase 3 — Intermediate Models
**Goal:** Validation and enrichment logic running, lineage building.

Tasks:
1. Write `models/intermediate/int_sales_validated.sql`
2. Write `models/intermediate/int_sales_enriched.sql`
3. Write `models/intermediate/schema.yml`
4. Run `dbt run --select intermediate`
5. Run `dbt test --select intermediate`
6. Open `dbt docs serve` — verify lineage graph shows correct dependencies
7. Commit

**Deliverable:** Both intermediate views exist. Lineage shows 3-node chain.

---

### Phase 4 — Mart Models
**Goal:** Full pipeline running end to end, fact table loading incrementally.

Tasks:
1. Write `models/marts/fct_sales.sql` with incremental config
2. Write `models/marts/rpt_daily_store.sql`
3. Write `models/marts/rpt_weekly_product.sql`
4. Write `models/marts/rpt_regional_summary.sql`
5. Write `models/marts/schema.yml`
6. Run `dbt run` — full pipeline
7. Run `dbt test` — all tests
8. Query `fct_sales` — verify row counts and revenue figures are correct
9. Run `dbt run` a second time — verify incremental logic adds zero rows
10. Commit

**Deliverable:** All 7 models running. `fct_sales` loaded. Zero test failures.

---

### Phase 5 — Custom Tests and Exposures
**Goal:** Business rule tests added, downstream consumers documented.

Tasks:
1. Write `tests/assert_no_negative_price.sql`
2. Write `tests/assert_valid_discount.sql`
3. Run `dbt test` — verify custom tests pass
4. Write `exposures/reporting.yml`
5. Run `dbt docs generate`
6. Open `dbt docs serve` — verify exposures appear in lineage graph
7. Screenshot lineage graph — source through marts to exposures
8. Commit

**Deliverable:** All tests green including custom tests. Exposures visible in lineage.

---

### Phase 6 — Documentation and README
**Goal:** Project is portfolio-ready. Everything documented.

Tasks:
1. Complete all column descriptions in all `schema.yml` files
2. Complete all model descriptions
3. Run `dbt docs generate` — verify everything renders correctly
4. Write `README.md` (see Section 11)
5. Final `dbt build` — confirm clean run
6. Push to GitHub
7. Tag release v1.0.0

**Deliverable:** Clean GitHub repo. Full documentation. `dbt build` green.

---

## 11. README Outline

The README must cover:

1. **Project summary** — what this is and why it exists
2. **Architecture diagram** — layered model diagram in ASCII
3. **Relationship to FranchisePulse** — how this project connects to Project 3
4. **Quick start** — install, configure, run in under 10 commands
5. **Model reference** — one paragraph per model explaining purpose
6. **Testing approach** — generic vs custom tests, how to run
7. **Lineage screenshot** — the dbt docs lineage graph
8. **Design decisions** — why incremental, why denormalised fct_sales,
   why view vs table materialisation
9. **Interview notes** — talking points for each dbt concept demonstrated

---

## 12. Success Criteria

The project is complete and portfolio-ready when all of the following are true:

| Criterion | How to verify |
|---|---|
| All 7 models run without error | `dbt run` exits 0 |
| All generic tests pass | `dbt test` exits 0 |
| All custom tests pass | `dbt test` exits 0 |
| Incremental logic works | Second `dbt run` inserts 0 rows to fct_sales |
| fct_sales row count is correct | Query count matches source PASS rows |
| Reporting marts match Project 3 views | Manual query comparison |
| Full lineage visible | `dbt docs serve` shows source → marts → exposures |
| All models and columns documented | No blank descriptions in docs site |
| README is complete | Covers all 9 sections listed above |
| Repository is clean | No credentials, no target/ folder, clear commit history |

---

## 13. Interview Talking Points

### Why dbt over stored procedures?
*"Stored procedures live in the database — they're hard to version control,
test independently, and document consistently. dbt models are plain SQL files
in a Git repo. Every change is tracked with a commit. Every model has tests
that run automatically. The documentation generates itself from the code.
It's the difference between transformation logic you manage manually and
transformation logic you can trust."*

### What is incremental materialisation?
*"On the first run, dbt loads every row into fct_sales. On every subsequent
run, it checks which transaction_ids already exist and only inserts new rows.
This means the pipeline gets faster as the table grows, not slower. At the
scale of this project it's a small optimisation. At 100 million rows it's
the difference between a 3-minute run and a 3-hour run."*

### What do dbt tests actually test?
*"Two categories. Generic tests are declared in schema.yml and run against
every model automatically — things like not_null, unique, and referential
integrity checks. Custom singular tests encode specific business rules as SQL
queries that return rows when they fail. If any test returns even one row,
dbt fails the build and nothing downstream gets updated. Data quality is
enforced at transformation time, not discovered when someone questions a
number in a report."*

### What is lineage in dbt?
*"dbt parses every ref() call in your SQL and builds a directed acyclic graph
of your entire transformation layer. You can see that rpt_regional_summary
depends on fct_sales, which depends on int_sales_enriched, which depends on
int_sales_validated, which depends on stg_sales, which reads from the raw
staging table loaded by Airflow. Extend that with exposures and you can see
the full journey from a raw CSV file to a finance report. When something breaks
you know immediately what's affected."*

### Why carry dimension attributes into fct_sales?
*"fct_sales is denormalised — it carries store_name, region, product_name
and other dimension attributes directly rather than requiring joins at query
time. This is a deliberate trade-off. The reporting marts sit on top of a
single table with no joins, which means simple queries and fast results.
The surrogate keys are still present for referential integrity. At larger
scale you'd reconsider this, but for a reporting-focused mart it's the
right call."*

---

*End of Specification*
