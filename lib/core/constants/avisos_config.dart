/// Os dois valores que ligam o app ao mini-servidor dos avisos.
///
/// Os dois são PÚBLICOS por natureza — o endereço do Worker e a chave pública
/// do VAPID viajam em todo aviso e aparecem no código do app, como já
/// acontece com as chaves do Firebase em `firebase_options.dart`. A chave
/// PRIVADA do VAPID nunca entra aqui: ela fica só nos segredos da Cloudflare.
/// Se ela aparecer neste arquivo um dia, qualquer pessoa com o endereço do
/// app poderá mandar notificação para o ministério inteiro.
///
/// Enquanto estes valores forem os de exemplo, o app não mostra o botão de
/// ativar avisos — explica o que falta, em vez de dar erro.
class AvisosConfig {
  AvisosConfig._();

  /// O endereço do Worker, sem barra no fim.
  ///
  /// Sai do `wrangler deploy`, no formato
  /// `https://levitasync-avisos.SEU-USUARIO.workers.dev`.
  static const String worker = 'https://levitasync-avisos.marcioaguiar04.workers.dev';

  /// A chave pública do VAPID, em base64url.
  ///
  /// Sai do `npx web-push generate-vapid-keys` — é a linha "Public Key",
  /// com 87 caracteres.
  static const String chavePublica = 'BK8kod6yy9DIw1N0tJPdeg7-WRYVmQwUVUG9YOhcAPt9JANI6b8Z2iTzrfEUWx5iKSXWodTzIlu-LOh8PF6szBk';

  /// Já foi configurado de verdade?
  static bool get configurado => pareceConfigurado(worker, chavePublica);

  /// A mesma conta, com os valores dados — é esta que o teste exercita.
  ///
  /// A primeira versão era um getter que lia as constantes, e o teste
  /// afirmava `configurado == false`. Funcionou por um dia: no instante em
  /// que o Worker foi publicado e as duas linhas preenchidas, o teste passou
  /// a falhar sem nada estar errado. **Teste que depende de configuração
  /// local quebra quando a configuração é feita** — o certo é testar a regra,
  /// não o valor de hoje.
  ///
  /// Confere o TAMANHO da chave, e não só se ela mudou, porque colar metade
  /// dela é o erro mais provável: tem 87 caracteres e não tem onde quebrar.
  static bool pareceConfigurado(String worker, String chavePublica) =>
      worker.startsWith('https://') &&
      !worker.contains('COLE-AQUI') &&
      chavePublica.length >= 80 &&
      !chavePublica.contains('COLE-AQUI');
}
