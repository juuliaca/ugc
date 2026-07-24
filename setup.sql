-- =============================================================
-- SETUP DO BANCO DE DADOS DO PAINEL
-- Rode este arquivo inteiro no SQL Editor do Supabase:
-- Project > SQL Editor > New query > cole tudo > Run.
-- =============================================================

-- Tabela de eventos do site: visitas, cliques em botões e vídeos vistos.
create table if not exists portfolio_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,        -- 'page_view' | 'button_click' | 'video_view'
  event_name text,                 -- nome do evento (ex: id do vídeo no YouTube, nome do botão)
  session_id text,                 -- identifica um visitante/sessão no navegador
  page_path text,                  -- caminho da página onde o evento aconteceu
  metadata jsonb,                  -- dados extras (title, brand, category, etc.)
  created_at timestamptz not null default now()
);

-- Tabela de mensagens recebidas pelo formulário de contato e pelo pop-up.
create table if not exists portfolio_leads (
  id uuid primary key default gen_random_uuid(),
  name text,
  email text,
  phone text,
  brand text,
  budget text,
  message text,
  source text,                     -- 'contact' | 'popup'
  created_at timestamptz not null default now()
);

-- Índices pela data de criação: as duas tabelas são sempre lidas
-- ordenadas por created_at (inclusive na paginação do painel), então
-- isso deixa essa consulta mais rápida conforme os dados crescem.
create index if not exists idx_portfolio_events_created_at on portfolio_events (created_at desc);
create index if not exists idx_portfolio_leads_created_at on portfolio_leads (created_at desc);

-- Liga a segurança em nível de linha (Row Level Security) nas duas tabelas.
-- Sem isso, por padrão o Supabase bloqueia qualquer leitura de fora.
alter table portfolio_events enable row level security;
alter table portfolio_leads enable row level security;

-- Só um usuário autenticado (ou seja, você logada no painel através do
-- Supabase Auth) pode LER essas tabelas.
create policy "Painel autenticado pode ler eventos"
  on portfolio_events for select
  to authenticated
  using (true);

create policy "Painel autenticado pode ler leads"
  on portfolio_leads for select
  to authenticated
  using (true);

-- IMPORTANTE: de propósito, não existe nenhuma policy de INSERT, UPDATE
-- ou DELETE aqui. A gravação desses eventos (quando alguém visita o site,
-- clica num botão ou assiste um vídeo) deve vir do próprio site do
-- portfólio através de um servidor ou função com a chave de serviço
-- (service role), nunca direto do navegador com a chave anon/pública.
-- Se a escrita usasse a chave anon, qualquer pessoa que abrisse o
-- código do site poderia forjar ou apagar os seus números.
