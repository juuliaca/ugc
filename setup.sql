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
-- Supabase Auth) pode LER essas tabelas. "drop policy if exists" antes de
-- cada uma deixa esse arquivo seguro de rodar de novo no futuro, sem dar
-- erro de "a policy já existe".
drop policy if exists "Painel autenticado pode ler eventos" on portfolio_events;
create policy "Painel autenticado pode ler eventos"
  on portfolio_events for select
  to authenticated
  using (true);

drop policy if exists "Painel autenticado pode ler leads" on portfolio_leads;
create policy "Painel autenticado pode ler leads"
  on portfolio_leads for select
  to authenticated
  using (true);

-- O site público (index.html) roda inteiro no navegador de quem visita,
-- sem nenhum servidor por trás, e por isso ele grava esses eventos usando
-- a mesma chave pública (anon) que já está exposta no código do site.
-- Para isso não virar uma porta aberta, a policy abaixo libera só GRAVAR
-- (insert) pra quem não está logado, nunca ler, alterar ou apagar: mesmo
-- que alguém veja a chave anon no código, só consegue adicionar linhas
-- novas (na pior das hipóteses, "lixo" nos números), nunca enxergar,
-- editar ou apagar os dados que já existem. Isso continua reservado
-- só para quem está autenticada no painel, pela regra de leitura acima.
drop policy if exists "Site publico pode registrar eventos" on portfolio_events;
create policy "Site publico pode registrar eventos"
  on portfolio_events for insert
  to anon
  with check (true);

drop policy if exists "Site publico pode enviar mensagens" on portfolio_leads;
create policy "Site publico pode enviar mensagens"
  on portfolio_leads for insert
  to anon
  with check (true);

-- A policy acima só funciona junto com esta permissão de gravação: no
-- Postgres, a policy (RLS) decide QUAIS linhas passam, mas a role
-- "anon" também precisa ter a permissão básica de INSERT na tabela,
-- senão a gravação é barrada antes mesmo de chegar a olhar a policy.
grant insert on portfolio_events to anon;
grant insert on portfolio_leads to anon;

-- =============================================================
-- FINANCEIRO: lançamentos (entradas/saídas, pessoal/empresa) e a
-- meta de economia. Ao contrário das tabelas acima, essas duas são
-- de uso 100% privado: só quem está logada no painel pode ler ou
-- escrever, o site público nunca toca nelas.
-- =============================================================
create table if not exists portfolio_financeiro (
  id uuid primary key default gen_random_uuid(),
  tipo text not null,               -- 'entrada' | 'saida'
  esfera text not null,             -- 'pessoal' | 'empresa'
  categoria text not null,
  descricao text,
  valor numeric(12,2) not null,
  data date not null,               -- data do lançamento (escolhida por você, não a de gravação)
  status text not null default 'confirmado', -- 'confirmado' | 'pendente' (dinheiro que ainda não entrou/saiu)
  created_at timestamptz not null default now()
);
create index if not exists idx_portfolio_financeiro_data on portfolio_financeiro (data desc);

-- Garante a coluna "status" mesmo se a tabela já existia de antes
-- (rodar este arquivo de novo depois de já ter usado o painel).
alter table portfolio_financeiro add column if not exists status text not null default 'confirmado';

-- Guarda a meta de economia numa única linha (id sempre = 1): salvar
-- uma meta nova sobrescreve essa mesma linha em vez de criar outra.
create table if not exists portfolio_meta_economia (
  id int primary key default 1,
  valor_meta numeric(12,2) not null default 0,
  atualizado_em timestamptz not null default now(),
  constraint um_unico_registro check (id = 1)
);
insert into portfolio_meta_economia (id, valor_meta)
  values (1, 0)
  on conflict (id) do nothing;

alter table portfolio_financeiro enable row level security;
alter table portfolio_meta_economia enable row level security;

-- "for all" cobre select/insert/update/delete de uma vez: quem está
-- logada no painel pode ler, lançar, editar e apagar seus próprios
-- lançamentos e a meta.
drop policy if exists "Painel autenticado gerencia financeiro" on portfolio_financeiro;
create policy "Painel autenticado gerencia financeiro"
  on portfolio_financeiro for all
  to authenticated
  using (true)
  with check (true);

drop policy if exists "Painel autenticado gerencia meta" on portfolio_meta_economia;
create policy "Painel autenticado gerencia meta"
  on portfolio_meta_economia for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete on portfolio_financeiro to authenticated;
grant select, insert, update, delete on portfolio_meta_economia to authenticated;

-- =============================================================
-- DESPESAS FIXAS: itens que se repetem todo mês (aluguel, assinatura,
-- etc.). Você cadastra uma vez só; o painel lança automaticamente um
-- registro em portfolio_financeiro pra cada uma, todo mês, ao abrir a
-- aba Financeiro (sem duplicar, graças à coluna origem_fixa_id abaixo).
-- =============================================================
create table if not exists portfolio_despesas_fixas (
  id uuid primary key default gen_random_uuid(),
  tipo text not null default 'saida',   -- quase sempre 'saida', mas aceita 'entrada' (ex: renda fixa)
  esfera text not null,                 -- 'pessoal' | 'empresa'
  categoria text not null,
  descricao text,
  valor numeric(12,2) not null,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

-- Marca, em cada lançamento gerado automaticamente, de qual despesa
-- fixa ele veio. "on delete set null" faz o lançamento já lançado
-- continuar existindo normalmente mesmo se a despesa fixa for apagada
-- depois (só para de gerar linhas novas dali em diante).
alter table portfolio_financeiro
  add column if not exists origem_fixa_id uuid references portfolio_despesas_fixas(id) on delete set null;

alter table portfolio_despesas_fixas enable row level security;

drop policy if exists "Painel autenticado gerencia despesas fixas" on portfolio_despesas_fixas;
create policy "Painel autenticado gerencia despesas fixas"
  on portfolio_despesas_fixas for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update, delete on portfolio_despesas_fixas to authenticated;
