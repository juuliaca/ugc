/* =============================================================
   RASTREIO DE VISITAS, CLIQUES, VÍDEOS E MENSAGENS
   Carregado pelo index.html (site público). Registra os eventos
   que alimentam o painel administrativo (login/ e painel/), usando
   a chave pública (anon) do Supabase, com permissão só de GRAVAR
   (nunca ler, alterar ou apagar); veja a policy em setup.sql.

   Fala direto com a API REST do Supabase via fetch(), em vez de
   usar a biblioteca supabase-js: o "insert" da biblioteca pede a
   linha de volta por padrão, e isso esbarra numa regra do Postgres
   que exige permissão de LEITURA pra devolver a linha inserida
   (mesmo a gravação em si sendo permitida). Como o "anon" não tem
   permissão de leitura de propósito, a gravação era barrada. Pedir
   explicitamente "não devolva a linha" (Prefer: return=minimal)
   evita esse problema.
   ============================================================= */

(function () {
  const SUPABASE_URL = "https://kemurhnujsroigskydxj.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtlbXVyaG51anNyb2lnc2t5ZHhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MTYwMzAsImV4cCI6MjEwMDQ5MjAzMH0.QsTaqo7NFFsrOxupNF_L1V3cBmSuZU92LzGy4KHSP3M";

  // Identifica o mesmo visitante entre visitas diferentes, guardando um
  // id aleatório no navegador dele. É esse id que vira "session_id" nos
  // eventos e é contado como "Visitantes únicos" no painel.
  const CHAVE_VISITANTE = "portfolio_visitor_id";

  function obterIdVisitante() {
    try {
      let id = localStorage.getItem(CHAVE_VISITANTE);
      if (!id) {
        id = window.crypto && window.crypto.randomUUID
          ? window.crypto.randomUUID()
          : "visitante-" + Date.now() + "-" + Math.random().toString(16).slice(2);
        localStorage.setItem(CHAVE_VISITANTE, id);
      }
      return id;
    } catch (erro) {
      // Se o navegador bloquear localStorage (modo privado, por exemplo),
      // segue sem quebrar a página, só sem lembrar o visitante depois.
      return "sem-id";
    }
  }

  // Envia um POST direto pra tabela indicada, sem pedir a linha de volta.
  // Nunca lança erro pra fora: se a gravação falhar por qualquer motivo,
  // a navegação do site continua normal, só fica um aviso no console.
  function gravar(tabela, linha) {
    fetch(SUPABASE_URL + "/rest/v1/" + tabela, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": "Bearer " + SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
      },
      body: JSON.stringify(linha),
    })
      .then(function (resposta) {
        if (!resposta.ok) {
          resposta.text().then(function (texto) {
            console.warn("Rastreio: falha ao gravar em " + tabela, resposta.status, texto);
          });
        }
      })
      .catch(function (erroDeRede) {
        console.warn("Rastreio: falha de rede ao gravar em " + tabela, erroDeRede);
      });
  }

  function registrarEvento(tipo, nome, metadata) {
    gravar("portfolio_events", {
      event_type: tipo,
      event_name: nome || null,
      session_id: obterIdVisitante(),
      page_path: window.location.pathname,
      metadata: metadata || null,
    });
  }

  window.Rastreio = {
    // Chamado uma vez ao carregar a página.
    registrarVisita: function () {
      registrarEvento("page_view", window.location.pathname, null);
    },

    // Chamado nos cliques de botões/links que valem a pena acompanhar.
    // Use nomes começando com "contact_" para os que levam a pessoa a
    // tentar falar com você (WhatsApp, e-mail, Instagram, formulário):
    // esses entram na contagem de "Clicaram para entrar em contato".
    registrarClique: function (nome, metadata) {
      registrarEvento("button_click", nome, metadata || null);
    },

    // Chamado quando alguém decide assistir um vídeo com som de verdade
    // (não a prévia muda do hover). "idVideo" é o id do vídeo no YouTube.
    registrarVideo: function (idVideo, metadata) {
      registrarEvento("video_view", idVideo, metadata || null);
    },

    // Grava uma mensagem recebida (formulário de contato) em
    // portfolio_leads.
    registrarLead: function (dados) {
      gravar("portfolio_leads", dados);
    },
  };

  window.Rastreio.registrarVisita();
})();
