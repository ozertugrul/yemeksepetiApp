-- Sipariş değerlendirmeleri + mağaza sahibinin tek-seferlik yanıtı

CREATE TABLE IF NOT EXISTS order_reviews (
    id                  TEXT PRIMARY KEY,
    order_id            TEXT NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    restaurant_id       TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    speed_rating        DOUBLE PRECISION NOT NULL,
    taste_rating        DOUBLE PRECISION NOT NULL,
    presentation_rating DOUBLE PRECISION NOT NULL,
    average_rating      DOUBLE PRECISION NOT NULL,
    comment             TEXT,
    owner_reply         TEXT,
    owner_replied_at    TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_reviews_restaurant_created
    ON order_reviews(restaurant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_reviews_user
    ON order_reviews(user_id);

DO $$ BEGIN
  CREATE TRIGGER trg_order_reviews_updated
    BEFORE UPDATE ON order_reviews
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
