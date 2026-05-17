# SQL Layer — Database Setup & Queries
This folder contains everything needed to recreate the RetailLens PostgreSQL database and run the analytical queries.

## Prerequisites
- PostgreSQL 18 installed and running locally
- Python 3.10+ with a virtual environment
- All 11 Olist CSVs downloaded from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), (https://www.kaggle.com/datasets/olistbr/marketing-funnel-olist) and placed in the `data/` folder

## Setup — Step by Step

**1. Create a virtual environment and install dependencies**
```bash
python -m venv venv

# Activate it
source venv/bin/activate        # Mac/Linux
venv\Scripts\activate           # Windows

pip install -r requirements.txt
```

**2. Set up your credentials**
```bash
cp .env.example .env
```
Open `.env` and fill in your PostgreSQL password. Everything else (host, port, db name) can stay as-is for a standard local setup.

**3. Create the database**
```bash
createdb retaillens
```

**4. Create the tables**
This runs `schema.sql` which creates all 11 empty tables with proper data types, foreign keys, and indexes.
```bash
psql -U postgres -d retaillens -f sql/schema.sql
```

You should see a series of `CREATE TABLE` and `CREATE INDEX` lines with no errors.

**5. Load the data**
```bash
python scripts/load_to_postgres.py
```

## Running Queries

**Option A — psql terminal**
```bash
psql -U postgres -d retaillens
```
Then paste any query from `queries.sql` directly. Or run the whole file:
```bash
psql -U postgres -d retaillens -f sql/queries.sql
```

**Option B — pgAdmin (recommended for visual output)**

1. Open pgAdmin 4
2. Connect to your local server
3. Navigate to retaillens database
4. Open the Query Tool (Tools → Query Tool)
5. Paste queries from `queries.sql` and hit Run (F5)

---