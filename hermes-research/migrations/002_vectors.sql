-- Embedding columns for de-duplication (bge-small-en-v1.5, 384 dims).
-- Production runs the pgvector image, where this always applies. Without pgvector the
-- migration fails loudly, unless the session sets hre.allow_no_vector = 'on' (tests only).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vector') THEN
    CREATE EXTENSION IF NOT EXISTS vector;
    ALTER TABLE concepts ADD COLUMN IF NOT EXISTS embedding vector(384);
    ALTER TABLE signals  ADD COLUMN IF NOT EXISTS embedding vector(384);
    CREATE INDEX IF NOT EXISTS concepts_embedding ON concepts USING hnsw (embedding vector_cosine_ops);
    CREATE INDEX IF NOT EXISTS signals_embedding  ON signals  USING hnsw (embedding vector_cosine_ops);
  ELSIF coalesce(current_setting('hre.allow_no_vector', true), 'off') = 'on' THEN
    RAISE NOTICE 'pgvector not available; skipping embedding columns (hre.allow_no_vector=on)';
  ELSE
    RAISE EXCEPTION 'pgvector extension is not available; use the pgvector/pgvector image';
  END IF;
END $$;
