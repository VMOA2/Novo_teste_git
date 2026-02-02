CREATE TABLE IF NOT EXISTS public.teste_git (
  id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL
);
