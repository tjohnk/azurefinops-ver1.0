# No-CSV ingestion

1. Azure DevOps collector writes JSON to ADLS Gen2/Blob.
2. Configure an Azure Data Explorer data connection / ingestion job to ingest JSON into the tables in schema.csl.
3. Cost Management Export lands cost data in ADLS and is ingested into CostFact.
4. Power BI connects only to ADX.

For very large estates, an ETL step can convert JSON landing data to Parquet before ADX ingestion. This is an optimization; Power BI remains ADX-only.
