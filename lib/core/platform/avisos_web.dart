import 'dart:convert';
import 'dart:js_interop';

/// A inscrição deste aparelho no serviço de push.
typedef InscricaoDeAviso = ({String endpoint, String p256dh, String auth});

// As funções moram em `web/avisos.js`. Ver lá por que a permissão só se pede
// dentro de um toque.
@JS('levitaAvisosSuportados')
external JSFunction? get _suportados;

@JS('levitaPermissaoDeAvisos')
external JSFunction? get _permissao;

@JS('levitaInscricaoAtual')
external JSFunction? get _atual;

@JS('levitaInscrever')
external JSFunction? get _inscrever;

@JS('levitaDesinscrever')
external JSFunction? get _desinscrever;

@JS('levitaPediuAbrirChat')
external JSFunction? get _pediuChat;

@JS('levitaChamarWorker')
external JSFunction? get _chamarWorker;

/// Este aparelho sabe receber aviso?
///
/// Falso no Safari do iPhone quando o app NÃO está instalado na tela de
/// início — lá o `PushManager` simplesmente não existe. É esse falso que faz
/// a tela mostrar o passo a passo de instalar em vez do botão.
bool get avisosSuportados {
  try {
    return _suportados?.callAsFunction(null).dartify() == true;
  } catch (_) {
    return false;
  }
}

/// 'granted', 'denied', 'default' ou 'sem-suporte'.
String permissaoDeAvisos() {
  try {
    final v = _permissao?.callAsFunction(null).dartify();
    return v is String ? v : 'sem-suporte';
  } catch (_) {
    return 'sem-suporte';
  }
}

InscricaoDeAviso? _daJson(Object? bruto) {
  if (bruto is! String || bruto.isEmpty) return null;
  try {
    final m = jsonDecode(bruto) as Map<String, dynamic>;
    final endpoint = m['endpoint'] as String?;
    final p256dh = m['p256dh'] as String?;
    final auth = m['auth'] as String?;
    if (endpoint == null || p256dh == null || auth == null) return null;
    return (endpoint: endpoint, p256dh: p256dh, auth: auth);
  } catch (_) {
    return null;
  }
}

/// A inscrição que já existe neste aparelho, ou null.
Future<InscricaoDeAviso?> inscricaoAtual() async {
  final f = _atual;
  if (f == null) return null;
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    return _daJson(r.dartify());
  } catch (_) {
    return null;
  }
}

/// Pede a permissão e inscreve. Só funciona dentro de um toque da pessoa.
///
/// Devolve a inscrição, ou o motivo: 'sem-suporte', 'negado' ou 'erro'.
Future<({InscricaoDeAviso? inscricao, String? falha})> inscrever(
    String chavePublica) async {
  final f = _inscrever;
  if (f == null) return (inscricao: null, falha: 'sem-suporte');
  try {
    final r = await (f.callAsFunction(null, chavePublica.toJS) as JSPromise)
        .toDart;
    final bruto = r.dartify();
    final inscricao = _daJson(bruto);
    if (inscricao != null) return (inscricao: inscricao, falha: null);
    return (inscricao: null, falha: bruto is String ? bruto : 'erro');
  } catch (_) {
    return (inscricao: null, falha: 'erro');
  }
}

Future<bool> desinscrever() async {
  final f = _desinscrever;
  if (f == null) return false;
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    return r.dartify() == true;
  } catch (_) {
    return false;
  }
}

/// Um POST no Worker dos avisos. `status` 0 quer dizer que nem saiu.
Future<({int status, String corpo})> chamarWorker(
    String url, String token, String corpo) async {
  final f = _chamarWorker;
  if (f == null) return (status: 0, corpo: 'página sem o avisos.js');
  try {
    final r = await (f.callAsFunction(null, url.toJS, token.toJS, corpo.toJS)
        as JSPromise).toDart;
    final bruto = r.dartify();
    if (bruto is! String) return (status: 0, corpo: 'resposta estranha');
    final m = jsonDecode(bruto) as Map<String, dynamic>;
    return (
      status: (m['status'] as num?)?.toInt() ?? 0,
      corpo: (m['corpo'] as String?) ?? '',
    );
  } catch (e) {
    return (status: 0, corpo: '$e');
  }
}

/// Alguém tocou numa notificação? Responde uma vez só.
bool pediuAbrirChat() {
  try {
    return _pediuChat?.callAsFunction(null).dartify() == true;
  } catch (_) {
    return false;
  }
}
