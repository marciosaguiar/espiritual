/// O aparelho apagou o que o app tinha guardado?
///
/// O iPhone pode limpar os dados de um site quando falta espaço (ou depois de
/// semanas sem uso, fora do app instalado). O app não recebe aviso nenhum — as
/// coisas simplesmente deixam de estar lá. Então ele deixa DUAS marcas em dois
/// lugares que o navegador guarda separados (`localStorage` e IndexedDB), e
/// confere as duas ao abrir:
///
/// - as duas presentes: está tudo como foi deixado;
/// - as duas ausentes: primeira vez neste aparelho (ou tudo foi apagado — e aí
///   é impossível distinguir, e o caminho é o mesmo: baixar);
/// - só uma presente: o navegador apagou UM dos lugares. É o caso que se
///   percebe, e que precisa de conserto.
///
/// O conserto é sempre o mesmo e não pede nada à pessoa: esquecer o que o app
/// guardou de derivado (progresso de baixada, cota do dia), deixar as marcas
/// de novo, e baixar outra vez, aos poucos. O login é a exceção que ninguém
/// resolve por ela: se o navegador levou a sessão junto, ela entra de novo.
library;

enum VereditoDoAparelho { tudoCerto, primeiraVez, dadosApagados }

VereditoDoAparelho conferirMarcas({
  required bool marcaNoLocalStorage,
  required bool marcaNoArmazem,
}) {
  if (marcaNoLocalStorage && marcaNoArmazem) {
    return VereditoDoAparelho.tudoCerto;
  }
  if (!marcaNoLocalStorage && !marcaNoArmazem) {
    return VereditoDoAparelho.primeiraVez;
  }
  return VereditoDoAparelho.dadosApagados;
}
