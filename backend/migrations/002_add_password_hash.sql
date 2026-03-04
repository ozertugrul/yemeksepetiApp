-- users tablosuna local auth için password hash alanı ekle
ALTER TABLE users
ADD COLUMN IF NOT EXISTS password_hash TEXT;
