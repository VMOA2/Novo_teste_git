-- Migration: 20250131_create_test_table_cron_bucket
-- Descrição: Cria tabela de teste com tipos complexos, RLS, cron job e storage bucket

-- ============================================================
-- 1. ENUM TYPES
-- ============================================================

CREATE TYPE public.status_type AS ENUM (
  'draft',
  'pending',
  'active',
  'suspended',
  'archived'
);

CREATE TYPE public.priority_level AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

CREATE TYPE public.category_type AS ENUM (
  'general',
  'finance',
  'engineering',
  'marketing',
  'support'
);

-- ============================================================
-- 2. TABELA PRINCIPAL COM TIPOS COMPLEXOS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.test_records (
  -- Identificadores
  id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  external_ref        uuid          UNIQUE NOT NULL DEFAULT gen_random_uuid(),

  -- Campos básicos
  title               text          NOT NULL CHECK (char_length(title) BETWEEN 1 AND 255),
  description         text,
  slug                text          UNIQUE GENERATED ALWAYS AS (
                                      lower(regexp_replace(title, '[^a-zA-Z0-9]+', '-', 'g'))
                                    ) STORED,

  -- Enums
  status              public.status_type      NOT NULL DEFAULT 'draft',
  priority            public.priority_level   NOT NULL DEFAULT 'medium',
  category            public.category_type    NOT NULL DEFAULT 'general',

  -- Numéricos e monetários
  score               numeric(10, 2)  DEFAULT 0 CHECK (score >= 0),
  amount              numeric(15, 2)  CHECK (amount IS NULL OR amount >= 0),
  counter             bigint          NOT NULL DEFAULT 0,

  -- Booleanos
  is_published         boolean        NOT NULL DEFAULT false,
  is_featured          boolean        NOT NULL DEFAULT false,

  -- Arrays (tipos compostos)
  tags                text[]          DEFAULT '{}',
  scores_history      numeric[]       DEFAULT '{}',
  related_ids         uuid[]          DEFAULT '{}',

  -- JSONB (dados semi-estruturados)
  metadata            jsonb           DEFAULT '{}'::jsonb,
  config              jsonb,

  -- Range types
  valid_range         int4range,
  active_period       tstzrange,

  -- Timestamps
  created_at          timestamptz     NOT NULL DEFAULT now(),
  updated_at          timestamptz     NOT NULL DEFAULT now(),
  published_at        timestamptz,
  expires_at          timestamptz     CHECK (expires_at IS NULL OR expires_at > created_at),

  -- Relação com usuário autenticado
  owner_id            uuid            NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Constraint composta: só permite publicar se status for 'active'
  CONSTRAINT chk_published_requires_active
    CHECK (NOT is_published OR status = 'active')
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_test_records_owner      ON public.test_records (owner_id);
CREATE INDEX IF NOT EXISTS idx_test_records_status     ON public.test_records (status);
CREATE INDEX IF NOT EXISTS idx_test_records_tags       ON public.test_records USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_test_records_metadata   ON public.test_records USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_test_records_created_at ON public.test_records (created_at DESC);

-- Trigger para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_test_records_updated_at
  BEFORE UPDATE ON public.test_records
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- 3. ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.test_records ENABLE ROW LEVEL SECURITY;

-- Usuários autenticados só veem seus próprios registros
CREATE POLICY "Authenticated users can select own records"
  ON public.test_records
  FOR SELECT
  USING (auth.uid() = owner_id);

-- Usuários autenticados só criam registros para si mesmos
CREATE POLICY "Authenticated users can insert own records"
  ON public.test_records
  FOR INSERT
  WITH CHECK (auth.uid() = owner_id);

-- Usuários autenticados só atualizam seus próprios registros
CREATE POLICY "Authenticated users can update own records"
  ON public.test_records
  FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Usuários autenticados só deletam seus próprios registros
CREATE POLICY "Authenticated users can delete own records"
  ON public.test_records
  FOR DELETE
  USING (auth.uid() = owner_id);

-- Registros publicados são visíveis para todos (incluindo anônimos)
CREATE POLICY "Published records are visible to everyone"
  ON public.test_records
  FOR SELECT
  USING (is_published = true);

-- ============================================================
-- 4. CRON JOB (pg_cron)
-- Agenda um job que arquiva registros expirados a cada hora
-- ============================================================

SELECT cron.schedule(
  'archive_expired_test_records',       -- nome do job
  '0 * * * *',                          -- cron expression: a cada hora no minuto 0
  $$
    UPDATE public.test_records
    SET status = 'archived',
        updated_at = now()
    WHERE expires_at IS NOT NULL
      AND expires_at < now()
      AND status != 'archived';
  $$
);

-- ============================================================
-- 5. STORAGE BUCKET
-- Cria um bucket para uploads relacionados aos test_records
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'test-record-attachments',
  'test-record-attachments',
  false,                                          -- bucket privado
  10485760,                                       -- limite: 10 MB por arquivo
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- RLS do Storage: usuários só acessam arquivos na pasta do próprio owner_id
-- Padrão de caminho: test-record-attachments/{owner_id}/{record_id}/arquivo.png

CREATE POLICY "Users can upload own attachments"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'test-record-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can read own attachments"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'test-record-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can update own attachments"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'test-record-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users can delete own attachments"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'test-record-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
