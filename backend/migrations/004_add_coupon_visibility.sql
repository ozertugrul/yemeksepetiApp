-- Kupon görünürlüğü ve şehir filtresi desteği
ALTER TABLE coupons
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE coupons
  ADD COLUMN IF NOT EXISTS city TEXT;

CREATE INDEX IF NOT EXISTS idx_coupons_is_public ON coupons(is_public);
CREATE INDEX IF NOT EXISTS idx_coupons_city ON coupons(city);
