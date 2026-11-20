/// O armazém local do app: um guarda-chaves que cabe o que `localStorage` não
/// cabe (a fila de envio, as cópias das músicas, os áudios do chat).
///
/// Na web é IndexedDB (`web/offline.js`); fora dela, uma tabela em memória —
/// o alvo do app é o PWA, e o que o armazém guarda é sempre recuperável do
/// banco, então perder a tabela num celular nativo custa uma baixada, não um
/// dado.
///
/// Nenhuma função lança: ler devolve nulo quando não deu, e gravar devolve
/// falso. Um armazém que falha não pode derrubar uma tela.
library;

export 'armazem_stub.dart' if (dart.library.js_interop) 'armazem_web.dart';
