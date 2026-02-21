-- migrations/001_initial_schema.sql
-- Supabase SQL Editor'a yapıştır ve çalıştır.
-- Idempotent — birden çok kez çalıştırmak güvenli (IF NOT EXISTS).

-- 1. pgvector uzantısını etkinleştir
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Kullanıcılar
CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,          -- Firebase UID
    email         TEXT UNIQUE NOT NULL,
    display_name  TEXT,
    role          TEXT NOT NULL DEFAULT 'user', -- 'user' | 'storeOwner' | 'admin'
    city          TEXT,
    phone         TEXT,
    managed_restaurant_id TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Restoranlar
CREATE TABLE IF NOT EXISTS restaurants (
    id                    TEXT PRIMARY KEY,
    owner_id              TEXT REFERENCES users(id),
    name                  TEXT NOT NULL,
    description           TEXT,
    cuisine_type          TEXT,
    image_url             TEXT,
    rating                DOUBLE PRECISION DEFAULT 0,
    delivery_time         TEXT,
    min_order_amount      DOUBLE PRECISION DEFAULT 0,
    is_active             BOOLEAN DEFAULT true,
    city                  TEXT,
    allows_pickup         BOOLEAN DEFAULT false,
    allows_cash_on_del    BOOLEAN DEFAULT false,
    successful_order_count INT DEFAULT 0,
    average_rating        DOUBLE PRECISION DEFAULT 0,
    rating_count          INT DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Menü öğeleri (embedding burada)
CREATE TABLE IF NOT EXISTS menu_items (
    id               TEXT PRIMARY KEY,
    restaurant_id    TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    description      TEXT,
    price            DOUBLE PRECISION NOT NULL,
    image_url        TEXT,
    category         TEXT DEFAULT 'Diğer',
    discount_percent DOUBLE PRECISION DEFAULT 0,
    is_available     BOOLEAN DEFAULT true,
    option_groups    JSONB DEFAULT '[]',      -- MenuItemOptionGroup[] JSON
    suggested_ids    TEXT[] DEFAULT '{}',
    -- Embedding: all-MiniLM-L6-v2 → 384 boyut
    embedding        vector(384),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Kullanıcı adresleri
CREATE TABLE IF NOT EXISTS user_addresses (
    id            TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title         TEXT NOT NULL,
    city          TEXT,
    district      TEXT,
    neighborhood  TEXT,
    street        TEXT,
    building_no   TEXT,
    flat_no       TEXT,
    directions    TEXT,
    is_default    BOOLEAN DEFAULT false,
    phone         TEXT,
    latitude      DOUBLE PRECISION,
    longitude     DOUBLE PRECISION,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. Siparişler
CREATE TABLE IF NOT EXISTS orders (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users(id),
    restaurant_id   TEXT NOT NULL REFERENCES restaurants(id),
    status          TEXT NOT NULL DEFAULT 'pending',
    payment_method  TEXT NOT NULL,
    delivery_address JSONB,                   -- UserAddress snapshot
    items           JSONB NOT NULL DEFAULT '[]', -- OrderItem[] JSON
    subtotal        DOUBLE PRECISION NOT NULL DEFAULT 0,
    delivery_fee    DOUBLE PRECISION DEFAULT 0,
    discount_amount DOUBLE PRECISION DEFAULT 0,
    total_amount    DOUBLE PRECISION NOT NULL DEFAULT 0,
    coupon_code     TEXT,
    notes           TEXT,
    is_rated        BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. Kuponlar
CREATE TABLE IF NOT EXISTS coupons (
    id                   TEXT PRIMARY KEY,
    restaurant_id        TEXT REFERENCES restaurants(id),  -- NULL = global
    code                 TEXT UNIQUE NOT NULL,
    description          TEXT,
    discount_amount      DOUBLE PRECISION DEFAULT 0,
    discount_percent     DOUBLE PRECISION DEFAULT 0,
    minimum_order_amount DOUBLE PRECISION DEFAULT 0,
    expiry_date          TIMESTAMPTZ NOT NULL,
    is_active            BOOLEAN DEFAULT true,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. Kullanıcı kupon kullanımı
CREATE TABLE IF NOT EXISTS user_coupons (
    id          SERIAL PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id),
    coupon_id   TEXT NOT NULL REFERENCES coupons(id),
    used_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, coupon_id)
);

-- ─────────────────────────────
-- INDEKSLER
-- ─────────────────────────────

-- pgvector: IVFFlat, cosine benzerliği (öneri sistemi için)
-- NOT: indeks oluşturmadan önce en az birkaç embedding satırı olmalı.
-- Migration sonrası embedding verisi yüklendi ise aşağıyı ayrıca çalıştır:
-- CREATE INDEX IF NOT EXISTS idx_menu_items_embedding
--   ON menu_items USING ivfflat (embedding vector_cosine_ops)
--   WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant ON menu_items(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_user          ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant    ON orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status        ON orders(status);
CREATE INDEX IF NOT EXISTS idx_addresses_user       ON user_addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_city     ON restaurants(city);
CREATE INDEX IF NOT EXISTS idx_restaurants_active   ON restaurants(is_active);

-- ─────────────────────────────
-- UPDATED_AT otomatik güncelleme
-- ─────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  CREATE TRIGGER trg_restaurants_updated
    BEFORE UPDATE ON restaurants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_menu_items_updated
    BEFORE UPDATE ON menu_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_orders_updated
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_users_updated
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
