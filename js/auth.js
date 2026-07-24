/* =============================================================
   AUTENTICAÇÃO COMPARTILHADA
   Usado por login.html e painel.html. Cria o cliente do Supabase
   uma única vez aqui e expõe window.Auth com login, logout e
   verificação de sessão, pra não repetir essa lógica nas páginas.
   ============================================================= */

// Dados do projeto no Supabase (URL e chave pública/anon).
const SUPABASE_URL = "https://kemurhnujsroigskydxj.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtlbXVyaG51anNyb2lnc2t5ZHhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ5MTYwMzAsImV4cCI6MjEwMDQ5MjAzMH0.QsTaqo7NFFsrOxupNF_L1V3cBmSuZU92LzGy4KHSP3M";

// O script do Supabase (carregado por CDN antes deste arquivo) cria
// window.supabase com createClient. O cliente é montado uma única vez
// aqui e reaproveitado por qualquer página que carregue este arquivo.
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

window.Auth = {
  // Cliente cru do Supabase, exposto para o painel poder consultar
  // as tabelas (portfolio_events, portfolio_leads) diretamente.
  sb: sb,

  // Faz login com e-mail e senha. Em caso de erro, lança uma
  // mensagem em português pronta pra mostrar na tela.
  async login(email, senha) {
    const resultado = await sb.auth.signInWithPassword({ email: email, password: senha });
    if (resultado.error) {
      if (resultado.error.message === "Invalid login credentials") {
        throw new Error("E-mail ou senha incorretos.");
      }
      throw new Error(resultado.error.message);
    }
    return resultado.data.user;
  },

  // Confere se existe uma sessão ativa. Sem sessão, manda pro login
  // e devolve null: essa função é o guarda que roda no topo do painel.
  async checkAuth() {
    const resultado = await sb.auth.getSession();
    if (resultado.error || !resultado.data.session) {
      window.location.href = "/login/";
      return null;
    }
    return resultado.data.session.user;
  },

  // Encerra a sessão atual e volta pro login.
  async logout() {
    await sb.auth.signOut();
    window.location.href = "/login/";
  },

  // Dispara o e-mail de recuperação de senha do Supabase.
  async recuperarSenha(email) {
    const resultado = await sb.auth.resetPasswordForEmail(email);
    if (resultado.error) {
      throw new Error(resultado.error.message);
    }
  },
};
