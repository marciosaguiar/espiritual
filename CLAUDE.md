# LevitaSync

App do ministério de louvor: repertório, escala dos cultos e chat da equipe.
Flutter (Android, iOS e web/PWA) com Firebase.

Quem usa são voluntários leigos — "só sabem usar WhatsApp". Isso decide muita
coisa: nada de jargão na tela, nenhum passo que dependa de adivinhar, e
nenhuma falha silenciosa.

## Como rodar

```bash
flutter pub get
flutter run -d chrome          # ou um dispositivo conectado
flutter analyze                # deve terminar sem nenhum "error"
                               # (os "issues" restantes são avisos)
flutter test                   # 122 testes
```

Testes das regras de segurança (sobem o emulador do Firestore; exigem Node e Java):

```bash
cd test_regras && npm install && npm test    # 59 testes
```

**Rode os dois antes de qualquer commit.** As regras não compilam junto com o
app: um erro nelas só aparece quando alguém não consegue entrar.

O `analysis_options.yaml` existe por dois motivos: liga o `flutter_lints`, que
estava declarado no `pubspec.yaml` e nunca era aplicado, e tira
`test_regras/node_modules` da análise. Sem essa exclusão, rodar os testes de
regra fazia o `flutter analyze` acusar 6 erros vindos de um arquivo de exemplo
de dentro do `firebase-tools` — os dois comandos acima se contradiziam.

## Estado atual

Funciona e está testado. O que **ainda falta para o app rodar de verdade** é
configuração, não código:

1. Criar o projeto no Firebase (Firestore em produção + Authentication por
   e-mail/senha + plano Blaze com orçamento).
2. `flutterfire configure` — preenche `lib/firebase_options.dart` e os
   arquivos nativos, que hoje têm valores de exemplo.
3. `firebase deploy --only firestore:rules`.
4. Depois de criar a primeira conta pelo app, **promover-se a líder no
   console**: Firestore → `users` → seu documento → `role`: `levita` → `admin`.
   As regras proíbem nascer admin de propósito (o endereço do app é público).

Sem o passo 2 o app abre numa tela explicando o que falta, em vez de parecer
quebrado.

## Como está organizado

```
lib/
├─ core/
│  ├─ constants/     cores, textos (AppStrings.appName é o nome do app)
│  ├─ platform/      install.dart — detecção de PWA, por importação condicional
│  └─ utils/         chord_transposer.dart
├─ data/
│  ├─ models/        user, song, arrangement (+ songPref), scale, message
│  └─ services/      auth_service, firestore_service, local_storage_service
└─ presentation/
   ├─ providers/     auth, songs, scale, chat, theme  (Provider)
   ├─ screens/       login, cadastro, 5 abas, detalhes
   └─ widgets/
```

### Modelo de dados — três camadas

```
songs/{songId}                        a obra: nome, artista, letra, tom original, links
songs/{songId}/arrangements/{id}      como a NOSSA igreja toca: cifra, tom, bpm
users/{userId}/songPrefs/{songId}     meu tom e minhas anotações (privado)
scales/{scaleId}.songs[]              só referências: {songId, arrangementId, keyOverride}

teams/{teamId}                        Equipe Manhã, Equipe Noite: [{userId, instrument}]
config/agendaFixa                     um doc só: os horários fixos da semana
```

A escala guarda **referências, nunca cópias**. Antes ela copiava nome e
artista, e corrigir uma música não corrigia os cultos já montados. As telas
resolvem pelo id com `SongsProvider.nameOf/artistOf/keyOf`.

A cifra fica no arranjo, não na música: é o que impede o app de baixar o
repertório inteiro de cifras só para abrir a lista.

### Agenda fixa e equipes

Os cultos da igreja se repetem (quarta 8h e 19h30, sexta 19h30, domingo 8h e
19h), então o líder configura isso uma vez em Perfil → Agenda fixa e o app
cria as próximas 4 semanas sozinho, já com a equipe padrão escalada e todos
como não confirmados.

- **O id do culto vem da data e hora:** `2026-11-15_0800`. É isso que impede
  duplicata: dois líderes abrindo o app ao mesmo tempo calculam o mesmo id e
  escrevem o mesmo documento, cada um dentro de uma transação que confere se
  ele já existe.
- **Cancelar é um campo, nunca exclusão.** Apagar um culto gerado não
  adianta: o gerador o recriaria na próxima abertura. Por isso o menu do
  culto oferece "Cancelar" e só mostra "Excluir" para culto avulso.
- **`manuallyEdited`** marca o culto que o líder ajustou à mão. "Aplicar aos
  próximos cultos?", ao salvar uma equipe, pula esses e preserva quem já
  confirmou. Confirmar presença NÃO marca — é ação do levita, não edição.
- **A geração só roda para o líder**, porque as regras só deixam ele criar.
  Fragilidade conhecida: se nenhum líder abrir o app por semanas, os cultos
  param de ser criados. O conserto de verdade é uma Cloud Function agendada,
  que depende do plano Blaze.
