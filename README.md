# FranchisePulse dbt Transformation Layer

## Project Overview
FranchisePulse dbt is a modern data transformation layer built on top of a retail sales pipeline for a fictional 12-location Irish coffee franchise. It transforms raw POS sales data into a clean, tested, and documented reporting-ready data model.

## Architecture
The project follows a layered transformation architecture:

```
SOURCE LAYER (dbo.stg_sales)
      │
      ▼
STAGING LAYER (models/staging/stg_sales.sql)
      │
      ▼
INTERMEDIATE LAYER (models/intermediate/)
      │  ├─ int_sales_validated.sql
      │  └─ int_sales_enriched.sql
      ▼
MART LAYER (models/marts/)
      ├─ fct_sales.sql (Incremental)
      ├─ rpt_daily_store.sql
      ├─ rpt_weekly_product.sql
      └─ rpt_regional_summary.sql
      │
      ▼
CONSUMPTION LAYER (Exposures)
```

## Tech Stack
- **dbt Core 1.11**
- **SQL Server 2022** (Dockerized)
- **Python 3.12**
- **Docker & Docker Compose**

## Quick Start
1. **Clone the repository**
2. **Start the environment:**
   ```bash
   docker-compose up -d sqlserver
   docker-compose build dbt
   ```
3. **Initialize the database:**
   ```bash
   # Create database and populate sample data
   Get-Content setup_data.sql | docker exec -i franchise-pulse-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'FranchisePulse2024!' -C
   ```
4. **Run dbt:**
   ```bash
   docker-compose run --rm dbt deps
   docker-compose run --rm dbt run --full-refresh
   docker-compose run --rm dbt test
   ```

## Key Features
- **Incremental Materialization:** `fct_sales` uses dbt's incremental pattern for performance.
- **Data Quality:** 40+ tests including generic (not null, unique, relationships) and custom singular tests.
- **Documentation:** Full lineage and column-level documentation.
- **Exposures:** Documented downstream consumers (Dashboards, Finance Reports).

## Design Decisions
- **Denormalized Marts:** Mart models carry dimension attributes directly to minimize joins at the reporting layer.
- **Layered approach:** Logic is separated into cleaning (staging), business rules (intermediate), and reporting (marts).
- **Dockerized Environment:** Ensures consistency across different development machines.

