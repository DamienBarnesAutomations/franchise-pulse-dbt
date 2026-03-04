# FranchisePulse dbt Transformation Layer

## What this project is
FranchisePulse dbt is a technical portfolio project demonstrating a modern data transformation layer for a fictional 12-location Irish coffee franchise. It solves the problem of transforming raw, inconsistent POS sales data into a reliable, tested, and documented reporting-ready dataset. This project demonstrates the full dbt development lifecycle—from raw staging to incremental fact tables and aggregated reporting marts—to provide a production-grade template for senior data engineers and hiring managers.

## Architecture
This project implements a layered transformation architecture within dbt, moving data from raw staging to persistent facts and finally to reporting views.

```text
┌─────────────────────────────────────────────────────────────┐
│  SOURCE LAYER (SQL Server)                                  │
│  dbo.stg_sales (raw) | dim_store | dim_product | dim_date   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGING LAYER (models/staging/)                            │
│  stg_sales.sql: Type casting, renaming, filtering PASS rows │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  INTERMEDIATE LAYER (models/intermediate/)                  │
│  int_sales_validated.sql: Business rule filters, measures   │
│  int_sales_enriched.sql: Joins to dimension tables          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  MART LAYER (models/marts/)                                 │
│  fct_sales.sql (Incremental): Persistent transaction grain  │
│  rpt_daily_store.sql: Aggregated performance metrics        │
│  rpt_weekly_product.sql: Product mix analysis               │
│  rpt_regional_summary.sql: Executive regional rollups       │
└─────────────────────────────────────────────────────────────┘
```

## Tech stack

| Component | Technology | Purpose |
| :--- | :--- | :--- |
| Transformation | dbt Core 1.8+ | Model management, testing, and documentation |
| Database | SQL Server 2022 | Data warehouse and storage engine |
| Runtime | Docker | Containerized environment for consistent execution |
| Language | SQL (T-SQL) | Transformation logic and data modeling |
| Documentation | dbt Docs | Automated lineage and data dictionary |

## Project structure
```text
C:\Users\damie\projects\franchise-pulse-dbt\
├── dbt_project.yml        # Core dbt configuration and model settings
├── docker-compose.yml     # Orchestration for the dbt container
├── Dockerfile.dbt         # Environment definition with dbt and SQL drivers
├── packages.yml           # External dbt package dependencies (dbt_utils)
├── analyses/              # Ad-hoc SQL analysis files
├── exposures/             # Documentation of downstream dashboard consumers
│   └── reporting.yml      # Defines Finance and Operations reporting links
├── macros/                # Reusable SQL logic and helper functions
├── models/                # SQL transformation logic organized by layer
│   ├── staging/           # Initial cleanup and casting of raw source data
│   ├── intermediate/      # Business validation and dimension enrichment
│   └── marts/             # Reporting-ready fact and summary models
└── tests/                 # Custom singular data quality tests
    ├── assert_no_negative_price.sql
    └── assert_valid_discount.sql
```

## Quick start
Assume you have Docker and Git installed. Ensure your SQL Server instance is reachable from the container.

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-repo/franchise-pulse-dbt.git
   cd franchise-pulse-dbt
   ```

2. **Configure profiles.yml**
   Create a `profiles.yml` in the project root (or `~/.dbt/`) with your SQL Server credentials following the template in `SPECIFICATION.md`.

3. **Build the container and run dbt**
   ```bash
   docker-compose run dbt deps
   docker-compose run dbt build
   ```

4. **Generate and view documentation**
   ```bash
   docker-compose run -p 8081:8081 dbt docs generate
   docker-compose run -p 8081:8081 dbt docs serve --port 8081
   ```

## How it works
The pipeline processes data through four distinct stages:

1.  **Staging (`stg_sales.sql`)**: Reads from the `franchisepulse.stg_sales` source. It filters for rows where `validation_status = 'PASS'`, casts `VARCHAR` inputs to `DATETIME2` and `DECIMAL` types, and standardizes null values for columns like `cashier_id`.
2.  **Validation (`int_sales_validated.sql`)**: Applies business logic filters, such as excluding transactions with non-positive unit prices or dates outside the valid range. It calculates measures like `gross_revenue` and `net_revenue`.
3.  **Enrichment (`int_sales_enriched.sql`)**: Performs inner joins between the validated sales and four dimension tables (`dim_store`, `dim_product`, `dim_date`, `dim_payment_method`) to resolve natural keys into surrogate keys and pull in attributes like `region` and `category`.
4.  **Persistence (`fct_sales.sql`)**: Uses `incremental` materialization to append only new `transaction_id` records that do not already exist in the target table. This ensures the model scales efficiently as the transaction volume grows.
5.  **Aggregation (`rpt_daily_store.sql`, etc.)**: Final mart models aggregate the incremental fact table into summary views for specific business domains, such as daily store performance or regional summaries.

## Design decisions

*   **Incremental Materialization for `fct_sales`**: We chose an incremental strategy with a `unique_key` constraint to prevent full table scans and re-processing of historical data. This ensures the transformation remains performant as the franchise scales from thousands to millions of transactions.
*   **Layered Modeling (Staging → Intermediate → Marts)**: By separating type casting from business logic and enrichment, we ensure that errors are caught early in the pipeline. This modularity allows for easier debugging and independent testing of each transformation stage.
*   **Denormalized Marts**: Mart models like `fct_sales` carry dimension attributes (e.g., `store_name`, `region`) directly. This trade-off prioritizes reporting performance and simplicity for BI tools by eliminating complex join requirements at the query layer.
*   **Declarative Data Quality**: We use a combination of generic YAML tests for relational integrity and custom SQL singular tests for business rules. This ensures that a build fails immediately if data quality thresholds are not met, preventing bad data from reaching downstream reports.

## What this demonstrates
This project proves several key data engineering competencies:

*   **dbt Lifecycle Management**: Experience with model layering, materialization strategies, and package management.
*   **Data Modeling**: Ability to design and implement star-schema-aligned datasets, including surrogate key management and denormalization.
*   **Automated Testing**: Implementation of a "shift-left" data quality strategy using generic and custom SQL tests.
*   **Environment Orchestration**: Use of Docker to ensure a portable, reproducible transformation environment.
*   **Documentation as Code**: Leveraging dbt exposures and schema files to provide clear lineage and data definitions for stakeholders.