- **A decisão de quais cultos faltam é uma função pura**
  (`FirestoreService.servicosFaltando`), testada em `test/agenda_fixa_test.dart`.
  Toda lógica nova de geração entra ali, não dentro da transação.

### Janela de leitura dos cultos

`watchScales` lê apenas de 60 dias atrás até 90 dias à frente
(`FirestoreService.janelaPassado` / `janelaFuturo`). Com 5 cultos por semana
são ~260 por ano, e antes o app lia a coleção inteira a cada abertura. O
efeito colateral: meses muito antigos aparecem vazios no calendário.

## Regras do jogo neste projeto

- **Texto na tela em português; comentários no código em inglês.** Comentário
  explica *por que*, não *o quê* — de preferência o defeito que ele evita.
- **Toda escrita devolve o motivo do erro**, não um `bool`. Os providers
  devolvem `null` quando dá certo e a mensagem quando falha; a tela mostra.
  `catch (_)` só é aceitável em leitura com valor padrão seguro.
- **Mudança em escala vai por transação**, gravando só o campo que lhe
  pertence (`confirmPresence`, `setScaleSongs`, `setLevitas`,
  `updateScaleDetails`). Ler-alterar-gravar o documento inteiro perde o
  trabalho de quem está mexendo ao mesmo tempo.
- **Nada de dependência declarada e não usada.** Já foram removidas 14.
- O nome do app sai de `AppStrings.appName`, nunca escrito à mão.
- **Tela que abre por cima usa `GlassPageRoute`, nunca `MaterialPageRoute`.**
  Os dois temas põem `scaffoldBackgroundColor: Colors.transparent` para o
  fundo único do app aparecer. Com `MaterialPageRoute` isso deixava a tela
  que entra translúcida *durante a animação*, e as duas apareciam embaralhadas
  por alguns décimos de segundo. `GlassPageRoute` pinta o fundo dentro da
  própria rota. Um teste varre `lib/presentation/screens` e falha se alguém
  voltar atrás.

## Armadilhas que já custaram caro

- **`null` em regra do Firestore.** `null is string` é falso. O app grava
  `photoUrl: null`, e uma validação `campo is string` recusava criar conta,
  editar perfil e promover membro. Toda validação de texto opcional precisa
  do `== null`. Foi pego pelo `test_regras`, não pela leitura.
- **`Timestamp` não vira JSON.** `jsonEncode` sobre o mapa do Firestore lança,
  e isso quebrava todo login. Por isso existem `toJson`/`fromJson` separados
  de `toFirestore`/`fromFirestore`.
- **Transpor acordes.** Só transpõe linha em que *todas* as palavras são
  acordes. Antes, "E o Senhor é bom" virava "F# o Senhor é bom".
- **Escutas em tempo real.** As quatro começam juntas em `main_screen`, e duas
  leem a coleção inteira. É o maior custo de leitura do app; com 300 músicas
  passa da cota gratuita diária do Firestore.
- **O app instalado serve a versão em cache.** Na tela de início quem entrega
  as telas é o service worker, e o iOS só procura versão nova numa carga de
  página de verdade — coisa que um app instalado quase nunca faz. Resultado:
  um defeito corrigido, publicado e no ar continua aparecendo no celular.
  Aconteceu com o instrumento em inglês: a correção estava no build do
  GitHub Pages e a tela vinha de um cache antigo. O `web/index.html` agora
  pergunta por versão nova quando o app volta ao primeiro plano e recarrega
  uma vez quando ela assume. **Ao investigar um defeito "que não sumiu",
  confirme primeiro de qual build veio a tela.**

## Próximos passos combinados (fase 2)

Nesta ordem, e **nada disso antes de testar o app num iPhone real**:

0. ~~Agenda fixa + equipes~~ — **feito.**

1. **Aprovação do líder.** Quem se cadastra entra com `role: 'pendente'`; as
   regras não liberam leitura nenhuma para pendente; o líder aprova ou recusa
   em Perfil → Membros, com selo de quantos aguardam. Hoje o cadastro é
   aberto a qualquer pessoa com o link, e é o buraco mais urgente.
2. **Notificações push**, Android e iPhone. No iOS funciona por Web Push com
   VAPID em PWA instalado (16.4+) — **não** exige conta paga da Apple. Exige
   Cloud Functions para os gatilhos: escalado, lembrete da véspera, mensagem
   nova e "novo pedido de entrada" para o líder.
3. **Líder redefine senha de um membro.** Só com o Admin SDK, em Cloud
   Function — o Firebase não deixa um app trocar a senha de outra pessoa.
   Fica pequeno depois que as Functions existirem.

Quando as Functions existirem, mover a função do usuário para um *custom
claim* no token: as regras passam a ler `request.auth.token.role` e somem as
leituras extras que hoje cada `get()` dentro da regra cobra.

## O que não existe (e o relatório de auditoria aponta)

Busca de música na internet, anexo de áudio e imagem no chat, PDF da escala,
foto de perfil, transformar uma mensagem do chat em decisão da agenda.
