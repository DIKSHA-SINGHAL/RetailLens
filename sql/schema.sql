-- =============================================================
-- WHAT THIS FILE DOES:
--   Creates 11 empty tables in your PostgreSQL database.
--   Run this once before loading any data.
--
-- WHY WE NEED THIS:
--   PostgreSQL is strict about types. You tell it upfront:
--   "this column holds text", "this one holds decimals".
--   It then enforces that. SQLite lets you skip this step — Postgres does not.
--
-- HOW TO RUN:
--   psql -d retaillens -f sql/schema.sql
--
-- HOW TO RE-RUN (if you mess up and want to start fresh):
--   Just run it again. The DROP TABLE lines at the top will
--   wipe existing tables before recreating them.
-- =============================================================


-- -------------------------------------------------------------
-- SAFETY: Drop tables if they already exist.
-- "CASCADE" means: if another table depends on this one
-- (via foreign key), drop that too. Order matters here —
-- child tables must be dropped before parent tables.
-- -------------------------------------------------------------
DROP TABLE IF EXISTS closed_deals          CASCADE;
DROP TABLE IF EXISTS mql                   CASCADE;
DROP TABLE IF EXISTS order_reviews         CASCADE;
DROP TABLE IF EXISTS order_payments        CASCADE;
DROP TABLE IF EXISTS order_items           CASCADE;
DROP TABLE IF EXISTS orders                CASCADE;
DROP TABLE IF EXISTS geolocation           CASCADE;
DROP TABLE IF EXISTS category_translation  CASCADE;
DROP TABLE IF EXISTS products              CASCADE;
DROP TABLE IF EXISTS sellers               CASCADE;
DROP TABLE IF EXISTS customers             CASCADE;


-- =============================================================
-- DATA TYPE CHEAT SHEET (used below):
--   VARCHAR(n)    → text with a max length of n characters
--   CHAR(2)       → exactly 2 characters (used for state codes)
--   TEXT          → unlimited text (used for review messages)
--   SMALLINT      → whole number, -32k to +32k (small counts)
--   INTEGER       → whole number, up to ~2 billion
--   NUMERIC(p,s)  → decimal. p = total digits, s = after decimal
--                   NUMERIC(10,2) → up to 99999999.99
--   TIMESTAMP     → date + time: "2017-10-02 10:56:33"
--   DATE          → date only: "2017-10-02"
-- =============================================================


-- -------------------------------------------------------------
-- TABLE 1: customers
-- Each row = one customer account.
-- customer_id ties to orders. customer_unique_id identifies
-- the real human across multiple accounts.
-- -------------------------------------------------------------
CREATE TABLE customers (
    customer_id              VARCHAR(32)  NOT NULL,  -- ties to orders table
    customer_unique_id       VARCHAR(32)  NOT NULL,  -- real person identifier (use for RFM)
    customer_zip_code_prefix INTEGER,
    customer_city            VARCHAR(60),
    customer_state           CHAR(2),                -- e.g. "SP", "RJ"
    PRIMARY KEY (customer_id)
);


-- -------------------------------------------------------------
-- TABLE 2: sellers
-- Each row = one seller on the Olist marketplace.
-- -------------------------------------------------------------
CREATE TABLE sellers (
    seller_id               VARCHAR(32)  NOT NULL,
    seller_zip_code_prefix  INTEGER,
    seller_city             VARCHAR(60),
    seller_state            CHAR(2),
    PRIMARY KEY (seller_id)
);


-- -------------------------------------------------------------
-- TABLE 3: products
-- Each row = one product listing.
-- -------------------------------------------------------------
CREATE TABLE products (
    product_id                   VARCHAR(32)   NOT NULL,
    product_category_name        VARCHAR(100),           -- Portuguese, joined to translation table
    product_name_lenght          SMALLINT,               -- character count of product name
    product_description_lenght   INTEGER,                -- character count of description
    product_photos_qty           SMALLINT,               -- number of photos uploaded
    product_weight_g             NUMERIC(10,2),
    product_length_cm            NUMERIC(6,2),
    product_height_cm            NUMERIC(6,2),
    product_width_cm             NUMERIC(6,2),
    PRIMARY KEY (product_id)
);


-- -------------------------------------------------------------
-- TABLE 4: category_translation
-- Maps Portuguese category names to English.
-- 71 rows. Used in every category-level revenue query.
-- -------------------------------------------------------------
CREATE TABLE category_translation (
    product_category_name          VARCHAR(100)  NOT NULL,  -- Portuguese (joins to products)
    product_category_name_english  VARCHAR(100),
    PRIMARY KEY (product_category_name)
);


-- -------------------------------------------------------------
-- TABLE 5: geolocation
-- Zip code to lat/lng coordinates.
-- No primary key — zip codes repeat with slightly different coords.
-- -------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix  INTEGER,
    geolocation_lat              NUMERIC(10,6),  -- 6 decimal places = ~10cm precision
    geolocation_lng              NUMERIC(10,6),
    geolocation_city             VARCHAR(100),
    geolocation_state            CHAR(2)
);


