-- migrations/002_add_password_hash.sql
-- Firebase'den kendi auth sistemine geçiş.
-- users tablosuna password_hash kolonu ekle.
-- Mevcut kullanıcı satırları NULL kalır.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS password_hash TEXT;
