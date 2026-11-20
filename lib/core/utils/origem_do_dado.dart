/// Um "vazio" que veio do CACHE não é resposta: é a falta de resposta.
///
/// O Firestore entrega primeiro o que o aparelho já tem. Se o cache dele está
/// vazio (aparelho novo, dados apagados, consulta nunca feita ali), a primeira
/// notificação é uma lista vazia marcada `fromCache` — e, sem internet, é a
/// ÚNICA que vai chegar. Tratá-la como verdade apagava da tela a cópia que o
/// app tinha restaurado do aparelho ("Nenhum culto marcado") e, dois segundos
/// depois, regravava a cópia vazia por cima da boa. Foi achado provando o app
/// com a rede cortada.
///
/// Só um vazio vindo do SERVIDOR quer dizer "não há nada". Vazio do cache, com
/// dados já na tela, é ignorado; sem nada na tela, vale (acaba a espera e a tela
/// mostra o estado vazio).
bool ignorarVazioDoCache({
  required bool doCache,
  required bool vazio,
  required bool jaTemDados,
}) =>
    doCache && vazio && jaTemDados;