-- -------------------------------------------------------------
-- TABLE 6: orders
-- The central fact table. Every order in the system.
-- 99,441 rows. Almost every query in this project starts here.
--
-- KEY THING TO UNDERSTAND:
--   An "order" is just the header record. The actual products
--   and prices live in order_items. The payment amount lives
--   in order_payments. This is normal relational design —
--   one order can have many items and multiple payment methods.
-- -------------------------------------------------------------
CREATE TABLE orders (
    order_id                      VARCHAR(32)  NOT NULL,
    customer_id                   VARCHAR(32)  NOT NULL,
    order_status                  VARCHAR(20),            -- e.g. "delivered", "canceled"
    order_purchase_timestamp      TIMESTAMP,              -- when customer clicked buy
    order_approved_at             TIMESTAMP,              -- when payment was confirmed
    order_delivered_carrier_date  TIMESTAMP,              -- when seller handed to courier
    order_delivered_customer_date TIMESTAMP,              -- when customer received it (nullable!)
    order_estimated_delivery_date TIMESTAMP,              -- what Olist promised
    PRIMARY KEY (order_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
    -- FOREIGN KEY means: customer_id here must exist in the customers table.
    -- Postgres will reject an order with an unknown customer.
);


-- -------------------------------------------------------------
-- TABLE 7: order_items
-- One row per ITEM in an order, not per order.
-- An order with 3 products = 3 rows here, same order_id.
-- order_item_id is just 1, 2, 3 within that order.
--
-- price       = what the customer paid for the product
-- freight_value = shipping cost for that item
-- -------------------------------------------------------------
CREATE TABLE order_items (
    order_id             VARCHAR(32)   NOT NULL,
    order_item_id        SMALLINT      NOT NULL,  -- 1 = first item, 2 = second, etc.
    product_id           VARCHAR(32),
    seller_id            VARCHAR(32),
    shipping_limit_date  TIMESTAMP,               -- deadline for seller to ship
    price                NUMERIC(10,2),
    freight_value        NUMERIC(8,2),
    PRIMARY KEY (order_id, order_item_id),        -- composite key: order + item sequence
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (seller_id)  REFERENCES sellers(seller_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);


-- -------------------------------------------------------------
-- TABLE 8: order_payments
-- One row per PAYMENT METHOD per order.
--
-- !! IMPORTANT !!
--   One order can have multiple rows here.
--   Example: R$200 by credit card + R$50 voucher = 2 rows,
--   same order_id.
--   Always use SUM(payment_value) grouped by order_id.
--   Never use COUNT(*) to count orders from this table.
--
-- payment_sequential: 1 = primary method, 2+ = additional
-- -------------------------------------------------------------
CREATE TABLE order_payments (
    order_id              VARCHAR(32)  NOT NULL,
    payment_sequential    SMALLINT,
    payment_type          VARCHAR(20),   -- "credit_card", "boleto", "voucher", "debit_card"
    payment_installments  SMALLINT,      -- number of monthly installments chosen
    payment_value         NUMERIC(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);


-- -------------------------------------------------------------
-- TABLE 9: order_reviews
-- Customer review submitted after delivery.
-- review_score: 1 (worst) to 5 (best).
-- Comment fields are nullable — most customers skip text.
-- -------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id               VARCHAR(32),
    order_id                VARCHAR(32),
    review_score            SMALLINT,    -- 1 to 5
    review_comment_title    TEXT,        -- short title, often null
    review_comment_message  TEXT,        -- full message, usually null
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);


-- -------------------------------------------------------------
-- TABLE 10: mql (Marketing Qualified Leads)
-- Sellers who showed interest in joining Olist.
-- 8,000 leads entered the funnel. Only 842 converted (~10.5%).
-- origin = which channel brought them in (organic, paid, email)
-- -------------------------------------------------------------
CREATE TABLE mql (
    mql_id              VARCHAR(32)  NOT NULL,
    first_contact_date  DATE,
    landing_page_id     VARCHAR(32),
    origin              VARCHAR(30),
    PRIMARY KEY (mql_id)
);


-- -------------------------------------------------------------
-- TABLE 11: closed_deals
-- The 842 leads who became sellers.
-- Joins to mql via mql_id, and to sellers via seller_id.
-- declared_monthly_revenue = self-reported by seller, not verified.
-- -------------------------------------------------------------
CREATE TABLE closed_deals (
    mql_id                        VARCHAR(32),
    seller_id                     VARCHAR(32),
    sdr_id                        VARCHAR(32),   -- sales development rep ID
    sr_id                         VARCHAR(32),   -- sales rep who closed the deal
    won_date                      TIMESTAMP,
    business_segment              VARCHAR(60),
    lead_type                     VARCHAR(40),
    lead_behaviour_profile        VARCHAR(20),
    has_company                   BOOLEAN,
    has_gtin                      BOOLEAN,
    average_stock                 VARCHAR(20),
    business_type                 VARCHAR(30),
    declared_product_catalog_size NUMERIC(12,2),
    declared_monthly_revenue      NUMERIC(14,2),
    FOREIGN KEY (mql_id)    REFERENCES mql(mql_id)
);


-- =============================================================
-- INDEXES
-- =============================================================
-- WHY INDEXES?
--   Without an index, Postgres scans every row to find matches.
--   With an index, it jumps straight to the right rows — like
--   a book index vs reading every page.
--
--   Rule: index columns you JOIN on or filter with WHERE often.
--   We add them after table creation (data loads faster this way).
-- =============================================================

CREATE INDEX idx_orders_status   ON orders(order_status);         -- filtered in almost every query
CREATE INDEX idx_orders_purchase ON orders(order_purchase_timestamp); -- monthly grouping
CREATE INDEX idx_orders_customer ON orders(customer_id);          -- joining to customers
CREATE INDEX idx_items_seller    ON order_items(seller_id);       -- seller performance queries
CREATE INDEX idx_items_product   ON order_items(product_id);      -- category revenue queries
CREATE INDEX idx_payments_order  ON order_payments(order_id);     -- joining from orders
CREATE INDEX idx_reviews_order   ON order_reviews(order_id);      -- joining from orders
CREATE INDEX idx_products_cat    ON products(product_category_name); -- category joins
CREATE INDEX idx_customers_state ON customers(customer_state);    -- state-level aggregations