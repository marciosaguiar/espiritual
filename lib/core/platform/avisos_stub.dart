/// A inscrição deste aparelho no serviço de push.
typedef InscricaoDeAviso = ({String endpoint, String p256dh, String auth});

/// Fora da web não há Web Push: Android e iOS nativos usariam FCM, que exige
/// configuração nativa e um pacote a mais. O app roda como PWA nos dois.
bool get avisosSuportados => false;

String permissaoDeAvisos() => 'sem-suporte';

Future<InscricaoDeAviso?> inscricaoAtual() async => null;

Future<({InscricaoDeAviso? inscricao, String? falha})> inscrever(
        String chavePublica) async =>
    (inscricao: null, falha: 'sem-suporte');

Future<bool> desinscrever() async => false;

Future<({int status, String corpo})> chamarWorker(
        String url, String token, String corpo) async =>
    (status: 0, corpo: 'sem-suporte');

bool pediuAbrirChat() => false;
