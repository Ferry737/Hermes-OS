-- Core schema. Vector columns live in 002_vectors.sql so the core can be tested without pgvector.
CREATE TABLE system_state (key text PRIMARY KEY, value jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO system_state VALUES ('mode', '"running"', now());

CREATE TABLE runs (
  id bigserial PRIMARY KEY, kind text NOT NULL, period text NOT NULL,
  status text NOT NULL DEFAULT 'open', git_sha text, config_hash text,
  started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
  UNIQUE (kind, period));

CREATE TABLE concepts (
  id bigserial PRIMARY KEY, slug text UNIQUE NOT NULL, title text NOT NULL,
  thesis text NOT NULL, customer text NOT NULL, wedge text NOT NULL,
  archetype text NOT NULL CHECK (archetype IN ('software_infra','payments','lending','marketplace_brokerage','crypto_protocol')),
  geographies text[] NOT NULL, why_now_signal_ids bigint[] NOT NULL DEFAULT '{}',
  state text NOT NULL DEFAULT 'DISCOVERED', research_round int NOT NULL DEFAULT 0,
  merged_into bigint REFERENCES concepts(id), kill_reason text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON concepts (state);

CREATE TABLE tasks (
  id bigserial PRIMARY KEY, run_id bigint REFERENCES runs(id), concept_id bigint REFERENCES concepts(id),
  role text NOT NULL, kind text NOT NULL, payload jsonb NOT NULL DEFAULT '{}',
  idempotency_key text UNIQUE NOT NULL, priority int NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','leased','succeeded','dead')),
  attempts int NOT NULL DEFAULT 0, max_attempts int NOT NULL DEFAULT 4,
  lease_owner text, lease_expires_at timestamptz, not_before timestamptz NOT NULL DEFAULT now(),
  last_error text, result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX tasks_ready ON tasks (role, priority DESC, created_at) WHERE status = 'queued';
CREATE INDEX tasks_leased ON tasks (lease_expires_at) WHERE status = 'leased';
CREATE INDEX tasks_concept ON tasks (concept_id);

CREATE TABLE signals (
  id bigserial PRIMARY KEY, source text NOT NULL, url text NOT NULL, title text,
  published_at timestamptz, retrieved_at timestamptz NOT NULL DEFAULT now(),
  signal_type text, segment text, geography text, summary text,
  content_hash text NOT NULL, UNIQUE (source, content_hash));

CREATE TABLE documents (
  id bigserial PRIMARY KEY, url text NOT NULL, domain text NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now(), http_status int, content_type text,
  content_hash text UNIQUE NOT NULL, raw_path text NOT NULL, text_path text NOT NULL,
  published_at timestamptz, title text);

CREATE TABLE evidence (
  id bigserial PRIMARY KEY, concept_id bigint NOT NULL REFERENCES concepts(id),
  document_id bigint NOT NULL REFERENCES documents(id), claim text NOT NULL, quote text NOT NULL,
  claim_hash text NOT NULL, metric_key text, value numeric, unit text, as_of date,
  verification text NOT NULL DEFAULT 'pending' CHECK (verification IN ('pending','verified','weak','unverified')),
  match_score int, prompt_version text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (concept_id, document_id, claim_hash));

CREATE TABLE evaluations (
  id bigserial PRIMARY KEY, concept_id bigint NOT NULL REFERENCES concepts(id), round int NOT NULL,
  metrics jsonb NOT NULL, moats jsonb NOT NULL, red_team jsonb NOT NULL, red_flags text[] NOT NULL DEFAULT '{}',
  prompt_versions jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (concept_id, round));

CREATE TABLE scores (
  id bigserial PRIMARY KEY, concept_id bigint NOT NULL REFERENCES concepts(id),
  evaluation_id bigint NOT NULL REFERENCES evaluations(id), rubric_version text NOT NULL,
  killed_by text, median numeric, p10 numeric, p90 numeric, confidence numeric, p_band_a numeric, band text,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (evaluation_id, rubric_version));

CREATE TABLE forecasts (
  id bigserial PRIMARY KEY, concept_id bigint NOT NULL REFERENCES concepts(id), week text NOT NULL,
  band text NOT NULL, p_band_a numeric, matched_companies jsonb NOT NULL DEFAULT '[]', UNIQUE (concept_id, week));

CREATE TABLE llm_calls (
  id bigserial PRIMARY KEY, task_id bigint REFERENCES tasks(id), concept_id bigint REFERENCES concepts(id),
  agent text NOT NULL, model text NOT NULL, prompt_version text NOT NULL,
  status text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','settled','released')),
  est_cost_usd numeric NOT NULL, cost_usd numeric, input_tokens int, output_tokens int,
  cache_read_tokens int, cache_write_tokens int, stop_reason text, latency_ms int, batch boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON llm_calls (created_at);
CREATE INDEX ON llm_calls (concept_id);

CREATE TABLE reports (
  id bigserial PRIMARY KEY, kind text NOT NULL, period text NOT NULL, md_path text NOT NULL,
  html_path text NOT NULL, number_check text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (kind, period));

CREATE TABLE events (
  id bigserial PRIMARY KEY, at timestamptz NOT NULL DEFAULT now(), actor text NOT NULL,
  entity text NOT NULL, entity_id bigint, action text NOT NULL, detail jsonb NOT NULL DEFAULT '{}');

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hre_reader') THEN
    CREATE ROLE hre_reader NOLOGIN;
  END IF;
END $$;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hre_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO hre_reader;
