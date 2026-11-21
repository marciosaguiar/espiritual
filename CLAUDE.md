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
flutter test                   # 1070 testes
```

Testes das regras de segurança (sobem o emulador do Firestore; exigem Node e Java):

```bash
cd test_regras && npm install && npm test    # 327 testes
```

Para ver o app em vários tamanhos de tela (sem Firebase, sem navegador):

```bash
CAPTURAR_EM=/pasta/das/fotos flutter test ferramentas/captura/capturar_telas_test.dart
# opcionais: LARGURAS=375,768,1280,1920  TELAS=inicio,hinarios  TEMAS=claro,escuro
```

Num navegador de verdade (Chromium + Playwright, sem Firebase): prova que o
detalhe abre AO LADO, clicando com o mouse a 1280, 1920 e 2400 px:

```bash
flutter build web --release -t ferramentas/captura/main_demo.dart \
    --base-href / --pwa-strategy=none --no-web-resources-cdn
node ferramentas/captura/provar_ao_lado.mjs build/web /pasta/das/fotos
```

Para MEDIR a abertura do app (a `main()` de verdade, o service worker e o
Firestore com cache, contra o emulador, num Chromium com a rede e o processador
de um celular) — ver "A abertura do app" abaixo:

```bash
SEMENTE_EM=/tmp/semente.json flutter test ferramentas/medir/gerar_semente_test.dart
firebase emulators:start --only auth,firestore --project espiritual-d2403   # com auth no firebase.json
node ferramentas/medir/semear.mjs /tmp/semente.json
flutter build web --release --base-href / --pwa-strategy=none --no-web-resources-cdn \
    --dart-define=EMULADOR=true --dart-define=MEDIR=true
node ferramentas/medir/carimbar_sw.mjs build/web
PERFIL=lento REPETICOES=3 node ferramentas/medir/medir_abertura.mjs build/web /tmp/medidas.json
node ferramentas/medir/comparar.mjs antes.json depois.json
```

Para CONTAR quantos documentos o banco entrega (a leitura que o Firebase cobra)
e para PROVAR, num Chromium com a rede cortada, que o app funciona sem internet —
ver "Offline primeiro":

```bash
flutter build web --release --base-href / --pwa-strategy=none --no-web-resources-cdn \
    --dart-define=EMULADOR=true --dart-define=MEDIR=true --dart-define=PORTA_FIRESTORE=8081
node ferramentas/medir/carimbar_sw.mjs build/web
# com o emulador de pé (auth + firestore):
node ferramentas/medir/semear.mjs /tmp/semente.json
node ferramentas/medir/semear_biblioteca.mjs /tmp/semente.json    # 2 hinários + cifras, texto INVENTADO
COM_PREPARO=1 node ferramentas/medir/medir_leituras.mjs build/web /tmp/leituras.json
node ferramentas/medir/semear.mjs /tmp/semente.json && node ferramentas/medir/semear_biblioteca.mjs /tmp/semente.json
node ferramentas/medir/provar_offline.mjs build/web /pasta/das/fotos
# a medição agora diz DE ONDE vêm os documentos (por coleção), quantos são
# DISTINTOS por consulta, e mede a "primeira abertura do dia" (cópias vencidas):
SEMENTE=/tmp/semente-levita.json node ferramentas/medir/medir_leituras.mjs build/web /tmp/saida.json   # entrando como levita
DEBUG_PEDIDO=users node ferramentas/medir/medir_leituras.mjs ...      # mostra cada consulta enviada a essa coleção
```

**Rode os dois antes de qualquer commit.** As regras não compilam junto com o
app: um erro nelas só aparece quando alguém não consegue entrar.

O `analysis_options.yaml` existe por dois motivos: liga o `flutter_lints`, que
estava declarado no `pubspec.yaml` e nunca era aplicado, e tira
`test_regras/node_modules` da análise. Sem essa exclusão, rodar os testes de
regra fazia o `flutter analyze` acusar 6 erros vindos de um arquivo de exemplo
de dentro do `firebase-tools` — os dois comandos acima se contradiziam.

O `test_regras/.npmrc` também não é enfeite: `@firebase/rules-unit-testing@3`
pede `firebase@^10` e aqui se usa o 13. As versões novas do npm recusam
instalar por isso, então `npm install` falhava num computador limpo, embora os
236 testes passem com as duas versões juntas. O `.npmrc` dá a licença; sem ele
só com `npm install --legacy-peer-deps`.

O mini-servidor dos avisos tem testes próprios, que não precisam de emulador
nem de Flutter:

```bash
node --test worker/teste/*.mjs               # 104 testes
node --test web/teste/*.mjs                  # 24 testes do service worker
node --test ferramentas/teste/*.mjs          # 22 testes das rotinas diárias
```

**A versão do Flutter é fixa** (`flutter-version: '3.50.0'` nos dois
workflows), e medir o pacote com outra versão não vale: ver "A trava do
tamanho reprovou todo deploy por dias".

**E a string da versão NÃO BASTA.** Quem compila é o motor e o Dart, que
aparecem nas outras linhas do `flutter --version`. Um contêiner com
framework novo e motor velho diz "3.50.0" e gera 199 KB a menos — ver "A
versão fixada mentiu" nas armadilhas. Antes de comparar qualquer número de
tamanho, confira as três linhas:

```
Flutter 3.50.0 • channel stable
Framework • revision ... (dias)
Engine    • hash ... (dias, não MESES)
Tools     • Dart 3.x
```

O segundo roda o `web/sw.js` de verdade, com o `self` do navegador simulado:
é ele que decide qual etiqueta cada aviso usa e para onde vai quem toca, e
erro ali não aparece na tela de ninguém — o aviso chega bonito e leva à tela
errada, ou um aviso apaga o outro e um pedido de entrada se perde. **No
navegador isso não dá para medir:** `Notification.permission` responde
`denied` no Chromium headless, e nem o `grantPermissions` do Playwright nem o
`Browser.grantPermissions` do protocolo do Chrome mudam isso — o push chega ao
service worker e o `showNotification` lança.

## Estado atual

Funciona e está testado. O que **ainda falta para o app rodar de verdade** é
configuração, não código:

1. Criar o projeto no Firebase (Firestore em produção + Authentication por
   e-mail/senha + plano Blaze com orçamento).
2. `flutterfire configure` — já rodado: `lib/firebase_options.dart` tem as
   chaves de verdade para **web e Android**, que são as duas plataformas em
   que o app roda (no iPhone é o PWA instalado, não aplicativo nativo). iOS e
   macOS **não estão configurados de propósito**: tinham blocos de exemplo
   apontando para um projeto `levitasync` que nunca existiu, e compilar
   nativo com eles não dava erro nenhum — o app abria e toda chamada ao banco
   falhava. Agora os dois lançam um erro que diz o que fazer. O
   `ios/Runner/GoogleService-Info.plist` continua sendo o de exemplo, e o
   erro avisa disso também.
3. `firebase deploy --only firestore:rules`.
4. Depois de criar a primeira conta pelo app, **promover-se a líder no
   console**: Firestore → `users` → seu documento → `role`: `pendente` →
   `admin`. As regras proíbem nascer admin de propósito, e agora proíbem
   também nascer levita: todo cadastro novo fica `pendente` até um líder
   aprovar. Como o primeiro cadastro não tem líder para aprová-lo, esse
   primeiro empurrão é no console — uma vez só, na vida do projeto.

Sem o passo 2 o app abre numa tela explicando o que falta, em vez de parecer
quebrado.

## Como está organizado

```
lib/
├─ core/
│  ├─ constants/     cores, textos (AppStrings.appName é o nome do app)
│  ├─ platform/      install.dart — detecção de PWA, por importação condicional
│  └─ utils/         chord_transposer, mapa_da_musica, texto (busca sem acento)
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
- **Cancelar é um campo, nunca exclusão — e agora não há exclusão nenhuma.**
  Apagar um culto gerado não adiantava: o gerador o recriaria na próxima
  abertura. O menu ainda oferecia "Excluir" para o culto avulso, e era a
  segunda opção vermelha a dois dedos de "Cancelar": a de baixo levava junto
  quem já tinha confirmado presença, o repertório montado e o registro de
  quem tocou ali. "Excluir culto" deixou de existir, como deixou de existir
  para as músicas, e **`allow delete: if false` em `scales`** vale para
  todos, líder incluído — esconder o botão não bastaria, porque a API aceita
  quem falar direto com ela. Apagar de verdade, só pelo console do Firebase.
- **Um dia pode ter MAIS DE UM culto — e a pergunta "qual é o culto deste dia?"
  não tem resposta única.** O domingo tem o da manhã e o da noite, e a quarta
  também. A Escala tinha `getScaleForDay`, que devolvia o primeiro que achasse:
  tocar no domingo mostrava só o das 8h, e o das 19h estava no banco, na lista
  de próximos e com ponto no calendário, mas **não dava para abrir pelo dia**.
  Não aparecia em teste nenhum porque nenhum teste tinha dois cultos no mesmo
  dia. Agora `ScaleProvider.cultosDoDia` devolve TODOS, do mais cedo ao mais
  tarde (função pura que recebe a lista, como `aindaVale`), e a função de um
  culto só **deixou de existir**: deixá-la ali seria convidar o defeito a
  voltar. Três consequências na mesma tela: o calendário põe **um ponto por
  culto** (`cultosPorDia`), o "+" **sempre abre a criação** — antes, num dia
  com culto, pulava para o que existia e impedia criar o segundo — e quem
  impede criar o MESMO culto duas vezes é a conferência de horário ("Já existe
  um culto às 19:30 neste dia"), porque o id do culto criado à mão é sorteado
  e não barraria nada.
- **`manuallyEdited`** marca o culto que o líder ajustou à mão. "Aplicar aos
  próximos cultos?", ao salvar uma equipe, pula esses e preserva quem já
  confirmou. Confirmar presença NÃO marca — é ação do levita, não edição.
- **A geração roda em DOIS lugares**, e as duas são seguras de repetir: no
  app, quando um líder o abre, e no Worker, uma vez por dia (ver "O Worker
  gera os cultos"). A fragilidade de antes — nenhum líder abre o app por
  semanas e a escala seca sem ninguém perceber — deixou de existir, e sem
  Cloud Function: o robô é um líder comum, e criar é permitido a líder.
- **A decisão de quais cultos faltam é uma função pura**
  (`FirestoreService.servicosFaltando`), testada em `test/agenda_fixa_test.dart`.
  Toda lógica nova de geração entra ali, não dentro da transação.

### Aprovação do líder

O endereço do app é público — tem de ser, o GitHub Pages serve de graça só
repositório público. Então qualquer pessoa com o link cria uma conta. Quem se
cadastra nasce `pendente`:

```
pendente  → acabou de se cadastrar; não lê NADA além do próprio cadastro
levita    → aprovado
admin     → líder
removido  → saiu, foi recusado ou foi tirado; mesma falta de acesso
```

**`removido` é um estado só.** Recusar um pedido novo e tirar alguém que já
estava dentro são a mesma coisa para o banco: sem acesso, documento
preservado, volta possível. O nome antigo `recusado` ainda é lido (vira
`removido`) e nunca mais é gravado.

- **A trava está nas regras, não na tela.** Esconder botões não adiantaria:
  qualquer um fala direto com o banco pela API. `aprovado()` no
  `firestore.rules` é o que vale, e o `test_regras` cobre cada coleção.
  Rodando os testes novos contra as regras antigas, 16 falham — é a medida
  exata do buraco que existia.
- **O pendente lê o próprio cadastro, e só.** Sem isso o app não teria como
  saber que a pessoa está esperando, e mostraria cinco abas vazias parecendo
  quebrado. É o que a `PendingScreen` explica.
- **Função desconhecida vira `pendente`**, nos dois lados: `fromString` no
  Dart e a lista fechada `['levita','admin']` na regra. Campo faltando,
  documento meio gravado ou nome escrito errado no console têm de significar
  *menos* acesso, nunca o acesso normal.
- **Nada é apagado, nunca.** O app não apaga conta — isso exigiria o Admin
  SDK num servidor, que depende do plano pago — e as regras proíbem apagar
  `users`. "Remover" é revogar acesso. O histórico (quem tocou onde, o que
  disse no chat) é do ministério, não do vínculo.
- **Remover é uma transação só**, em `FirestoreService.removerDoMinisterio`:
  marca o cadastro (`role`, `removedAt`, `removedBy`), tira a pessoa de todas
  as equipes e dos cultos **futuros**, e grava só o campo que pertence a cada
  documento (`members`, `levitas`). Culto passado fica como está: ela tocou
  lá. A parte que dá para errar em silêncio é pura e testada
  (`FirestoreService.semAPessoa`).
- **Quem some de um culto deixa aviso.** `ScaleModel.faltando` guarda os
  nomes, e a tela do culto diz ao líder "Faltando alguém: Fulano foi
  removido". Sem isso o culto perderia um instrumento e ninguém saberia até
  domingo. O aviso some quando o líder mexe na escalação — o gesto de "já vi".
- **Sair do ministério é da própria pessoa**, em Perfil. Mesmo efeito, com
  `removedBy` apontando para ela mesma.
- **O último líder não sai nem é removido.** Essa proteção é SÓ do app: a
  regra teria de contar quantos admins existem, e contar exige consulta, que
  regra do Firestore não faz. Vale contra engano, não contra má-fé.
- **Perder o acesso limpa o aparelho.** `LocalStorageService
  .limparTudoDoMinisterio()` apaga sessão e músicas salvas offline; sem isso
  o banco recusaria tudo mas o repertório continuaria no celular.
- **O app escuta o próprio cadastro** (`AuthService.watchUser`), então a
  aprovação vale na hora, sem a pessoa precisar fechar e abrir. Vale para o
  contrário também: líder rebaixado perde as telas de líder na mesma hora.
- **O selo aparece em dois lugares** — na aba Perfil e na linha "Membros do
  ministério" —, porque um pedido esquecido é uma pessoa achando que o app
  não funciona.

### Janela de leitura dos cultos

`watchScales` lê apenas de 60 dias atrás até 90 dias à frente
(`FirestoreService.janelaPassado` / `janelaFuturo`). Com 5 cultos por semana
são ~260 por ano, e antes o app lia a coleção inteira a cada abertura. O
efeito colateral: meses muito antigos aparecem vazios no calendário.

### O aparelho guarda o que já leu

`main()` liga o cache persistente do Firestore (`Settings(persistenceEnabled:
true)`), que na web é o IndexedDB. Antes, cada abertura do app relia do
servidor tudo o que as quatro escutas de `main_screen` alcançam — e **leitura
é a cota que aperta** no plano grátis: 50 mil por dia.

- **Medido no emulador**, com o banco do tamanho do ministério (40 músicas,
  109 cultos dentro da janela, 50 mensagens, 3 equipes): a segunda abertura
  baixava **202 documentos** do servidor e passou a baixar **zero**. Os 202
  vêm do disco, e as quatro consultas recebem do servidor uma resposta vazia,
  só confirmando que nada mudou. Para enxergar essa resposta foi preciso
  `includeMetadataChanges: true` — sem isso o SDK engole o aviso de que o
  servidor respondeu, e a medição não distingue "entregou zero" de "não
  respondeu".
- **O IndexedDB é indexado pelo nome do app.** A primeira versão da medição
  dava um nome sorteado a cada carga e concluía que o cache não servia para
  nada: cada abertura abria um banco novo e vazio.
- **O limite é a SEGUNDA ABA**: o cache é de aba única. Medido: a segunda aba
  não consegue a trava, avisa no console (`failed-precondition`) e **cai
  sozinha para o cache em memória** — que é o que o app fazia antes. Ninguém
  fica com tela vazia. No iPhone o app instalado é uma janela só, então o
  caso é o do computador com duas abas.
- O app também passou a **abrir com o repertório e a escala na tela sem
  internet nenhuma**, e sem esperar a rede para desenhar.
- **O prazo é 30 minutos, e está na conta do Firebase.** Sem cache, *toda*
  reconexão de escuta é cobrada como consulta nova, sem prazo nenhum — era
  por isso que abrir o app duas vezes seguidas custava duas vezes. Com cache,
  só volta a custar a escuta que ficou desligada **mais de 30 minutos**.
  Então a primeira abertura do dia continua custando os 202; o que ficou de
  graça é o vaivém — sair do app e voltar, conferir a escala entre uma
  mensagem e outra —, que é o que mais acontece num domingo.

## Regras do jogo neste projeto

- **Tudo em português: a tela e os comentários do código.** Era "comentário
  em inglês", e a regra perdeu: quem lê este código é o dono do app, que não
  lê inglês, e um comentário que ele não entende não explica nada a ninguém.
  Os comentários antigos, em inglês, **ficam como estão** — traduzir centenas
  de linhas encheria o histórico de mudanças sem conserto nenhum junto, e é
  justamente nesse barulho que um erro de verdade passa despercebido. Vale
  para o que se escreve de agora em diante.
  Comentário explica *por que*, não *o quê* — de preferência o defeito que
  ele evita.
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
- **Valor padrão que abre a porta.** `fromFirestore` lia
  `data['role'] ?? 'levita'`: um cadastro sem o campo `role` entrava como
  aprovado. Com a aprovação do líder isso deixou de ser detalhe e virou a
  diferença entre a trava funcionar ou não. Foi pego por um teste escrito
  justamente para perguntar "e se o campo não existir?" — vale repetir essa
  pergunta em todo `?? valor` que decide acesso.
- **"Próximo culto" comparava só a DATA.** Domingo às 20h53, o culto das 8h
  daquele mesmo domingo ainda aparecia como o próximo, porque a conta jogava
  a hora fora. Agora vale `ScaleProvider.aindaVale(culto, agora)`: o culto
  que ainda não começou, e o que começou há menos de
  `duracaoDoCulto` (2 h), que é quem abre o app no meio do culto. A função é
  pura e recebe `agora` como parâmetro, para o teste poder ficar na virada do
  dia — onde este tipo de conta quebra. Dos 11 testes, 4 falham contra a
  conta antiga.
- **Versão nova ficava "esperando" no iPhone.** O service worker novo era
  baixado e esperava o antigo soltar o controle; num app instalado, que o
  iOS quase nunca encerra, isso levava dias — "saí e entrei três vezes e
  continua a versão velha". O `install` do `web/sw.js` **não** chama mais
  `skipWaiting()` sozinho: trocar o código debaixo de quem está tocando no
  culto é pior que esperar. Em vez disso, a página mostra a faixa "Nova
  versão disponível · Atualizar", e o toque manda `{tipo:'ATUALIZAR'}` para
  o worker, que aí assume. **A faixa é HTML da página, fora do Flutter**,
  porque precisa aparecer mesmo com o app ocupado.
  A única atualização sem perguntar acontece com a pessoa **no Início, parada
  há mais de 5 s e com a tela à vista** — `main_screen` conta à página em que
  aba está, por `lib/core/platform/tela_atual.dart`. Testado de ponta a
  ponta: publicar A, abrir, publicar B, e a faixa aparece; tocando em
  Atualizar, o cache vira B e recarrega **uma** vez. Nos outros dois casos
  (acabou de tocar; está em outra tela) a faixa pergunta e nada recarrega.
- **O Flutter tirou o cache do app e ninguém percebeu.** O
  `flutter_service_worker.js` das versões novas é um arquivo de 784 bytes que
  só se desregistra. O app continuou funcionando — e passou a baixar 3,26 MB
  a cada abertura, 1,49 MB deles de `canvaskit.wasm` vindo do servidor do
  Google. Era a tela de abertura de ~5 s que aparecia toda vez que se voltava
  ao app no iPhone. Agora o cache é nosso (`web/sw.js`), a lista do que
  guardar sai do build na publicação, e a CI falha se o canvaskit voltar ao
  CDN ou se o Flutter voltar a registrar um service worker. **Medido: de 3,26
  MB e 2,5 s por abertura para abrir sem internet nenhuma.**
- **Push com corpo `null` derrubava o aviso.** O `sw.js` fazia
  `dados = evento.data ? evento.data.json() : {}`. Um push cujo corpo seja
  exatamente `null` é JSON **válido**: o `json()` não lança, devolve `null`, e
  ler `dados.titulo` lançava. O navegador exige uma notificação visível para
  cada push — sem ela, **descadastra o aparelho por abuso**, e aquele celular
  pararia de receber aviso para sempre, sem nada na tela. O `?? {}` conserta;
  foi o teste do service worker que achou, escrito para outra coisa.
- **`''[0]` LANÇA, e a tela do culto fazia isso.** O avatar de cada escalado
  era `levita.userName[0].toUpperCase()`. E o gerador da agenda fixa grava
  `userName` VAZIO — ele monta o culto a partir da equipe, que guarda só ids.
  Então todo culto gerado com equipe padrão derrubava a tela do culto
  inteira, no meio da lista de escalados. Não tinha aparecido ainda porque os
  horários estavam sem equipe padrão: bastava o líder escolher uma. O chat já
  se protegia (`isNotEmpty ? ... : '?'`); a escala, não. Agora o nome é
  resolvido por id (`ScaleLevita.nomeCom`) e a inicial nunca indexa vazio
  (`inicialCom`).
- **`affectedKeys()` NÃO conta campo gravado com o mesmo valor.** Um teste de
  regra escrito para provar que o levita não muda o repertório de carona
  passava sozinho: ele gravava `songs: [{songId:'s1'}]`, que era exatamente o
  que já estava no documento. Para a regra, `songs` não mudou. Todo teste de
  "não pode mexer em X de carona" precisa gravar em X um valor DIFERENTE do
  que está lá.
- **A trava do tamanho reprovou TODO deploy por dias, e o CI ficou verde.**
  O app no ar ficou parado numa versão antiga enquanto entrega após entrega
  era aplicada e nada chegava ao celular de ninguém. Três erros se somaram, e
  os três eram meus:
  1. **A base foi medida fora da CI.** `BASE=3610328` saiu do site no ar, mas
     eu conferia o tamanho no meu contêiner, com outra versão do Flutter.
     **Medido: as flags do build mudam 73 bytes; a versão muda ~200 KB.** Eu
     reportei "folga de 59 KB" com um número que não era comparável ao da CI,
     onde o mesmo commit dava 3.720.932 e depois 3.852.078.
  2. **`channel: stable` sem versão fixa deriva no tempo.** A ação baixa o
     último estável no momento da execução: o mesmo commit passa a gerar
     tamanhos diferentes em dias diferentes, e um lançamento do Flutter
     estoura o orçamento sem ninguém ter mexido em código. Agora a versão é
     fixa nos dois workflows, e trocá-la exige medir a base de novo no mesmo
     movimento.
  3. **A trava morava só no workflow de publicação, que ninguém abre.** O CI
     — que é onde se olha — nem construía o pacote web. Agora a trava está no
     CI, com as mesmas flags da publicação, e **os testes do Worker, do
     service worker e das rotinas diárias também**: eles tinham o mesmo
     defeito, rodavam só na publicação.
  A lição que vale além deste caso: **número medido em ambiente diferente do
  que decide não é medida, é palpite** — e toda trava precisa falhar onde a
  pessoa olha, não onde o robô olha.
- **A versão fixada mentiu, e o palpite voltou um nível mais fundo.** Com
  `flutter-version: '3.50.0'` nos dois lados, eu medi 3.668.988 bytes e a CI
  mediu **3.868.219** no mesmo commit. A trava de versão estava funcionando —
  o log mostra `FLUTTER_ROOT=/opt/hostedtoolcache/flutter/stable-3.50.0-x64`.
  O problema era o meu SDK:

  ```
  Framework • revision ab2912035e (9 days ago)  • 2026-11-09
  Engine    • hash 6cd51c08a88e (14 months ago) • 2025-08-13
  Tools     • Dart 3.9.0
  ```

  Framework de 9 dias com motor e Dart de 14 meses: um `dart2js` velho,
  gerando menos código. **A string da versão não basta** — ela diz o
  framework, e quem compila é o motor. Agora a CI imprime
  `flutter --version`, `FLUTTER_ROOT` e `dart --version` no passo "Qual
  Flutter está medindo", antes de medir, e a mensagem de erro manda olhar
  para lá. A base passou a ser a que a CI mediu (3.868.219), com a prova de
  que ela mede o app e não ruído: 3.852.078 no `60f377c` e 3.868.219 no
  `83080d1`, e os 16 KB de diferença são exatamente a tela de hinos.
- **`--pwa-strategy` está deprecado e vai sair.** O log do build avisa, e
  aponta o [issue 156910](https://github.com/flutter/flutter/issues/156910).
  A flag não foi trocada de propósito: é ela que impede o Flutter de
  registrar o service worker dele por cima do nosso (`web/sw.js`). Quando
  ela sair, o build vai falhar ou — pior — voltar a registrar o worker do
  Flutter, e a trava da publicação pega isso. Ao mexer nisto, confira
  `navigator.serviceWorker.getRegistration()` no app publicado antes de dar
  por resolvido.
- **Status não é diagnóstico.** A rotina diária falhou duas noites seguidas
  dizendo só "O Worker respondeu 403: {...}". Cada status tem causa e conserto
  diferentes, e nenhum deles está no código do app: estão na Cloudflare, no
  console do Firebase ou no cadastro do robô. Agora
  `ferramentas/diagnostico.mjs` traduz o status para a causa provável e o
  conserto, e o job ainda pergunta ao Worker como ele está — então o caso mais
  comum (segredo faltando) se resolve lendo o próprio log.
- **E a raiz do Worker dizia "configurado" enquanto nada funcionava.** Ela
  conferia se os segredos estão **preenchidos**, que não é o que importa:
  `ROBO_EMAIL` preenchido não é o robô conseguir entrar, e conseguir entrar
  não é o cadastro dele estar aprovado no banco. Daí `GET /saude`, que tenta
  de verdade — entra, lê o próprio cadastro e diz a função — sem login,
  porque quem precisa dela é um job de madrugada e um leigo abrindo um
  endereço no celular. Guardada por 5 minutos: é endereço público, e um laço
  contra ela custaria uma leitura por chamada.
- **`null` que significa duas coisas acusa a pessoa errada.** `lerDoc`
  devolvia `null` tanto para 404 ("não existe") quanto para 403 ("o Firestore
  RECUSOU"), e quem chamava traduzia o `null` para *"Sua entrada ainda não foi
  aprovada por um líder"*. O 403 do banco nunca é sobre quem pediu: **o Worker
  lê o cadastro de quem chamou usando o token do ROBÔ dele**, e a regra de
  `users` é `souEu(userId) || aprovado()`. Então um robô não aprovado — ou um
  `FIREBASE_API_KEY` de um projeto com `FIREBASE_PROJECT_ID` de outro — faz o
  líder ler que ele não está aprovado, com a tela mostrando 👑 Líder ao lado.
  Agora 403 do banco virou `RoboSemAcesso`, que sai como **503 com o conserto
  dentro** (é falha do servidor, não de quem pediu), e "não existe cadastro"
  deixou de ser "não aprovado" — são consertos em lugares diferentes, e um
  deles não se resolve em Membros nenhum, porque a conta não aparece lá.
- **São DUAS contas de robô, e é fácil olhar a errada.** `ROBO_EMAIL` (na
  Cloudflare) é com quem o Worker fala com o banco; `FAXINA_EMAIL` (nos
  segredos do GitHub) é com quem os jobs se identificam. Podem ser a mesma, e
  é mais simples que sejam. Quando não são, o engano é cruel: a tela mostra
  aprovada a conta que você aprovou, e a recusa vem por causa da outra.
- **Nenhuma rota do Worker tinha teste, e `firebase.js` era o único arquivo
  dele sem nenhum** — justamente o que fala com o banco. Agora `rotas.test.mjs`
  assina um ID token de verdade (par de chaves gerado no teste, `fetch`
  respondendo pelo Google e pelo Firestore) e mede o que o log do job lê: o
  status e a frase. **Medido:** com o defeito de volta, 2 dos 12 falham; sem a
  casca que pega o que escapa, outros 2.
- **Diagnóstico errado que custou tempo:** quando o instrumento continuou
  aparecendo em inglês depois de corrigido, eu disse que era cache do service
  worker. Não era: não havia service worker nenhum. **Antes de culpar o
  cache, confira se ele existe** — `navigator.serviceWorker.getRegistration()`
  responde em um segundo.
- **O gesto de voltar saía do app.** Arrastar da borda esquerda, no app
  instalado, é um `history.back()`. Duas coisas foram precisas, nesta ordem:
  `PopScope(canPop: false)` na raiz, que segura o Flutter, e
  **`setUrlStrategy(null)` em `main()`**, que é o que resolve de verdade.
  O Flutter empilha uma entrada própria no histórico ao iniciar, para o
  botão "voltar" do navegador fechar telas; é a existência dessa entrada que
  faz o WebKit aceitar o gesto e desenhar o documento anterior — a tela de
  abertura — deslizando por baixo. Medido: `history.length` 3 com estado
  `{"flutter":true}` antes, 2 e estado `null` depois (o 2 é a página em
  branco do próprio teste; no app instalado sobra uma só).
  **O que se perde:** endereço por tela e o botão "voltar" do navegador.
  Nenhum dos dois é usado aqui — a navegação é por abas e por telas que
  abrem por cima, todas com seta de voltar na barra.

## Próximos passos combinados (fase 2)

Nesta ordem, e **nada disso antes de testar o app num iPhone real**:

0. ~~Agenda fixa + equipes~~ — **feito.**
0. ~~Cifra de verdade, colar cifra, cantor/músico~~ — **feito.**

1. ~~Aprovação do líder~~ — **feito.**
1. ~~Remover do ministério, devolver acesso e sair sozinho~~ — **feito.**
2. ~~**Avisos**: mensagem nova, "você foi escalado" e lembrete da
   véspera~~ — **feito**, por Worker da Cloudflare em vez de Cloud Function
   (ver "Avisos do chat" e "Avisos da escala"). Falta só "novo pedido de
   entrada" para o líder, que é o mesmo leque de envio com outro gatilho.
3. ~~**Rolagem sincronizada no culto**~~ — **feito** (ver "Modo Culto ao
   vivo").
4. ~~**Reações e "visto por"** no chat~~ — **feito**, com responder citando
   e @menção (ver "Reações, citação e visto por").
5. ~~**Líder redefine senha de um membro.**~~ — **decidido que NÃO**, e o
   motivo está em "Recuperar a senha". Exigiria chave de administrador, que
   não serve só para trocar senha: quem a tem entra como qualquer pessoa do
   ministério, líder incluído. O caminho que substituiu isso é o e-mail de
   recuperação.

Quando as Functions existirem, mover a função do usuário para um *custom
claim* no token: as regras passam a ler `request.auth.token.role` e somem as
leituras extras que hoje cada `get()` dentro da regra cobra.

## Próximos passos combinados (fase 3)

Saíram da auditoria de 16/11/2026, nesta ordem, uma entrega pequena de cada
vez:

1. ~~Cache persistente do Firestore~~ — **feito** (ver "O aparelho guarda o
   que já leu"). Medido: 202 documentos na segunda abertura → zero.
2. ~~"Excluir culto" deixa de existir~~ — **feito**, com `allow delete: if
   false` em `scales`.
3. ~~**Recuperar senha**~~ — **feito**, pelo e-mail (ver "Recuperar a
   senha"). O segundo caminho pedido — líder define senha provisória — foi
   recusado com motivo: é impossível sem chave de administrador, e a chave
   não tem escopo menor que "entrar como qualquer um".
4. ~~**"Novo pedido de entrada"** avisa o líder~~ — **feito** (ver "Aviso de
   novo pedido de entrada").
5. ~~**O Worker gera os cultos da agenda fixa**~~ — **feito** (ver "O Worker
   gera os cultos").
6. ~~**"3 de 7 confirmaram"**, com quem falta, e avisar o líder~~ —
   **feito** (ver "Quem já confirmou").
7. ~~**"Minhas próximas músicas"** no Início~~ — **feito** (ver "Minhas
   próximas músicas").
8. ~~**Tom, cifra e "tocada pela última vez"** ao escolher as músicas~~ —
   **feito** (ver "Escolher as músicas do culto").
9. ~~**Mensagem do chat vira observação do culto**~~ — **feito** (ver "Levar
   um recado do chat para o culto").
10. ~~**Limpeza de tela**~~ — **feito** (ver "Um cartão só, e as palavras
    certas").

### Tirar música do repertório (nunca apagar)

O repertório inteiro sumiu do banco em 14/11/2026, sem ninguém assumir. A
investigação mostrou que o app tinha um caminho só para apagar — menu ⋮ do
líder → confirmação que **não dizia o nome da música** — e que nenhuma
limpeza alcançava `songs`. A causa provável foi um toque no menu errado.

Apagar deixou de existir. Vale a mesma regra dos cultos, **"cancelar é um
campo, nunca exclusão"**:

- `SongModel.archived` + `archivedAt` + `archivedBy`. O documento FICA.
- **`allow delete: if false` em `songs` e em `arrangements`** — para todos,
  líder incluído. Apagar de verdade só pelo console do Firebase, onde não se
  chega por engano no meio de um culto.
- Arquivar e desarquivar são `update` comuns, e `update` em `songs` já era só
  do líder: a mesma linha cobre as duas coisas.
- **A música arquivada continua em `SongsProvider.allSongs`**, e é por isso
  que o culto em que ela foi tocada segue mostrando o nome em vez de "Música
  removida". Quem oferece música para escolher usa
  **`SongsProvider.repertorio`**, que exclui as arquivadas. Confundir as duas
  é o jeito de estragar isto: `allSongs` resolve por id, `repertorio` oferece.
- A lista "Arquivadas" aparece só para o líder, com "Devolver" em cada linha.

**Se precisar recuperar algo apagado antes disto:** o documento some, mas a
subcoleção `arrangements` não — no console ela aparece como documento em
itálico, com a cifra dentro. E cultos anteriores ao modelo de três camadas
ainda guardam nome e artista copiados dentro de `songs[]`.

### Bíblia

Leitura offline, dentro do app: atalho no Início e em Perfil, grade de livros
AT/NT com busca, capítulos, versículos numerados, fonte ajustável, copiar e
compartilhar com a referência, e "Abrir no YouVersion" para quem quer outra
tradução.

- **O texto é ATIVO, não código.** `assets/biblia/<id>.json`, declarado no
  `pubspec.yaml`. Na web, um ativo do Flutter só sai pela rede quando alguém
  o pede: a Bíblia não entra no pacote inicial e não atrasa a abertura de
  quem nunca a abre. **Medido: zero pedidos de Bíblia ao abrir o app.**
- **A CI falha se o pacote inicial passar de 100 KB acima da base** medida em
  15/11/2026 (3.610.328 bytes). É a trava contra alguém transformar o texto
  em código sem perceber.
- **O `web/sw.js` deixa a Bíblia fora do que guarda na instalação** e a guarda
  quando a tradução é aberta. Sem essa exclusão, toda abertura de app
  baixaria 7,7 MB. **Medido: depois de abrir uma vez, a tradução abre sem
  internet nenhuma.**
- **Nada disso vai para o Firestore.** Seriam ~31 mil documentos por
  tradução, e a cota gratuita do Spark acabaria num domingo.
- **Só texto que pode ser distribuído.** Hoje: Bíblia Livre, que é
  **Creative Commons Atribuição 3.0 Brasil — não é domínio público** e exige
  crédito (por isso o crédito viaja dentro do arquivo e aparece no rodapé da
  leitura); e Almeida 1911, em domínio público. NVI, NTLH, ARA, ARC e
  companhia pertencem a editoras e **não entram**, nem que se ache o arquivo
  pronto num repositório público, nem baixando em vez de hospedando: quem
  copia a obra para o aparelho da pessoa continua sendo o app. Um teste falha
  se alguma delas aparecer na lista.
  **O caminho legítimo, se um dia for preciso:** `api.bible` (American Bible
  Society) licencia por tradução e tem plano gratuito com 3 Bíblias e 5 mil
  chamadas por mês — exige chave e conferir se a NVI em português está no
  catálogo; ou pedir autorização à SBB (ARA, ARC, NTLH) e à Biblica (NVI).
- **O botão leva ao capítulo certo na NVI**, em `bible.com`, que é de quem
  tem o direito de publicá-la. `129` é a NVI em português e os livros usam o
  código USFM de três letras (`JHN`, `SNG`); os dois foram conferidos no
  próprio site, e um teste cobre os 66 códigos.
- **Os `.json` não estão no histórico como patch:** são gerados por
  `bash ferramentas/baixar-biblia.sh`, que busca na fonte, confere os 66
  livros e grava sempre igual. Estão commitados no repositório, porque é o
  GitHub Pages que os serve. Se `flutter test` reclamar de arquivo faltando,
  é esse script que não rodou.
- Acrescentar uma tradução é um arquivo em `assets/biblia` mais uma linha em
  `traducoesDisponiveis`. Nenhum código novo. Ver `assets/biblia/LEIA-ME.md`
  para o formato e a procedência de cada texto.
- A última tradução e o último capítulo ficam no aparelho
  (`LocalStorageService`), não no banco: é o marcador de quem lê, não há o
  que sincronizar, e no Firestore custaria uma leitura por abertura.

### Saúde do sistema

Os robôs falharam em silêncio por **dias**. A rotina diária batia num 403, o
motivo ficava no log do Worker, e ninguém abre log de Worker — então a escala
parou de ser criada e o lembrete da véspera parou de chegar, sem nada
vermelho em lugar nenhum. A causa final: uma `FIREBASE_API_KEY` digitada à
mão na Cloudflare, com um caractere errado.

- **Cartão "Saúde do sistema" em Perfil, só para líder**, com cinco linhas:
  servidor dos avisos, robô, criação dos cultos, lembrete da véspera e faxina
  do chat. Cada uma diz **o que fazer**, não o número do erro: "o Worker
  respondeu 403" não é informação para quem vai consertar; "o robô não é
  líder: promova-o em Membros" é.
- **Aviso vermelho no Início** quando algo está quebrado, e **sem "agora
  não"**: ele sai quando o problema sai. Um cartão que se dispensa voltaria
  ao mesmo lugar — o toque sem pensar do primeiro dia, e o aviso nunca mais
  aparece.
- **Coleção `saude/{cultos,vespera,faxina}`:** cada rotina carimba "rodou às
  tantas" ao terminar, por `ferramentas/carimbo.mjs`. **A hora é do
  SERVIDOR** (`setToServerValue: REQUEST_TIME`) e a regra exige: com a hora
  do runner do GitHub, um relógio torto faria a tela dizer "rodou hoje" sobre
  uma rotina parada há uma semana.
- **O carimbo de FALHA também é gravado.** Sem ele, uma rotina que falha todo
  dia na mesma hora pareceria "rodou ontem" para sempre — que é exatamente o
  que aconteceu.
- **Falhar no carimbo não derruba a rotina:** quando ele não grava, o
  trabalho de verdade já foi feito. Derrubar o job por causa do registro
  transformaria um problema de anotação numa execução perdida.

**As três decisões que evitam alarme falso** — e alarme falso é o jeito mais
rápido de uma tela de diagnóstico virar tela que ninguém lê:

1. **"Não consegui falar com o Worker" é `desconhecido`, nunca vermelho.** É
   o wi-fi da igreja, não o sistema. Nenhum estado `desconhecido` acende o
   aviso do Início.
2. **Alerta em 26 h, vermelho só em 36 h.** Um job diário chega
   legitimamente perto das 24 h sem ter falhado; acender em 24 h daria alarme
   falso todo dia, pouco antes da hora dele.
3. **Carimbo ausente é `desconhecido`.** No dia desta entrega nenhuma rotina
   tinha carimbo, e estrear uma tela de diagnóstico em vermelho é a pior
   apresentação possível.

Nenhum segredo novo: `FIREBASE_PROJECT_ID` já existia (a faxina o usa) e
passou a ser passado também à rotina diária. O `/saude` do Worker é GET sem
login, então consultá-lo não custa leitura de Firestore nem token.

### Hino pelo número (Harpa Cristã e Cantor Cristão)

Na igreja o dirigente anuncia "hino 15 da Harpa" sem avisar antes. Antes
disto, quem ia tocar saía do culto, ia em Músicas, tentava lembrar o nome do
hino e procurava — com a igreja já de pé. Agora: Início → "Hino pelo número",
ou o ícone de teclado na aba Músicas, digitar 15.

**O TEXTO DOS HINOS NÃO ESTÁ NO APP, e isso é decisão de licença.** Vale a
regra deste projeto — nada protegido por direito autoral embarcado:

- **Harpa Cristã: não dá, e não é dúvida.** A CPAD é dona do hinário desde
  1941 e diz, no texto do app dela mesma (© 2017 CPAD), que "tem publicado,
  **revisado, ampliado** e divulgado a Harpa Cristã". **246 dos 640 hinos** são
  tradução ou adaptação de Paulo Leivas Macalão, morto em **26/08/1982** —
  protegida até **31/12/2052** pelo art. 41 da Lei 9.610/98. E o art. 14 fecha
  o argumento do "hino antigo é livre": *"É titular de direitos de autor quem
  adapta, traduz, arranja ou orquestra obra caída no domínio público"*. Ainda:
  a numeração atual (os 524 antigos + 116 acrescentados nos anos 1990) é a
  seleção e organização da CPAD, protegida por si (art. 7º, XIII), e houve
  condenação no TJ-RJ por reprodução não autorizada da obra.
- **Cantor Cristão: mais perto, mas ainda não.** Os dois maiores tradutores
  estão em domínio público — **Salomão Ginsburg (1867–1927)**, 104 hinos, e
  **William Edwin Entzminger (1859–1930)**, 72 hinos — e a numeração está
  estável em 578 desde a 18ª edição (1924), indo a 580 em 1964 e 581 em 1971.
  O que falta são **duas coisas concretas**: (1) não existe digitalização de
  uma edição anterior a 1955 em lugar nenhum que eu tenha achado — a única
  transcrição é a do Wikisource, que declara como fonte a **37ª edição, 2007,
  da JUERP/Geo-Gráfica**, está marcada "Verificação pendente, 0%" e não tem
  selo de domínio público (o rodapé CC BY-SA é a licença do site para as
  contribuições, não um parecer sobre o hinário); (2) não existe lista de
  tradutor por hino em forma usável — o índice do hymnary.org (CC1971) só traz
  tradutor na página de cada hino, uma por uma, e o próprio site marca o
  hinário como *"has not been proofed"*. Os nomes conhecidos cobrem 228 dos
  581; o resto é "diversos".
  **O que destravaria:** uma cópia ou scan da 18ª (1924) ou da 30ª (1956) —
  Biblioteca Nacional Digital, acervo de seminário batista, Convenção Batista
  Brasileira. Com ela, o compilador (Ginsburg, †1927) está em domínio público
  e a numeração bate com a de hoje nos hinos 1 a 578.

Então o app sabe **numerar e achar** hinos; o texto de cada um entra pelo
cadastro do ministério, do hinário que a igreja comprou, com o "Colar cifra"
que já existia.

  **Atualização de 19/11/2026 (tarde):** o texto passou a poder entrar em lote,
  pela tela "Importar hinário" — ver "Biblioteca de hinários". O que não mudou:
  nenhuma letra mora no repositório nem no pacote do app. "Ainda não está no repertório" é um estado NORMAL da tela, com
caminho para resolver — não um erro.

**Como foi feito:**

- **`hinario` + `numero` na música, não `numeroHarpa`.** Um campo com o nome
  de um hinário resolveria a Harpa e deixaria o Cantor de fora, e um hinário
  novo obrigaria a mexer em modelo, regra e tela. Agora é uma linha em
  `core/constants/hinarios.dart`.
- **Os dois campos andam SEMPRE juntos**, no modelo (`SongModel.ehHino`) e na
  regra. Hinário sem número não dá para abrir; número sem hinário não dá para
  saber de onde é — e documento pela metade é o jeito mais silencioso de o
  teclado parar de achar o hino, sem nada na tela.
- **A sigla vai gravada no TÍTULO** ("HC 15 · Sou Grato", `Hinario.tituloDe`),
  e é o contrário da regra da escala, que guarda referência e nunca cópia. De
  propósito: assim o hino se reconhece na escala, no chat e no lembrete da
  véspera sem que nenhuma dessas telas saiba o que é um hinário. **Mas quem
  ACHA o hino pelo número usa os CAMPOS, nunca o título** — se dependesse do
  texto, um líder corrigindo o nome quebraria o teclado sem ter como saber
  por quê.
- **O teto do número é generoso de propósito.** A Harpa "Revisada e Ampliada"
  tem 640, mas há edição sem os quatro hinos pátrios, com 636. Errar para
  MAIS é inofensivo: um número que a igreja não tenha cai em "ainda não está
  no repertório", que é verdade. Errar para MENOS diria "não existe" sobre um
  hino que existe — mentira no meio do culto.
- **O teto na REGRA é largo (1 a 9999), e isso é a lição da trava de
  tamanho.** O teto de verdade (640 e 581) mora no app, onde se troca sem
  deploy de regra. Repetir o número exato na regra seria pôr um número que
  pode mudar no lugar mais difícil de mudar — foi assim que a trava de tamanho
  reprovou todo deploy por dias. A regra impede lixo; quem diz "não existe o
  hino 700" é a tela.
- **Abrir sem confirmar, sem chutar.** `Hinario.podeCrescer` decide: quando
  nenhum número maior é possível ("65" na Harpa, porque 650 passa de 640), a
  abertura é imediata; quando ainda pode crescer ("15" pode virar 150), o app
  espera 600 ms. Sem espera, digitar "150" abriria o hino 1 no primeiro toque.
- **"Fora do repertório" não é "não cadastrado".** `hinoCadastrado` olha
  também as arquivadas, porque confundir os dois faria o líder cadastrar de
  novo um hino que já existe — perdendo a cifra que alguém já colou.
- **"Cadastrar agora" só aparece para o líder**, porque só o líder cria música
  no banco. Para um levita o botão falharia com erro de permissão, que não
  explica nada; a frase diz para pedir ao líder.
- **A lista de hinários é fechada na regra**, e um teste em Dart lê o
  `firestore.rules` e falha se um hinário novo for acrescentado ao app e
  esquecido lá — mesmo tipo de contrato do `agenda_contrato.json`. Sem ele, o
  cadastro seria recusado com erro de permissão, que não explica nada.
- **Mexer em `hinario`/`numero` é só do líder:** os dois ficam FORA da lista
  fechada de campos que quem cadastrou pode corrigir. Trocar o número de
  carona criaria dois hinos com o mesmo número.
- **Último hinário e últimos 8 hinos abertos ficam no APARELHO**, como o
  marcador da Bíblia: é o histórico de quem está com o celular na mão, não há
  o que sincronizar, e no Firestore custaria uma escrita por hino aberto.
- A busca por nome, artista, **trecho da letra** e número ignora acento
  (`core/utils/texto.dart`) — "lembro do trecho, não do número" é como a
  maioria procura hino.
- **Nada no Firestore além dos hinos que o ministério cadastrar**, e zero
  ativo novo: não há arquivo de hinário para baixar, então não há pedido na
  abertura do app nem peso no pacote inicial.

**No Modo Culto ao vivo e ao montar o culto** (entrega 2):

- O **mesmo teclado** nos três lugares, por um parâmetro `paraEscolher` que
  faz a tela devolver o hino em vez de abri-lo. Três telas parecidas é o
  jeito de uma ficar para trás quando a regra muda — e as duas novas herdam
  de graça o "não existe o hino 700", o "ainda não está no repertório" e os
  últimos abertos.
- **O hino entra como música EXTRA do culto e sincroniza** como qualquer
  outra, porque a posição que viaja entre os aparelhos é `{índice da música,
  âncora}` e índice só existe para música que está na lista do culto.
- **Só o líder põe hino no culto, inclusive no Modo ao vivo.** Mexer no
  repertório é do líder na regra do banco, e afrouxar isso por causa de um
  caso de domingo abriria "qualquer aprovado edita o culto" para sempre. Para
  quem não é líder o botão nem aparece.
- **`ScaleModel.comMusicaExtra` é pura e mora no modelo**, porque pôr a mesma
  música duas vezes não dá erro nenhum: ela apareceria duplicada na tela, o
  índice do Modo ao vivo apontaria para a cópia errada e "5 músicas" passaria
  a mentir.
- A conta da cifra, do tom e do mapa de âncoras saiu de dentro do laço
  (`_prepararMusica`): o hino que entra agora precisa das MESMAS âncoras dos
  outros aparelhos, senão o culto desalinha sem nada aparecer na tela.

### Cadastrar música com menos esforço

Cadastrar era digitar nome, artista, tom e colar a cifra — de memória. Quatro
atalhos, e **nada é buscado nem gerado automaticamente**: o app não baixa
página de site nenhum, nem por decisão do dono nem porque copiar a cifra de
lá é o que a licença não permite.

- **"Buscar no Cifra Club" na busca que não achou nada.** É o melhor momento
  do app: a pessoa acabou de digitar o nome, e o que falta é a cifra dele. O
  mesmo botão no "ainda não está no repertório" do teclado de hinos, com
  "Harpa Cristã 15" já no texto.
- **Faixa "Toque para usar a cifra copiada"**, quando a pessoa volta do Cifra
  Club. Ela **não lê a área de transferência para decidir se aparece**: no
  iPhone, ler exige um toque e mostra um pedido de permissão, e perguntar
  antes de ter o que oferecer é o caminho para a pessoa negar para sempre. O
  sinal é outro e mais forte: o app guardou que ela acabou de tocar em
  "Buscar no Cifra Club" (`LocalStorageService.marcarIdaAoCifraClub`, 30
  minutos). A leitura acontece **só no toque**, e se o que vier não parecer
  cifra a faixa diz isso em vez de abrir um cadastro vazio.
- **Web Share Target no Android** (PWA instalado): o app aparece no menu
  "Compartilhar". O que chega pode ser a cifra (quem seleciona tudo) ou só o
  endereço da página (quem usa o botão do site), e `comoUsarCompartilhado`
  decide — cifra vira cifra, endereço vira **link** da música. No iPhone não
  há nada a esconder: o Safari não tem Web Share Target, então o app não
  aparece no menu de lá. A leitura do parâmetro é no `avisos.js`, como o
  `?abrir=chat` já fazia, e é consumida na primeira leitura para o cadastro
  não reabrir a cada volta para a aba.
- **Aviso de duplicata por nome parecido, ANTES de criar**, com os nomes à
  vista. `nomesParecidos` ignora acento, maiúscula e pontuação, e acha
  "Sou Grato" contra "HC 15 · Sou Grato" — a mesma música cadastrada de outro
  jeito. **Piso de quatro letras** para a continência valer: sem ele, "Ele"
  casaria com meio repertório e o aviso perderia o crédito na primeira vez.
- **Uma heurística só.** Os três caminhos novos passam pelo MESMO
  `CifraColada.analisar` do campo "Colar cifra". Duas heurísticas para a
  mesma coisa é o jeito de elas discordarem um dia.

### Os atalhos do computador do dono

Três scripts em `ferramentas/`, para rodar no Mac. Eles existem porque os
comandos de verdade falham de jeitos que não explicam nada, e porque o app
vai passar para as mãos de um líder leigo.

- **`aplicar.sh`** — aplica o patch que está na área de transferência.
  Confere se o repositório está limpo (`git am` com mudança não salva para no
  meio e deixa um estado que assusta), mostra o que o patch traz, e no erro
  faz `git am --abort` e diz que o patch foi feito a partir de outro commit.
- **`publicar.sh`** — roda o que a CI roda, na ordem, e só então envia:
  analyze, testes do app, testes das rotinas e do Worker, testes de regra
  (com pergunta, que é o passo lento), push, regras do Firestore e Worker.
  Pergunta antes de cada passo que muda algo fora do computador, e termina
  consultando o `/saude`.
- **`robo.sh`** — troca a senha do robô nos TRÊS lugares que precisam
  combinar: a conta no Firebase Authentication, `ROBO_SENHA` na Cloudflare e
  `FAXINA_SENHA` no GitHub. **Não guarda senha nenhuma**: pede na hora, sem
  eco, sem arquivo, sem histórico de terminal. O primeiro passo é no console
  do Firebase, com as mãos do dono — trocar senha de conta pelo terminal
  exigiria chave de administrador, que este projeto não usa. O script avisa
  que a ordem importa: entre o primeiro passo e o último, o robô fica sem
  entrar.

### Recuperar a senha

Ninguém entrava com e-mail: entra com o NOME, e o Firebase, que exige um
endereço, recebe um inventado a partir dele — `ana@levitas.app`. Esse domínio
não é de ninguém. Então o "esqueci minha senha" do Firebase mandava o link
para o vazio, e **senha esquecida era acesso perdido, para todo mundo.**

- **Trocar a senha de outra pessoa é impossível sem chave de administrador.**
  O Firebase só deixa cada conta trocar a sua. E o console do Firebase
  também não faz isso: lá dá para criar conta, apagar conta e mandar e-mail
  de recuperação — não definir a senha de uma conta que já existe.
- **A chave de administrador foi recusada, e o motivo não é cautela vaga.**
  Ela não serve só para trocar senha: quem tem a chave privada assina um
  token para QUALQUER conta e entra como o líder do ministério. Não existe
  permissão menor no Firebase — a menor é "Firebase Authentication Admin", que
  já troca a senha de todos, o líder incluído. Ela ficaria atrás de um
  endereço público (o Worker), onde hoje uma falha de autenticação custa um
  aviso indevido e passaria a custar o projeto inteiro. Revogar exige IAM no
  Google Cloud, que não é operação de leigo; trocar a senha de um robô é. E o
  registro de "quem trocou a senha de quem" seria escrito pelo mesmo
  componente que tem a chave, com o Admin SDK ignorando as regras do banco —
  não é prova de nada.
- **Sobrou um caminho só, e ele só funciona ANTES:** cadastrar um e-mail de
  verdade enquanto a pessoa ainda consegue entrar. Daí o desenho todo ser
  sobre chegar nisso antes de alguém esquecer a senha.

Como ficou:

- **Um e-mail de verdade substitui o endereço interno da conta**, porque uma
  conta do Firebase tem UM endereço. Consequência direta: **quem cadastra
  e-mail passa a entrar com ele**. Por isso o campo da tela de login virou
  "Nome ou e-mail" (`UserModel.emailParaEntrar`: com arroba é e-mail, sem
  arroba é nome). No celular da pessoa isso é invisível, porque a sessão fica
  salva; aparece no aparelho novo.
- **O e-mail só passa a valer quando a pessoa clica no link**
  (`verifyBeforeUpdateEmail`). Sem essa confirmação, um e-mail digitado
  errado viraria o endereço da conta — e aí a pessoa não entraria mais nem
  receberia o link para consertar.
- **O endereço NÃO vem para o Firestore**, só o sim/não
  (`UserModel.recuperacaoPorEmail`). Todo aprovado lê `users`: gravar o
  e-mail de cada um entregaria a lista de e-mails do ministério a qualquer
  membro.
- **Quem grava o sim/não é uma conferência na abertura do app**
  (`AuthProvider.conferirRecuperacao`), porque o endereço muda FORA do app —
  a pessoa clica no link quando quiser, às vezes dias depois, no computador.
  Não existe momento melhor. A conferência só escreve quando o valor muda:
  uma escrita por abertura por pessoa seria cota jogada fora.
- **"Esqueci minha senha" pede o E-MAIL, nunca o nome.** Pedir o nome
  mandaria o link para `ana@levitas.app`, a tela diria "enviamos" e nada
  chegaria nunca — a falha silenciosa que este projeto não aceita. O
  endereço interno é recusado antes de tentar (`UserModel.enderecoInterno`).
- **A tela não promete que chegou.** O Firebase não conta se a conta existe
  (é proteção contra descobrir quem tem conta no app), então o texto é "se
  existir uma conta com esse e-mail, o link chega" e diz o que fazer se não
  chegar.
- **`setLanguageCode('pt-BR')` antes de cada envio**, senão o e-mail do
  Firebase chega em inglês — para quem "só sabe usar WhatsApp", um e-mail em
  inglês é um e-mail que não existe.
- **O líder vê quem ainda está desprotegido**, numa tarja na Equipe: "3
  pessoas não conseguem recuperar a senha". Fica na cara, e não num menu,
  porque é a única coisa deste app sem conserto depois. Zero não vira tarja
  verde: aviso que fica na tela quando não há nada a fazer ensina a não olhar.
- **O link de recuperação funciona sem Firebase Hosting publicado.** Medido:
  `espiritual-d2403.firebaseapp.com/__/auth/action` responde 200 com o
  `action.js` do Firebase, enquanto a raiz do domínio dá 404.

**O defeito que esta mudança quase criou:** `changePassword` reautenticava com
o endereço derivado do nome. Quem cadastrasse e-mail passaria a ter outro
endereço na conta, e a troca de senha falharia com "a sua senha está
incorreta" — com a senha certa, e só para quem se protegeu. Agora o endereço
sai de `account.email`, e um teste varre o arquivo para garantir que nenhuma
reautenticação volte a derivar do nome.

**Limites conhecidos:**

- **Quem está `pendente` não alcança o Perfil**, então só cadastra e-mail no
  próprio cadastro (o campo existe lá, opcional) ou depois de ser aprovado.
- **O nome deixa de ficar reservado.** A unicidade de nome vinha de o
  endereço interno ser único no Firebase. Quando alguém troca para um e-mail
  de verdade, `ana@levitas.app` fica livre e outra pessoa poderia se cadastrar
  como "Ana" — o líder vê o nome repetido na hora de aprovar, e é aí que isso
  se resolve. Conferir no app antes do cadastro exigiria ler `users` sem
  estar logado, o que as regras proíbem de propósito.
- **Quem não cadastrar e-mail e esquecer a senha perde o acesso.** Não há
  conserto, e o app diz isso em vez de prometer o contrário.

### O chat some depois de 30 dias

Conversa de combinação — "quem leva o cabo?", "ensaio às 19h" — não é
arquivo. Some em 30 dias; o que for decisão, o líder fixa.

- `MessageModel.venceu(agora)` é a regra, num lugar só, porque **três** coisas
  dependem dela: a tela, que esconde; a faxina, que apaga; e a regra do
  banco, que decide o que o líder pode mexer.
- **A tela esconde o vencido já na próxima abertura**, sem esperar a faxina.
  Assim a promessa vale desde o primeiro dia, e se a faxina parar o pior caso
  é ocupar banco — não mostrar recado velho.
- **`expiraEm` vai gravado na mensagem**, nulo quando fixada. Quem apaga roda
  fora do app e precisa saber o prazo sem reimplementar a regra.
- **Desafixar devolve o prazo contado do horário ORIGINAL.** Uma mensagem de
  dois meses que sai do topo não ganha mais 30 dias de vida.
- A regra do banco recusa fixada com prazo e não fixada sem prazo, para os
  dois campos não se separarem.
- **Ninguém reescreve o texto de uma mensagem**, nem o autor nem o líder. O
  líder só alcança os três campos de fixar.

**Por que a faxina é um job, e não a política de TTL do Firestore:** a
documentação do Firebase lista "TTL deletes" entre os recursos **sem cota
gratuita** — exige faturamento ativo, ou seja, Blaze. Este projeto fica no
Spark. Então é `.github/workflows/faxina-chat.yml`, diário, com exclusões
comuns (20 mil/dia na cota do Spark, muito acima do que um ministério gera).

- Ela entra como **um líder comum, com e-mail e senha**, nunca com chave de
  administrador: a chave ignora todas as regras e, se vazar, dá acesso a
  tudo; a senha do robô se troca e acabou.
- **Medido no emulador:** `where('expiraEm','<=',agora)` NÃO pega documento
  com `expiraEm` nulo nem sem o campo — só o vencido. Mesmo assim o script
  confere `fixada` antes de apagar, porque o estrago de um dia essa semântica
  mudar seria apagar justamente o que pediram para guardar.
- Sem os segredos configurados ela roda, diz que não está configurada e
  termina em verde.
- **Ela apaga os áudios ANTES das mensagens.** Se parar no meio, o pior caso
  é uma bolha dizendo que o áudio não está mais disponível — não meio mega de
  som órfão que ninguém alcança para apagar.

### Mensagem de voz

Segurar o microfone para gravar, arrastar para o lado para cancelar, limite de
dois minutos. O som vai para o Firestore, porque o **Cloud Storage não está no
plano grátis** desde fev/2026.

- **O áudio mora num documento à parte** (`audios/{audioId}`), e a mensagem só
  guarda a ficha: `audioId`, `audioDuracaoMs`, `audioTipo`. É isso que faz
  abrir o chat custar o mesmo de antes: os bytes só descem quando alguém toca
  no play. Os dois são gravados **num lote só** — mensagem apontando para
  áudio que não existe seria um play carregando para sempre.
- **Gravar e tocar é JavaScript** (`web/audio.js`), como já são a detecção de
  PWA e o compartilhar. `MediaRecorder` e `<audio>` o navegador já tem; o
  pacote Flutter equivalente pediria configuração nativa de Android e iOS
  para resolver o que o navegador faz sozinho.
- **O formato é a parte que dá errado, e um teste de navegador provou.**
  Pedir `audio/mp4` e conferir são coisas diferentes: `isTypeSupported` disse
  que sim e o MediaRecorder entregou `audio/mp4;codecs=opus` — contêiner da
  Apple com som que a Apple não toca. Então o AAC é pedido **pelo nome**
  (`audio/mp4;codecs=mp4a.40.2`), webm/opus vem antes do mp4 solto (ao menos
  se anuncia pelo que é), e o formato de verdade viaja junto do áudio.
- **`levitaPodeTocar` não tira o `;codecs=` antes de perguntar.** Tirava, para
  "evitar falso negativo", e era justamente o que transformava um mp4/opus num
  play mudo no iPhone. E porque `canPlayType` responder "maybe" é literalmente
  um talvez, o elemento tem `onerror`: o id que falhou sai em
  `levitaEstadoAudio`, e a bolha troca o play por **"Este áudio não toca neste
  aparelho"**. Dois caminhos para o mesmo aviso, porque um play que não faz
  nada é o pior desfecho possível.
- **Teto de 800 KiB**, conferido no app e na regra. 32 kbps é um pedido, não
  uma promessa: medido, dois minutos saíram a 34–36 kbps (~531 KiB). Um teto
  apertado seria recusar a mensagem *depois* de a pessoa falar dois minutos.
- **O áudio vence junto com a mensagem** — `expiraEm` igual nos dois, nulo nos
  dois quando fixada. Fixar e desafixar mexem nos dois documentos no mesmo
  lote, senão a mensagem ficaria no topo e o som sumiria em 30 dias.
- **A trava de dois minutos para a gravação e guarda o que já foi dito**, em
  vez de descartar tudo por passar do tempo.
- **Medido no Chromium** (`getUserMedia` trocado por um oscilador, porque
  contêiner não tem placa de som — todo o resto é o código real): grava, o
  base64 volta, o `<audio>` toca, pausa e retoma, cancelar solta o microfone e
  gravar de novo funciona, e áudio corrompido devolve `falhou` em vez de
  silêncio. **O que NÃO pude testar aqui é o microfone de verdade num
  iPhone** — a permissão e o formato que o Safari escolhe.

### Avisos do chat

Notificação de mensagem nova, com o app fechado, no Android e no iPhone. Sem
Cloud Functions: **o gatilho é um Worker da Cloudflare**, no plano gratuito de
100 mil pedidos por dia. O código fica em `worker/`, e o passo a passo de
publicar está em `worker/LEIA-ME.md`.

- **O Worker não grava nada.** Quem grava a mensagem é o app, com as regras do
  Firestore valendo. O Worker confere e manda o aviso. Se ele cair, o chat
  continua inteiro — só não chega notificação. Foi o que permitiu pendurar
  isto no app sem risco: `avisarDoChat` nem devolve erro para a tela.
- **O caminho que MOSTRA erro é o "Testar aviso"**, no Perfil. Aviso é
  invisível por natureza: sem um botão que diga "não chegou, e por quê",
  ninguém leigo descobriria que está quebrado.
- **Três conferências fazem o Worker não ser um megafone aberto**, porque o
  endereço dele é público: o ID token é verificado com as chaves do Google
  (e o `aud` tem de ser ESTE projeto, senão qualquer conta Firebase do mundo
  passaria); a pessoa tem de estar aprovada; e a mensagem tem de existir, ser
  dela e ter **menos de 2 minutos**. Essa última é o que impede pegar o id de
  uma mensagem antiga do chat — que todo aprovado lê — e reavisar o
  ministério com ela.
- **A cifra é feita à mão, com a WebCrypto** (RFC 8291 e 8292, em
  `worker/src/push.js`): a biblioteca `web-push` do npm usa o `crypto` do
  Node, que não existe num Worker. São ~120 linhas, e o teste faz **o papel do
  aparelho que recebe**: gera as chaves como o navegador geraria, manda cifrar
  e decifra de volta. Isso importa porque **erro de cifra não aparece no
  envio** — o serviço de push aceita os bytes, responde 201, o aviso chega ao
  aparelho e some sem nada na tela.
- **Não é FCM.** Web Push com VAPID é padrão e funciona no Chrome, no Firefox
  e no Safari — no iPhone, em PWA instalado, desde o iOS 16.4. O FCM exigiria
  uma chave de conta de serviço do Google, que é o tipo de credencial que este
  projeto evita.
- **O robô entra como líder comum, com e-mail e senha**, igual à faxina do
  chat, e pode ser a mesma conta. Chave de administrador ignoraria todas as
  regras do banco.
- **`endpoint` é uma CHAVE, não um endereço.** Quem o tem manda notificação
  para aquele celular direto, sem passar pelo Worker e sem limite. Por isso a
  regra de `pushSubs` **não deixa um levita aprovado ler a inscrição de
  outro** — só a própria. Quem lê a lista inteira é o líder, que é como o robô
  entra.
- **Uma inscrição por APARELHO**, com id sorteado guardado naquele navegador
  (`LocalStorageService.idDoAparelho`). Sem id estável, cada abertura criaria
  um registro novo e o ministério acumularia inscrições mortas — e cada aviso
  tentaria mandar para todas. As que o serviço de push recusa (404/410) o
  Worker apaga na hora.
- **Um aviso só, que se atualiza.** Etiqueta fixa `levita-chat` e a contagem
  lida das notificações que já estão na tela: a segunda mensagem vira "2
  mensagens novas". **Medido no Chromium:** três mensagens seguidas deixam
  **uma** notificação aberta, com a contagem certa.
- **A permissão só se pede dentro de um toque** — o iPhone não abre a caixa
  fora de um gesto. E negado **não se pergunta de novo**, nem reinstalando o
  app: por isso desligar os avisos no Perfil mantém a inscrição e só marca o
  registro, em vez de desinscrever.
- **Sem o app na tela de início, o iPhone não tem Push nenhum** — o
  `PushManager` nem existe no Safari comum. A tela então mostra o passo a
  passo de instalar, em vez de um botão que não funcionaria.
- **"Silenciar até amanhã" não é meia-noite.** Às 23h50 isso silenciaria por
  dez minutos e a pessoa acharia o botão quebrado. É o próximo 7h que esteja a
  mais de uma hora; de madrugada vale o 7h de hoje. Função pura que recebe
  `agora`, testada na virada do dia, do mês e do ano.
- **Tocar na notificação leva ao Chat por dois caminhos**, porque o app pode
  estar aberto ou fechado — e porque o app **não tem endereço por tela** (o
  `setUrlStrategy(null)` tirou isso para o gesto de voltar não sair do app).
  Com o app aberto, o service worker manda `{tipo:'ABRIR_CHAT'}` para a
  página; fechado, abre com `?abrir=chat`, que o `avisos.js` lê e apaga do
  endereço. O Flutter pergunta de 1 em 1 segundo e troca de aba. Os dois
  caminhos foram medidos no Chromium.
- **Perder o acesso apaga a inscrição.** Sem isso o aparelho continuaria
  recebendo aviso de cada mensagem de um ministério de que a pessoa já não faz
  parte — e a regra do banco não pegaria, porque quem manda é o robô, que é
  líder.
- **O limite de 30 por minuto é o cinto, não o cadeado.** Ele mora na memória
  do isolate, e a Cloudflare roda vários — então não é exato. O que segura
  abuso são as três conferências acima; o limite só impede um script em laço
  queimar a cota de leitura do Firestore.

### Instalar o app

O cartão "Instale o LevitaSync no celular" fica no Início até estar instalado,
e há uma linha em Perfil.

- **Não existe mais "Agora não".** Existia, e guardava a escolha para sempre:
  um toque sem pensar no primeiro dia e o convite nunca mais aparecia. Foi o
  que aconteceu com o dono do app, que passou semanas sem o aplicativo
  instalado sem entender por que os avisos não chegavam.
- No iPhone o texto não é preferência, é requisito: **fora da tela de início o
  Safari não tem Web Push nenhum**. O passo a passo usa os ícones do iOS
  (Compartilhar → Adicionar à Tela de Início).

### Dois toques para abrir o teclado (iPhone)

Tocar na caixa de texto do chat não abria o teclado; o segundo toque abria.
Não era o Flutter nem o Safari: era CSS **nosso**.

- **Medido no DOM vivo do app publicado:** o motor do Flutter marca
  `user-select: none` no `<body>` (para o canvas não virar texto selecionável),
  e `user-select` **se herda**. O campo invisível que recebe o teclado mora
  dentro do body, dentro de `<flt-text-editing-host>` — e nascia com
  `user-select: none`. No WebKit do iPhone, um campo assim **ganha o foco e o
  cursor mas não levanta o teclado**; o segundo toque, agora sobre um campo já
  focado, levanta.
- O conserto é uma linha no `web/index.html`, no mesmo bloco que já forçava
  `font-size: 16px` nesse campo (contra o zoom automático do iOS):
  `user-select: text` só para ele. **Medido: `none` → `text`.** O canvas
  continua não selecionável, porque a regra não o alcança.
- **Vale para todos os campos do app de uma vez**, porque é o mesmo elemento
  que o motor usa para qualquer `TextField` — não há campo de fora.
- O que foi descartado com evidência: não há `SelectionArea` no app (o gatilho
  conhecido do mesmo sintoma no rastreador do Flutter), não há `touch-action`
  em CSS nosso, os campos são `TextField` sem nada interceptando o toque, e o
  renderizador é o CanvasKit (o defeito do renderizador HTML não se aplica).

### Contas de robô

A faxina do chat e o servidor dos avisos entram como líderes comuns, com
e-mail e senha — este projeto não usa chave de administrador. O preço era
aparecerem como gente.

- **`UserModel.bot`.** Robô não entra em Membros, nem na contagem "3 líderes ·
  5 membros", nem nas equipes, nem nas escalas, e não recebe aviso (ele não
  usa o app, então não tem inscrição).
- **E não conta na proteção do último líder.** Contava: dava para remover a
  última pessoa de verdade porque o robô "ainda era líder", e o ministério
  ficava com um robô como único líder — ninguém mais aprovaria cadastro.
  `AuthService.adminCount()` agora filtra `bot` **no cliente**, não no
  `where`: `where('bot','!=',true)` NÃO devolve documento sem o campo, e
  deixaria de fora justamente os líderes humanos antigos.
- **Marcar é só do líder**, com confirmação pelo nome, e a regra do banco
  impede alguém se marcar: quem se marcasse robô sairia das escalas e não
  entenderia por que deixou de ser chamado.
- `bot` só é gravado quando é verdade, e **só `true` conta** — valor estranho
  no console não esconde uma pessoa de verdade.
- Os robôs ficam numa seção recolhida "Contas de robô", para o líder poder
  desmarcar.

### Várias funções por pessoa

Era uma função só. No ministério é comum tocar duas — cantar e fazer violão,
baixo e teclado.

- **`UserModel.instruments`, e a PRIMEIRA é a principal.** `instrument` virou
  um getter que devolve a primeira: foi isso que deixou a mudança caber sem
  tocar em dezenas de chamadas, e é a principal que aparece onde só cabe uma
  (chat, selo da escala). Em Membros aparecem todas, porque é lá que o líder
  decide quem pode ser escalado em quê.
- **A lista nunca é vazia.** `instrument` leria o primeiro item de uma lista
  vazia e derrubaria a tela; documento torto no console não pode fazer isso.
- **`instrument` continua gravado sozinho** além da lista: é o que uma versão
  antiga do app lê, e é o que a regra já validava.
- **A função é escolhida POR CULTO.** `ScaleLevita.instrument` já existia;
  agora o diálogo de escalar mostra as funções de quem faz mais de uma, e o
  líder diz "hoje ela canta". Trocar a função **não** apaga a confirmação de
  presença de quem já confirmou.
- **O modo de ver a música segue a função daquele culto**, não a escolha fixa
  do perfil: `SongDetailScreen.funcaoNoCulto`. Nulo (música aberta pelo
  repertório) mantém o comportamento antigo. A pessoa troca na hora pelo botão
  de sempre, e a troca não mexe no perfil.
- **A música do culto agora abre tocando nela.** Antes, para ver a cifra do
  domingo, a pessoa saía do culto, ia em Músicas e procurava pelo nome.

### Editar música

O menu ⋮ só tinha "Colar cifra" e "Tirar do repertório": um nome digitado
errado ficava errado para sempre, ou a música era cadastrada de novo e o
histórico dos cultos se perdia.

- **"Editar música" é do líder E de quem cadastrou.** A regra do banco abre
  uma lista fechada de campos para quem cadastrou
  (`name`, `artist`, `originalKey`, `links`, `observacoes`) — `archived` fica
  de fora, então quem cadastrou não tira nada do repertório, e `lyrics`
  também, porque trocar a letra é o que "Colar cifra" faz, e isso é do líder.
- **O BPM vai para o ARRANJO**, não para a música: é de como esta igreja toca
  (modelo de três camadas). O campo existia no modelo desde o começo e nunca
  tinha onde ser editado.
- **`SongModel.observacoes`** aparece acima da letra, não num menu: é
  combinação que vale no momento de tocar ("entra sem bateria").
- **O link do YouTube vira botão na música e no culto**, para ensaiar antes.
  `SongModel.comVideo` troca só o link de vídeo e deixa o Cifra Club e o
  Spotify onde estão.
- **Link que não abre agora avisa.** `abrirLink` existe por causa de uma falha
  silenciosa: o botão do YouTube chamava `canLaunchUrl` e, no "não", o toque
  não fazia absolutamente nada — nem som, nem aviso. Agora ele TENTA abrir, e
  só avisa se falhar, com o endereço e um "Copiar".

### Colar cifra do Cifra Club

Copiar a página cola o cabeçalho **sem as quebras de linha** que a tela
mostrava. Dois casos reais: `Sou Grato Por Seu AmorGet de: Joshua Coleman` e
`Tom: DAfinação: E A D G B E`.

- **Grudado, o "Tom:" não era reconhecido** — a música ficava com o tom antigo
  (G) e a cifra em outro (D). É o erro mais caro que isto podia dar: o levita
  toca no tom errado no domingo.
- **"Afinação: E A D G B E" é a pior linha para deixar passar**, porque é
  feita de nomes de acorde: ela entrava na cifra como se fosse uma linha de
  acordes de verdade.
- **Um padrão de largura zero não perdoa folga.** A primeira versão do corte
  permitia até seis letras antes do "de:", para pegar o "Get" que o botão do
  site cola no texto — e a expressão passou a casar em toda posição dentro
  dessas seis letras: "Amor" virou `m\no\nr`. O corte agora é exatamente
  antes de um rótulo conhecido.
- **E "de:/por:" não entra no corte por rótulo:** "Dificuldade: Fácil" tem
  "de:" dentro, e a palavra era cortada no meio, com "Fácil" virando o
  artista. O artista é separado à parte, por uma função que sabe ignorar linha
  de rótulo.
- **Toda heurística de cabeçalho vive nas 8 primeiras linhas.** Solta no texto
  inteiro, ela comeria verso ("de: " aparece em letra de música) — e comer um
  verso é pior que deixar um rótulo passar. Sem artista no cabeçalho, a
  primeira linha NÃO é descartada.
- **O tom detectado só troca o tom original com pergunta**, dizendo os dois
  tons: "a cifra está em D, a música está em G". Vazio, preenche direto.
- Título e artista detectados preenchem o cadastro **só em campo vazio**: a
  pessoa está digitando, e sobrescrever é pior que não ajudar.
- Os dois casos reais estão nos testes, com o texto do jeito que chegou.

### Modo Culto ao vivo

Durante o culto, todos na mesma parte da música ao mesmo tempo — cada um no
seu modo. Botão na tela do culto, acima da lista de músicas.

- **O que viaja é POSIÇÃO LÓGICA, nunca pixels:** `{música, âncora}`, e
  âncora é o índice da **linha de letra** (`MapaDaMusica`). É isso que
  permite o tecladista ler a cifra num celular pequeno e a cantora ler só a
  letra em fonte grande, parados no mesmo verso. Sincronizar pixels ou
  "linha 12" poria o tecladista no refrão e a cantora três versos atrás.
- **Os dois modos saem do MESMO texto.** Quando existe cifra, ela é a fonte
  dos dois: quem lê só a letra vê a letra extraída da cifra, não o campo
  `lyrics` da música. Se cada modo lesse um texto diferente, as âncoras não
  corresponderiam e o culto desalinharia **sem nenhum erro aparecer na
  tela**. Por isso `MapaDaMusica.mapear` constrói as duas versões na mesma
  varredura, e o teste confere que toda âncora aponta para a mesma letra nos
  dois — e que os índices nos dois textos são diferentes, senão o teste
  passaria por acidente.
- **O texto da linha viaja junto do índice.** Se um aparelho tiver uma versão
  diferente da música, o índice apontaria para outro verso; a tela avisa em
  vez de desalinhar calada.
- **A cota que aperta é a de LEITURAS, não a de escritas** — e eu errei essa
  conta na primeira versão. Cada mudança de posição é uma leitura cobrada
  para CADA aparelho que escuta. No teto de 2 escritas por segundo, uma hora
  de culto dá 7.200 mudanças: cabe nas 20.000 escritas/dia do Spark, mas com
  12 aparelhos são 86.400 **leituras**, e a cota é 50.000/dia — um culto só
  estouraria tudo. Daí duas travas: posição igual não vira escrita, e **a
  rolagem do condutor só publica quando PARA** (600 ms de espera). As linhas
  do meio do arrasto não interessam a quem segue, só onde o condutor parou.
  O que sobra são algumas centenas de mudanças por culto.
- **O comando não fica preso em quem sumiu.** Celular travado, bateria no
  fim, app fechado no meio do culto: depois de 45 s sem escrita, qualquer
  aprovado assume. A conta está nos dois lados —
  `EstadoAoVivo.silencioMaximo` e a regra do banco, com
  `request.time - duration.value(45,'s')` — porque esconder o botão não
  bastaria e deixar só a regra decidir daria um toque que falha sem
  explicação.
- **A hora é do SERVIDOR, e a regra exige.** Com o relógio do aparelho, um
  celular adiantado deixaria o estado "vivo" para sempre e ninguém mais
  assumiria. `serverTimestamp` chega nulo na primeira notificação local, e o
  modelo trata isso como "agora" — tratar como velho faria dois aparelhos
  assumirem ao mesmo tempo no primeiro instante.
- **Passar o comando NÃO escreve o id da outra pessoa:** solta o comando e
  avisa. Apontar um condutor que talvez não esteja com o app aberto
  travaria o culto por 45 s.
- **Seguir é o padrão; rolar à mão solta.** `UserScrollNotification` com
  direção diferente de `idle` é gesto de pessoa, não a animação do próprio
  app — sem essa distinção, a rolagem automática se soltaria sozinha.
- **Tela acesa:** Screen Wake Lock, que no iPhone funciona em PWA instalado
  **a partir do iOS 18.4** (antes disso o pedido é recusado; era defeito do
  WebKit). O navegador **solta a trava quando a página sai de vista**, então
  `web/tela_acesa.js` pede de novo no `visibilitychange` — sem isso a tela
  apagaria para quem atendeu uma mensagem e voltou. **Medido no Chromium:**
  1 pedido na entrada, 2 depois de voltar à vista, e nenhum depois de soltar
  de propósito. Quando o aparelho recusa, a tela diz para pôr o Bloqueio
  Automático em Nunca, em vez de apagar calada no meio da música.
- **O atraso entre aparelhos, medido:** dois clientes contra o emulador,
  25 amostras — mediana **20 ms**, p90 35 ms, pior caso 97 ms. O emulador
  roda na mesma máquina, então esse é o PISO: no Firestore de verdade soma-se
  a ida e volta até o datacenter.
- **Rolagem automática local** (play/pause e velocidade) funciona sem
  internet, e a velocidade inicial vem do BPM do arranjo: uma linha de letra
  dura mais ou menos quatro tempos. Com condutor ativo, a sincronização tem
  prioridade — assumir o comando desliga a rolagem automática.
- O tema do app NÃO vale aqui: preto de verdade, texto claro e fonte grande,
  porque é tela lida de longe, muitas vezes com refletor em cima.

### Reações, citação e "visto por"

O chat ganhou os quatro gestos que a equipe já sabe de cor do WhatsApp:
segurar para reagir, arrastar para a direita para responder, "@" para chamar
alguém, e os tiques de leitura.

- **As reações são um MAPA na própria mensagem** (`reacoes: {uid: emoji}`),
  não uma subcoleção. Por custo de leitura: o chat já escuta `messages`,
  então as reações chegam de graça junto das bolhas; numa subcoleção, cada
  bolha custaria uma escuta a mais — com 50 mensagens na tela, 50 escutas.
- **Uma reação por pessoa**, porque a chave do mapa é a pessoa. Tocar no
  emoji já marcado tira — o mesmo gesto põe e desfaz.
- **A regra do banco deixa cada um mexer SÓ na própria chave**, por
  `diff().affectedKeys().hasOnly([eu()])`. Sem isso, qualquer aprovado
  reescreveria o mapa inteiro e apagaria a reação dos outros.
- **E o `get('reacoes', {})` nos dois lados da regra não é zelo:** mensagem
  gravada antes desta mudança NÃO TEM o campo, e ler `resource.data.reacoes`
  direto faz a regra dar erro — recusando toda reação em toda mensagem antiga
  do chat. Tem teste só para esse caso.
- **Reagir não deixa mexer em mais nada de carona:** `mudou().hasOnly(...)`
  separa a reação de fixar e do texto, e há teste para as duas tentativas.
- **Emoji fora da lista é descartado na LEITURA também.** A regra recusa, mas
  documento mexido no console não pode desenhar lixo na tela de todo mundo.
- **A ordem das contagens é sempre a da lista oficial**, não por quantidade:
  contagem que muda de lugar a cada reação faz a pessoa tocar no emoji
  errado.

**Visto por** é UM documento por pessoa (`chatLeituras/{uid}`), não um
carimbo por mensagem:

- Marcar cada mensagem como lida por cada pessoa seriam 15 escritas por
  mensagem num ministério de 15 — a cota do Spark acabaria numa tarde de
  conversa. Com um documento por pessoa, abrir o chat custa UMA escrita, e os
  dois tiques saem de comparar horários.
- **A hora é do SERVIDOR, e a regra exige.** Senão bastaria adiantar o
  relógio do celular para ganhar dois tiques azuis em mensagem que ninguém
  leu.
- **O robô não entra na conta.** Com ele dentro, os dois tiques azuis seriam
  impossíveis para sempre, porque robô não abre o chat — e ninguém entenderia
  por quê.
- **O autor não se conta**, e **ministério de uma pessoa só não acende**: dois
  tiques azuis sem ninguém para ver significariam "todo mundo viu" quando não
  houve ninguém.
- **Um tique cinza enquanto as leituras não chegaram.** Nulo vira cinza, nunca
  azul: é mais honesto que dois tiques adivinhados.
- O serviço guarda até onde já marcou, então o chat pode chamar `marcarLido` a
  cada mensagem que chega sem virar uma escrita por mensagem recebida.

**Responder citando** copia um pedaço do texto na mensagem nova
(`respondeA`, `respondeANome`, `respondeATexto`):

- É o contrário da regra da escala, que guarda referência e nunca cópia — e de
  propósito, por dois motivos: a mensagem original **some em 30 dias** (a
  citação ficaria vazia, perdendo o sentido do que foi respondido), e resolver
  por id custaria uma leitura por bolha na tela.
- O arrasto é só para a DIREITA e com velocidade de verdade: arrasto curto é
  quase sempre tentativa de rolar a conversa.

**@menção** guarda a lista de uid, não os nomes (nome se repete e muda):

- **A menção fura o "silenciar até amanhã", mas NÃO o "avisos desligados".**
  O silêncio temporário é "não me acorde por bobagem", não "não me chame" — é
  o caso de "@Ana, você consegue vir às 18h?" na véspera. Já quem desligou os
  avisos fez uma escolha sobre o app todo, e furá-la seria o app decidindo por
  cima da pessoa, que não teria como se proteger a não ser desinstalando.
- Por isso **o leque de envio sai em dois grupos**, com textos diferentes:
  quem foi mencionado recebe "📣 mencionou você: …", e sem isso a pessoa seria
  acordada com o chat silenciado sem saber por quê.
- No envio, só valem as menções cujo "@nome" ainda está escrito no texto:
  escolher na lista e apagar o nome depois não manda aviso a ninguém.
- **Reação NUNCA dispara aviso.** O Worker só é chamado depois de uma mensagem
  ser CRIADA; reagir é um `update`, e nenhum caminho do app chama o aviso ali.

**O que isto custou em leitura:** o chat passou a abrir duas escutas novas
(~15 documentos cada): as leituras e a lista de pessoas — a segunda serve ao
"visto por" e à lista de quem mencionar. São ~30 leituras por sessão, uma vez.

### Minhas próximas músicas

Para chegar à cifra do domingo, a pessoa saía do Início, ia na Escala, abria o
culto, achava a música na lista e tocava nela: quatro telas para a única coisa
que ela abre o app para fazer.

- **O tom é o DAQUELE culto**, não o da música: é o primeiro dado que quem vai
  tocar procura, e muda de culto para culto (`SongsProvider.keyOf`).
- **A função também é a daquele culto**, e é ela que decide se a música abre em
  cifra ou só com a letra — quem canta num domingo e toca baixo no outro
  precisa de coisas diferentes em cada um.
- **Não aparece para quem não está escalado.** Cartão vazio dizendo "nenhuma
  música" ocupa o lugar de algo útil e ensina a passar o olho por cima.
- **O botão do YouTube só aparece quando há link**: botão que não faz nada é
  pior que botão nenhum (a mesma regra do `abrirLink`).
- `ScaleProvider.minhasProximasMusicas` é pura e recebe `agora`, como
  `aindaVale`: é conta de data, e conta de data quebra na virada do dia. A
  janela é a mesma do "próximo culto" — o culto que começou há menos de duas
  horas ainda conta, porque é quem abre o app no meio do culto.

### Escolher as músicas do culto

A lista de seleção era nome e "artista • tom", na ordem em que o banco
devolvia. Montar um culto era lembrar de cabeça o que já tinha sido tocado nas
últimas semanas e quais músicas a equipe já sabe.

- **"Tocada em 12/10" — e NUNCA "nunca tocada".** A resposta sai dos cultos que
  o app tem em memória, e a janela de leitura vai só até 60 dias atrás: a
  ausência de registro significa "não nesse período". Uma música do ano passado
  apareceria como nunca tocada, e o líder montaria o culto com base nisso. O
  texto é "não tocada nos últimos 2 meses", derivado da própria janela
  (`textoDaUltimaVez`).
- **Culto futuro e culto cancelado não contam** em `ultimaVezTocada`: a
  pergunta é o que já foi tocado, não o que está marcado, e ninguém tocou num
  culto cancelado.
- **A ordem padrão é "menos tocadas primeiro"**, porque é a pergunta que o
  líder faz: "o que a gente não canta há um tempo?". Repetir o mesmo
  repertório é o jeito mais comum de um ministério cansar a igreja sem
  perceber. Música sem registro vem primeiro — é a nova e a esquecida. Duas sem
  registro saem por nome, para a lista não dançar a cada abertura.
- **A busca ignora acento** (`core/utils/texto.dart`): quem procura "coracao"
  quer achar "Coração", e ninguém digita acento no celular com pressa. Vale
  para nome e artista.
- **"Tem cifra" custa uma leitura por música**, porque a cifra mora no arranjo
  — e é isso que impede o app de baixar o repertório inteiro de cifras só para
  abrir a lista. Então a pergunta é feita **uma vez por sessão e só quando o
  líder abre este diálogo** (`SongsProvider.conferirCifras`): ~40 leituras de
  50 mil por dia, numa tela que se abre de propósito.
  **Um campo `temCifra` na música foi descartado** por causa dos dados que já
  existem: música com cifra cadastrada antes do campo apareceria como "sem
  cifra", que é o contrário do que o ícone promete. E enquanto a resposta não
  chega, **nenhum ícone é desenhado** — ausência não pode parecer "sem cifra".
- **A ordem do culto é preservada ao salvar**: as músicas novas entram no fim,
  em vez de o repertório ser reordenado por causa de uma inclusão.

### Levar um recado do chat para o culto

O combinado nascia no chat — "domingo entra sem bateria", "a Ana leva o cabo" —
e morria lá: em 30 dias a mensagem some, e quem abre o culto no domingo não vê
nada. Copiar à mão era o que o líder fazia, quando lembrava.

- **Segurar a bolha → "Levar para o culto"**, só para o líder: chat é conversa,
  observação do culto é o combinado oficial que todo mundo escalado lê.
- **O culto padrão é o próximo**, mas a escolha existe: combinação de ensaio e
  de culto grande vêm na mesma conversa.
- **A assinatura vai no TEXTO**, não em campos (`— Márcio, 16/11: …`).
  Observação é combinação lida por gente; um histórico estruturado aqui seria
  uma coleção nova para resolver o que uma linha resolve.
- **Vai por transação**, e aqui isso importa mais que de costume: o valor novo
  DEPENDE do que já está gravado. Ler na tela, juntar e gravar apagaria a
  observação que outro líder escreveu nesse meio tempo — o caso de dois líderes
  montando o mesmo culto.
- **O teto de 5000 da regra existe também no app**
  (`ScaleModel.limiteDasObservacoes`), para a tela avisar ANTES de tentar:
  estourar no banco devolveria erro de permissão, que não explica nada.
- **As observações saíram do fim da tela para o TOPO**, visíveis a todos os
  escalados — um combinado que ninguém lê é um combinado que não existe. Para
  quem não é líder o campo de edição **desapareceu**: ele aparecia como uma
  caixa de texto que não aceitava texto, o que parece defeito.
- **No Modo Culto ao vivo elas entram recolhidas**, numa linha que se abre no
  toque: ali a música é que não pode perder espaço.

### Um cartão só, e as palavras certas

- **Um cartão de culto no Início.** Eram dois, com a mesma data e o mesmo
  culto: "Meu próximo compromisso" no topo e "Próximo culto" no fim, com a tela
  inteira entre eles. Quem estava escalado lia a mesma informação duas vezes;
  quem não estava via um cartão vermelho sumir e outro aparecer sem entender a
  diferença. Agora é um: escalado, ele fala com a pessoa
  (**"Você toca domingo, 19h, no baixo"**) e traz o botão de confirmar; não
  escalado, mostra o próximo culto do ministério. O toque abre o culto nos dois
  casos.
- **`UserInstrumentExtension.naFrase`** existe porque "Você toca domingo no
  Cantor(a)" é o que sai ao colar o rótulo numa frase — e quem canta não
  "toca": a frase inteira muda.
- **"Arquivadas" virou "Fora do repertório"**, e a ação, "Tirar do repertório"
  / "Devolver ao repertório". "Arquivar" é palavra de escritório.
- **O menu diz o que tem volta:** "Cancelar culto (dá para reativar)", "Tirar
  do repertório (dá para devolver)", e as duas confirmações explicam o que
  NÃO se perde. Antes as duas opções vermelhas pareciam irreversíveis.
- **As duas "observações" ganharam nomes diferentes:** "Observações do culto"
  (daquele domingo) e "Anotações da música" (da música em qualquer culto). A
  terceira, "Minha anotação", já era pessoal e continua.
- **"Offline" saiu da tela.** Virou "Salvar no celular" / "Tirar do celular" /
  "No celular", e "Sem conexão. Modo offline ativo." virou "Sem internet. O app
  está mostrando o que já baixou." Para quem "só sabe usar WhatsApp", offline é
  palavra de técnico — e é justamente o recurso que serve ao culto sem
  internet.
- **Maiúscula no meio da frase saiu** de 19 textos ("Próximo Culto", "Confirmar
  Presença", "Tons Salvos"…): em português isso se lê como tradução mal feita.
  "Modo Culto" ficou, porque é nome de recurso.
- **"Adicionar Músicas" virou "Músicas do culto"** e **"Definir Levitas" virou
  "Quem toca neste culto"**: dizem o que a tela faz, em vez de nomear a
  operação.

### Quem já confirmou

"Levitas (7)" dizia quantas pessoas estavam escaladas. A pergunta que o líder
faz no sábado à noite é outra: **quantas já disseram que vêm** — e ele
respondia isso abrindo o culto e contando os nomes verdes na mão.

- **A frase mora no modelo** (`ScaleModel.textoDaConfirmacao`), não na tela,
  porque são os casos de borda que a fazem soar como gente: "ninguém
  confirmou ainda" em vez de "0 de 7 confirmaram", "todos confirmaram" para o
  líder ler de longe, e "Confirmado" quando a escala tem uma pessoa só — "1 de
  1 confirmaram" estaria errado no português e na conta.
- **Culto sem ninguém escalado NÃO conta como pronto.** `todosConfirmaram` é
  falso com a lista vazia: zero de zero não é escala pronta, é escala vazia, e
  o verde ali diria ao líder que não há nada a fazer.
- **Quem falta sai pelo NOME** (`faltamConfirmar`), cortado em três mais "e
  mais N": os chips já dizem quem confirmou, mas ler ausência numa lista é
  trabalho — o olho conta os que têm tique. A frase diz de quem o líder
  precisa cobrar, que é a única coisa que ele pode fazer a respeito.
- **Na lista de cultos o número fica verde quando está tudo confirmado.**
  Antes era sempre vermelho, inclusive no culto pronto: cor que não muda não
  informa nada.

**O nome vem do cadastro, não da cópia dentro do culto.** `userName` é cópia,
e o gerador da agenda fixa grava vazio. Resolver por id é a mesma razão por
que a escala guarda referência de música e nunca cópia: quem corrige o próprio
nome corrige em todos os cultos de uma vez.

- **Uma escuta só da lista de pessoas, no app todo** (`AuthProvider.pessoas` /
  `nomes`, iniciada em `main_screen`). O chat tinha a dele, e a Escala e o
  Início passaram a precisar da mesma lista: três escutas sobre os mesmos ~15
  documentos custariam o triplo de leitura pela mesma informação. O chat
  passou a ler do provider, então o total de escutas **caiu**.
- Sem cadastro nem cópia, o nome vira "Alguém" — alguém que saiu e cujo
  documento ficou. Linha em branco o líder leria como "não tem ninguém aqui".

**Avisar o líder quando alguém confirma ou desmarca:**

- **Vai só para os LÍDERES**, e não para o ministério: é informação de quem
  remonta a escala. Avisar 14 pessoas de algo que nenhuma delas pode resolver
  é como se ensina a ignorar notificação. O líder que confirma a própria
  presença não se avisa (`excluirId`).
- **Quem decide quem é "o líder do culto" é a função, não o campo
  `createdBy`.** Desde que o Worker gera os cultos, `createdBy` é o robô na
  maioria deles — avisar "o criador" não avisaria ninguém.
- **O texto sai do DOCUMENTO, não do corpo do pedido.** O app manda só o id
  do culto; o Worker lê se a pessoa está confirmada ou não. Assim o aviso não
  pode dizer o contrário do que está gravado.
- **`confirmadoEm` é o carimbo de "acabou de confirmar"**, exigido pela regra
  como `request.time`, e o Worker só avisa se for de menos de 2 minutos — a
  mesma trava do chat e da escala. Sem ela, o id de um culto antigo, que todo
  aprovado lê, reavisaria o líder a qualquer momento.
- **O carimbo entra na MESMA escrita da confirmação**
  (`mudou().hasOnly(['levitas','confirmadoEm'])`). Uma segunda escrita só para
  carimbar dobraria a cota e deixaria o carimbo sem a confirmação quando a
  segunda falhasse.
- **Confirmar e desmarcar têm etiquetas diferentes.** Confirmar substitui o
  aviso anterior do mesmo culto (`levita-confirma-<culto>`): o líder só precisa
  saber que mexeu, e a contagem está no app. **Desmarcar é por pessoa**
  (`levita-desmarca-<culto>-<uid>`) e nunca é substituído — é um instrumento
  faltando no domingo, e perder esse nome seria perder a única notícia que
  pede ação.
- Liga e desliga à parte em Perfil, e o interruptor **só aparece para líder**,
  como o de "novo pedido de entrada".

### O Worker gera os cultos

A geração da agenda fixa rodava **só quando um líder abria o app**. A
fragilidade estava escrita aqui como "conhecida": férias, viagem, um mês
corrido, e os cultos paravam de ser criados — a escala secava sem ninguém
perceber. Agora roda também no Worker, todo dia, pelo mesmo job da véspera.

- **A mesma conta existe em dois lugares**, em duas linguagens. Isso é um
  risco de verdade: se uma calcular o id do culto de um jeito e a outra de
  outro, nascem **duplicatas** — dois domingos das 8h na lista, cada um com
  metade da equipe. Por isso existe **`test/dados/agenda_contrato.json`**: os
  mesmos dados de entrada, os mesmos ids esperados, e o formato do documento,
  conferidos pelos **dois lados** (`test/agenda_fixa_test.dart` e
  `worker/teste/agenda.test.mjs`). Mexer num gerador sem mexer no outro faz o
  teste do outro falhar.
- **Gravar um culto que já existe seria o pior estrago possível**: apagaria a
  escalação e as confirmações de presença de todo mundo, sem erro nenhum. Daí
  `criarDocSeNaoExiste`, com a pré-condição `currentDocument.exists=false`.
  **Medido no emulador:** a segunda tentativa volta **409 ALREADY_EXISTS** e o
  documento fica intacto, com a confirmação preservada. 409 é tratado como "já
  existe, siga adiante", não como erro — num ministério com a agenda em dia
  quase todo culto já existe, e desistir no primeiro impediria a criação dos
  que faltam.
- **O fuso é de Brasília, fixo, e a conta é de CALENDÁRIO.** O app faz a conta
  no relógio do aparelho; o Worker acorda em qualquer datacenter do mundo, e
  em UTC "quarta às 19h30" cairia na quinta de madrugada, com outro id. Então
  tudo em `worker/src/agenda.js` é relógio de parede de Brasília, e somar uma
  semana é somar 7 dias no calendário — nunca 7×24 horas a um instante, que é
  onde horário de verão quebraria (o Brasil não tem desde 2019, mas a conta
  não depende disso). O `-03:00` fica num lugar só.
- **`agoraEmBrasilia` normaliza a hora com `% 24`:** `hour12: false` devolve
  "24" para a meia-noite em parte dos ambientes, e 24 no id daria
  `2026-11-18_2400` — um culto que não existe.
- **Não há trava de uma vez por dia**, ao contrário do lembrete da véspera, e
  de propósito: criar é seguro de repetir (id + pré-condição), e mandar aviso
  não é. Uma trava aqui só esconderia que uma tentativa falhou.
- **Os cultos que já existem saem de uma CONSULTA por data**, não da coleção
  inteira: um ano são ~260 cultos, e listar todos custaria 260 leituras por
  dia para olhar as próximas 4 semanas. Culto cancelado conta como existente —
  ele não volta a ser criado, que é o motivo de cancelar ser um campo.
- **A geração vem ANTES do lembrete no job**, para um culto criado agora para
  amanhã ainda receber o aviso no mesmo passo. E com `continue-on-error`: uma
  falha na criação não pode silenciar o lembrete de quem já está escalado.
- **`paraFirestore` ganhou lista e mapa.** Antes, qualquer coisa que não fosse
  escalar virava `String(v)`: `levitas` seria gravado como o texto
  "[object Object]", e o app leria uma lista vazia — culto sem ninguém
  escalado, sem erro nenhum.
- **Há um teste de regra com o documento exato que o Worker grava.** Sem ele,
  a falha seria a mais silenciosa possível: o Worker recebe 403, escreve no
  log dele, ninguém olha log de Worker, e a escala para de ser criada — que é
  justamente o problema que isto veio resolver.
- **Nada no app mudou** nesta entrega: `lib/` e `web/` ficaram intocados.

### Aviso de novo pedido de entrada

Quem se cadastra fica `pendente` e **não vê nada do app** até um líder
aprovar. Antes, o líder só descobria o pedido abrindo a tela Membros por
conta própria — então o silêncio parecia defeito para quem estava esperando.

- **É a ÚNICA rota do Worker que atende quem NÃO está aprovado**, e tem de
  ser: quem acabou de se cadastrar está `pendente`, e é justamente desse
  cadastro que o líder precisa saber. Por isso ela vem antes do `quemPediu`,
  com conferência própria: token válido deste projeto, e o cadastro tem de
  existir e estar `pendente`. Um aprovado que chamasse a rota mandaria ao
  líder um aviso sem pedido nenhum por trás.
- **A trava não é uma janela de tempo, é uma marca:** `pedidosAvisados/{uid}`,
  um documento por cadastro, e cada cadastro avisa **uma vez na vida**. As
  outras rotas conferem "foi escrito agora", mas aqui o único carimbo
  disponível seria o `createdAt` do cadastro, que vem do **relógio do
  aparelho** — um celular adiantado valeria por dias, um atrasado nunca
  avisaria.
- **A marca é lida ANTES das duas leituras de coleção**, e é gravada mesmo
  quando ninguém recebeu. É trava de custo: sem ela, uma conta pendente em
  laço faria ~30 leituras por chamada e queimaria a cota do dia. Com ela, a
  segunda chamada custa uma leitura e volta. O pedido não se perde por isso,
  porque o selo na tela Membros não depende de notificação.
- **Só os líderes recebem** — são eles que aprovam —, e robô fora.
  `quemAvisaDoPedido` é função pura e testada, porque é a parte que erra em
  silêncio: mandar para o ministério inteiro (todos leriam "alguém quer
  entrar" sem poder fazer nada) e mandar para ninguém dão a mesma resposta no
  fim.
- **Etiqueta por pessoa** (`levita-pedido-<uid>`): dois cadastros no mesmo dia
  são dois avisos na tela. Com etiqueta fixa, o segundo apagaria o primeiro e
  um nome se perderia. Para isso o `sw.js` passou a aceitar uma `etiqueta`
  vinda do Worker.
- **Tocar no aviso abre a tela Membros**, onde se aprova — pelos mesmos dois
  caminhos do chat e do culto, porque o app não tem endereço por tela. O
  `main_screen` confere `isAdmin` de novo antes de abrir: quem foi rebaixado
  entre o envio e o toque veria uma tela sem botão nenhum.
- **Liga e desliga à parte, e só o líder vê o interruptor** em Perfil: um
  liga-desliga de algo que nunca chega é só confusão para quem não é líder.
  Chave ausente é ligada, como nos outros tipos.
- **O pedido de entrada respeita o "silenciar até amanhã"**, ao contrário da
  menção no chat: não é urgente, e o selo na tela não vai a lugar nenhum.

### Pedir o e-mail na hora certa

O e-mail de recuperação só funciona se for cadastrado **antes** de a senha ser
esquecida, e exige a senha atual. Então o app pede nos dois momentos em que a
pessoa ainda a tem na cabeça:

- **Na tela de espera da aprovação.** É o melhor momento do app inteiro: a
  pessoa acabou de digitar a senha e está parada, sem nada para fazer.
  Funciona mesmo estando `pendente`, porque trocar o endereço é operação do
  Firebase Authentication e não escreve no banco — o sim/não no cadastro só é
  gravado depois da aprovação, na conferência da abertura (as regras não
  deixam quem está pendente escrever nada).
- **No Início, depois de aprovado**, num cartão que sai da tela sozinho
  quando o e-mail existe. Fica ali, e não só em Perfil, porque ninguém abre o
  Perfil por conta própria. E **não tem "agora não"**, pelo mesmo motivo do
  cartão de instalar — só que aqui o preço de dispensar seria perder o acesso
  à própria conta.
- Os dois leem `AuthProvider.emailDeRecuperacao`, que vem do Firebase
  Authentication, não do campo no banco: é a verdade do momento, e vale para
  quem está pendente. Efeito colateral conhecido: quem confirma o link com o
  app aberto só vê o cartão sair na próxima abertura.

### Avisos da escala

"Você foi escalado" quando o líder salva a escala, e o lembrete da véspera com
as músicas — pedindo a confirmação de quem ainda não confirmou. Mesmo Worker,
mesma cifra, gatilhos diferentes.

- **Quem decide quem é "recém-escalado" é o APP**, que sabe quem estava na
  lista antes de salvar (`quemEntrouNaEscala`, função pura e testada). O
  Worker confere que esses ids estão de fato no culto — então uma lista
  inventada não avisa ninguém que não foi escalado de verdade.
- **Trocar a função de quem já estava NÃO avisa de novo.** Era o caso mais
  provável de aviso repetido: o líder abre o diálogo, muda o instrumento de
  alguém e salva. Avisar quem já estava é o pior tipo de notificação — a que
  não traz novidade e ensina a pessoa a ignorar as próximas.
- **`levitasEm` é o carimbo de "a escalação mudou agora"**, e o Worker exige
  que seja de menos de 2 minutos — a mesma trava do chat. Sem ela, o id de um
  culto antigo, que todo aprovado lê, reavisaria o ministério a qualquer
  momento. **A regra do banco exige que o carimbo seja `request.time`**: com a
  hora do aparelho, um líder com o relógio adiantado faria o carimbo valer por
  horas.
- **O lembrete da véspera é um job do GitHub Actions que só acorda o Worker.**
  Ele não manda notificação: a chave privada do VAPID fica num lugar só. E
  **não há segredo novo** — o job entra com a conta do robô da faxina e manda
  o ID token, e o endereço do Worker sai de `avisos_config.dart`, que está no
  repositório. Segredo compartilhado entre GitHub e Cloudflare seria uma coisa
  a mais para vazar, girar e esquecer.
- **Trava de uma vez por dia** (`avisosDaVespera/{yyyy-mm-dd}`): o job pode
  rodar duas vezes — nova tentativa, disparo à mão — e ninguém merece dois
  lembretes do mesmo culto.
- **A hora do culto sai no fuso de Brasília, fixo**, nunca do relógio do
  Worker: ele acorda em qualquer datacenter do mundo, e um culto de domingo
  19h apareceria como sábado 22h para metade do ministério. Testado na virada
  do dia (23h em Brasília é 02h do dia seguinte em UTC).
- **O lembrete lê as músicas uma vez por música**, não por pessoa: com 5
  músicas e 8 escalados, ler por pessoa seriam 40 leituras em vez de 5.
- **Os cultos de amanhã saem de uma CONSULTA por data** (`runQuery` no REST),
  não da coleção inteira: um ano são ~260 cultos, e listar todos custaria 260
  leituras por dia para achar um ou dois.
- **A notificação de culto não se junta com a do chat.** Etiqueta própria por
  culto: "você foi escalado" não é "mais uma mensagem", e somá-los na mesma
  contagem esconderia justamente o que importa. O lembrete substitui o "foi
  escalado" do mesmo culto em vez de empilhar dois. **Medido no Chromium:**
  duas notificações convivem na tela, e a contagem do chat continua certa.
- **Tocar no aviso abre O CULTO**, não o Início: um aviso que pede ação e
  larga a pessoa na tela errada é pior que nenhum aviso. Pelos mesmos dois
  caminhos do chat (app aberto → recado para a página; fechado →
  `?abrir=culto&culto=<id>`), porque o app não tem endereço por tela. Culto
  fora da janela de leitura de 90 dias não está na memória: aí o app para na
  aba da Escala, que é o lugar certo para procurar.
- **Cada tipo liga e desliga à parte**, em Perfil: chat, escalado e véspera.
  São incômodos diferentes — mensagem chega a toda hora, "você foi escalado"
  chega raro e importa. **CHAVE AUSENTE É LIGADA**, nos dois lados (app e
  Worker): todo aparelho inscrito antes desta mudança não tem o campo, e se a
  falta valesse "desligado" o ministério pararia de receber aviso de uma hora
  para outra sem ninguém ter mexido em nada.
- O liga-desliga geral continua acima dos tipos, e **a menção continua
  furando só o silêncio temporário** (ver "Reações, citação e visto por").

### Quando a tela diz "vazio"

Lista vazia e lista que não carregou são coisas diferentes, e a pessoa lê as
duas como defeito do app. O repertório vazio agora diz qual dos quatro casos
é — busca sem resultado, nenhuma favorita, nada salvo offline, ou repertório
realmente vazio — e o que fazer. **Vale para toda lista nova:** erro mostra o
motivo com "tentar de novo"; vazio diz por que está vazio.

Foi removido também um `loadSongs()` que ninguém chamava e que, no `catch`,
trocava a falha pela lista de músicas guardadas no aparelho. Depois de
reinstalar o app essa lista é vazia, então uma falha de leitura teria virado
"nenhuma música", sem erro nenhum na tela.

### Menos é mais: cada tela responde UMA pergunta

A rodada de 19/11/2026. O app tinha crescido por acréscimo — cada entrega
punha mais um cartão no Início e mais uma linha no Perfil —, e o resultado
era uma tela principal com nove cartões e um Perfil com treze linhas mais
duas listas compridas no fim. Para quem "só sabe usar WhatsApp", tela cheia é
tela que não se lê.

**A régua:** cada tela responde uma pergunta. O que não ajuda a responder sai
ou desce um nível. **Nada foi removido** — mudou de lugar.

- **Início: "o que eu preciso fazer agora?"** Um cartão de culto (que já
  tinha virado um na entrega anterior), as minhas próximas músicas, e
  pendências DE VERDADE: mensagem nova no chat, culto sem ninguém escalado,
  pedido de entrada esperando. Saíram os atalhos que repetiam a barra de
  baixo — "Hino pelo número" e o versículo do dia foram para dentro de
  Músicas e da Bíblia. **Quando não há nada pendente, uma linha amigável**,
  não um cartão vazio.
  As três contas de pendência são funções puras (`widgets/home/pendencias.dart`)
  e o que os testes guardam é principalmente o que NÃO deve aparecer: minha
  própria mensagem não conta como não lida, **"nunca abriu o chat neste
  aparelho" é ZERO e não "tudo"** (estrear o app com "47 mensagens novas" é
  parede, não notícia), culto cancelado e culto passado não são pendência, e
  robô pendente não manda o líder procurar uma pessoa que não existe.
- **Músicas: "onde está a música que eu preciso?"** Virou a biblioteca do
  ministério, com um seletor no topo: **Repertório · Hinários · Bíblia**. As
  três telas já existiam; o que mudou é que a Bíblia e o teclado de hinos
  deixaram de depender de um atalho no Início ou de uma linha no Perfil para
  serem encontrados. As duas são embutidas por um parâmetro `embutida`, não
  copiadas — duas telas parecidas é o jeito de uma ficar para trás.
- **Perfil: "quem eu sou aqui, e como mexo nos meus avisos?"** Treze linhas
  viraram quatro (Avisos · Conta · Modo escuro · Ajuda) mais, só para o
  líder, **Painel do líder**. Os três contadores do topo — Favoritas, Tons
  salvos, No celular — **viraram atalhos tocáveis**: eram números decorativos
  acima de duas listas que moravam no fim da tela, onde ninguém rolava.
  Favoritas e No celular levam aos filtros que já existem na aba Músicas;
  Tons salvos abre a lista que estava no fim.
- **"Saúde do sistema" saiu do Perfil.** O cartão com as cinco linhas foi
  para o Painel do líder, e no Perfil ficou só uma tarja — **e só quando algo
  está amarelo ou vermelho**. Cinco linhas de diagnóstico com tudo verde é o
  jeito de a pessoa aprender a passar o olho por cima.

**Decisões que tomei sozinho nesta rodada** (ficam registradas porque a
rodada foi autônoma):

- **Modo escuro é um interruptor na lista, não uma tela "Aparência".** Para
  quem só usa WhatsApp, um interruptor que se vê e se vira num toque ganha de
  uma tela que esconde um interruptor.
- **O versículo do dia foi para a Bíblia** e as sugestões do dia para o
  Repertório, em vez de desaparecerem do Início para o nada.
- **A busca das listas de gente só aparece acima de oito pessoas.** Campo de
  texto sobre seis nomes é um campo a mais na tela.
- **Durante uma busca, as contagens continuam sendo as do ministério.** "3
  líderes · 5 membros" é o tamanho da equipe, não o tamanho da busca.

### O campo que faltava: editar a letra e a cifra

**Era um defeito, não uma falta de recurso.** "Editar música" abria nome,
artista, tom, links e observações — e não a letra. Quem colou a cifra errada,
ou colou do Cifra Club com o cabeçalho grudado, não tinha como consertar: o
único caminho era "Colar cifra" substituindo tudo, de novo, do começo.

- **Um editor só, alcançado de três lugares** (cadastrar, editar, e a tela da
  música), e **um caminho de gravação só** (`_gravarCifra`). Três telas
  parecidas é o jeito de uma ficar para trás quando a regra muda.
- **Fonte monoespaçada e nada de correção automática**
  (`autocorrect: false`, `enableSuggestions: false`,
  `textCapitalization: none`). Numa cifra, o alinhamento É a informação: o
  acorde fica em cima da sílaba. O teclado do celular, "ajudando", trocava
  `Am` por `AM` e comia espaço.
- **`null` ≠ texto vazio** em `EdicaoDeMusica`: `null` é "não mexi na cifra",
  vazio seria "apague a cifra". Confundir os dois apagaria a cifra de toda
  música editada para corrigir um nome.
- **"Pré-visualizar" transpõe de verdade**, mas não grava nada: é para
  conferir se a cifra está no tom que se pensa, que é o erro mais caro do
  "Colar cifra" (ver "Colar cifra do Cifra Club").
- **Rascunho no aparelho, oferecido e nunca aplicado sozinho.** O editor
  guarda o texto a cada segundo em `LocalStorageService`, e na volta mostra
  uma faixa com "Recuperar" e "Descartar". Substituir o texto sozinho seria
  trocar a cifra certa por um rascunho velho sem pedir licença. O rascunho é
  esquecido quando a gravação dá certo — não quando a tela fecha, porque
  fechar a tela é justamente o caso em que ele serve.
- **As partes são detectadas, não digitadas.** `MapaDaMusica` já achava
  `[Refrão]` e tablatura para o Modo ao vivo; o editor mostra o que ele achou
  ("cifra com 12 linhas de acordes · 4 partes"), e a tela da música ganhou
  **"Ocultar tablaturas"** no menu ⋯ — quem canta não lê `e|---3---`, e são
  seis linhas de ruído entre dois versos. A escolha fica no APARELHO, e
  ausência vale como "mostrar".
- **Dados existentes abrem certo:** o formato não mudou. A cifra continua no
  arranjo, a letra continua na música, e o editor lê a cifra quando existe e
  a letra quando não — que é a mesma regra que o Modo ao vivo já usava.

### A tela da música tinha oito botões no topo

Transpor para cima, transpor para baixo, salvar o tom, voltar ao original,
"só letra", "com cifra", favoritar, salvar no celular, o menu ⋯ — tudo na
mesma faixa, acima da música, em telas de 375 px.

- **Sobrou o tom, e nada mais:** `Tom G` com um `−` e um `+` de 44 px, o
  coração e o ⋯. Tudo o que saiu está no ⋯, que é o gesto que esta equipe já
  conhece do WhatsApp.
- **O tom se salva sozinho**, 700 ms depois do último toque. "Salvar" e
  "Reset" eram dois botões para uma coisa que o app podia simplesmente
  lembrar — e quem não tocava em "Salvar" voltava à música no domingo e
  achava o tom errado. "Voltar ao tom original" ficou no ⋯, onde se procura
  uma volta atrás.
- **"Eu canto" e "Eu toco" substituíram "só letra / com cifra".** São as
  palavras da pessoa, não as do app: quem canta quer a letra grande, quem
  toca quer os acordes no seu tom.

### O que só apareceu rodando o app a 375 px

Não dá para conferir tela lendo código. Esta rodada rodou o app de verdade
num navegador de 375×812, com o banco do tamanho do ministério semeado num
emulador (16 pessoas, 42 músicas, 65 cultos, 8 recados), e fotografou 24
telas nos dois temas. **Cinco defeitos apareceram só aí**, e nenhum deles
estava no caminho de nenhum teste:

- **O título "Músicas" saía cortado ao meio.** A altura da barra morava em
  dois lugares que discordavam — `preferredSize` fixo em 120 e o cálculo do
  recuo em 168. Conteúdo maior que o espaço declarado faz o Flutter desenhar
  **por cima** do título. Agora a altura é somada num lugar só.
- **110 px de vazio no meio da Bíblia**, entre "Antigo Testamento" e Gênesis.
  A regra que ninguém vê lendo o código: **uma lista rolável sem `padding`
  herda o recuo do MediaQuery**, e dentro da aba Músicas esse recuo é a barra
  inteira (56 + 54 = exatamente os 110 medidos). `padding: EdgeInsets.zero`
  resolve. Vale para toda lista rolável aninhada.
- **"Original" quebrava em duas linhas** entre o − e o + ("Origina / l"), por
  cima do −: 54 px não cabiam.
- **O Início abria com dois convites** (instalar o app, cadastrar e-mail) e
  empurrava o cartão do culto para fora do primeiro olhar.
- **As pastilhas de quem não confirmou eram brancas fixas** e, no tema
  escuro, viravam retalhos claros no meio do cartão.

E uma classe inteira de defeito que a foto revelou: **texto do app apontando
para tela que mudou de lugar.** A tarja de Membros dizia "em Perfil →
Recuperar a senha", caminho que deixou de existir. Eram dez frases em seis
arquivos. Junto veio uma que estava errada desde a aprovação do líder: a tela
de cadastro prometia "Você entra como Levita" quando todo cadastro nasce
**pendente** — quem lesse aquilo e caísse na tela de espera acharia o app
quebrado.

**Como medir isto de novo:** o app aponta para o emulador (uma linha em
`main()`, só na árvore de teste), um servidor estático serve `build/web`, e o
Playwright liga a **semântica do Flutter** (o botão invisível "Enable
accessibility"), que transforma cada widget num elemento com rótulo. Duas
coisas custaram tempo e ficam registradas:

- **O mouse do Playwright derruba a página** com a semântica ligada: o filtro
  de cliques do motor se perde com ponteiro sintético vindo de fora
  ("Cannot read properties of null").
- **`elemento.click()` move um `ElevatedButton`, mas NÃO move um `InkWell`.**
  O seletor "Repertório · Hinários · Bíblia" não trocava de seção e o roteiro
  fotografava a mesma tela três vezes. O que move um InkWell é a sequência
  `pointerdown` + `pointerup` + `click` disparada **no próprio elemento**.

**Medido também, porque é promessa de tela que falha calada:** o tom se salva
sozinho. Tocar no + leva "Tom G" a "Tom G#/Ab"; saindo da música e abrindo de
novo, continua "Tom G#/Ab". O − e o + são 44×44.

### A ordem dos hinos e dos hinários

Rodada de 19/11/2026, pequena. A lista de hinos saía sempre em ordem de
número, e os hinários apareciam na ordem em que eu os acrescentei ao código —
uma igreja que canta do Cantor Cristão tocava na pastilha certa toda vez que
abria a tela, sempre com a igreja esperando.

**Ordenar os hinos**, num botão discreto ao lado da busca: pelo número
(padrão), pelo nome, mais tocados no ministério, meus favoritos primeiro.

- **A busca continua valendo em qualquer ordem**, porque filtrar e ordenar
  são funções separadas: `hinosFiltrados` acha, `hinosOrdenados` põe em
  ordem.
- **O NÚMERO É SEMPRE O DESEMPATE.** Em "mais tocados", dois hinos com a
  mesma contagem — e o caso comum é zero — sairiam em ordem indefinida, e a
  lista dançaria a cada abertura. É a mesma regra de "Escolher as músicas do
  culto", pelo mesmo motivo: lista que muda de lugar faz a pessoa tocar na
  linha errada.
- **"Pelo nome" ordena pelo NOME, não pelo título.** O título gravado é
  "HC 15 · Sou Grato" — a sigla vai nele de propósito, para o hino se
  reconhecer na escala e no chat. Mas ordenar o título inteiro ordena por
  "hc 1", "hc 120", "hc 15", ou seja, pelo número de novo. **Visto na tela:**
  "HC 1 · Chuvas de Graça" vinha antes de "HC 120 · Amigo de Pecadores", e a
  opção parecia um botão que não faz nada. `nomeSemHinario` corta só o que
  tem a cara do prefixo gerado; hino cadastrado à mão com o nome puro passa
  intacto.
- **"Mais tocados" diz de quando.** A contagem sai dos cultos que o app já
  tem em memória, e a janela de leitura são 60 dias — então a tela escreve
  "Mais tocados nos últimos 2 meses, primeiro", e nunca promete o histórico
  inteiro. Mesma honestidade de "não tocada nos últimos 2 meses" no
  repertório.
- **Sem culto registrado, a opção avisa e cai para o número.** Escolher "mais
  tocados" num ministério sem histórico devolveria uma lista por número sem
  explicação nenhuma — a pessoa acharia que o botão não funcionou.
- `ScaleProvider.vezesTocadas` segue as regras de `ultimaVezTocada`: culto
  cancelado não conta, culto futuro não conta. E a mesma música repetida
  dentro de um culto conta **uma vez**: foi um culto.

**Arrastar os hinários.** As duas pastilhas lado a lado viraram uma lista de
pé, porque lado a lado não existe "arrastar para cima". O preço são uns 50 px
antes do teclado; o que se ganha é a igreja do Cantor Cristão deixá-lo em
primeiro **e o app abrir nele**.

- **A alça fica visível, e o mesmo movimento está no menu de cada linha**
  ("Mover para cima/baixo"). Arrastar exige firmeza na mão, e metade deste
  ministério tem mais de sessenta anos. A opção que não tem para onde ir
  **some**, em vez de aparecer e não fazer nada.
- **`hinariosNaOrdem` é pura porque a lista gravada envelhece em silêncio.**
  Um hinário NOVO não está nela — e, se a tela mostrasse só o que está
  gravado, ele simplesmente não apareceria para quem já arrastou os cartões
  uma vez, sem que ninguém ligasse uma coisa à outra. Então o que não está na
  lista entra no fim, e id que não existe mais é descartado.
- **O primeiro da lista é o que abre, e a linha diz isso** ("abre aqui").
  Duas fontes para a mesma decisão seria arrastar o Cantor para cima e o app
  continuar abrindo na Harpa. O último hinário usado só vale **enquanto
  ninguém arrastou nada** — é o que preserva o costume de quem já usa o app.
- **Reordenar NÃO troca de hinário:** quem arrasta está organizando a lista,
  não escolhendo o que ler agora.
- `movido` prende o índice nas bordas: subir o primeiro devolve a mesma
  lista, em vez de dar a volta e mandá-lo para o fim.

**As duas escolhas ficam no APARELHO** (`LocalStorageService`), como o
marcador da Bíblia e os últimos hinos abertos: é preferência de quem está com
o celular na mão, não há o que sincronizar, e no Firestore custaria leitura
por abertura para guardar duas palavras. A ordem dos hinos vale para todos os
hinários — quem gosta de ver por nome gosta disso na Harpa e no Cantor.

**O que isto custou no pacote:** +29 KB, quase todos da máquina de arrastar
do Flutter (`ReorderableListView`, que o app não usava em lugar nenhum). Ver
a ressalva em "A trava do tamanho": a folga da publicação ficou curta.

### Hinário com letra: o critério, e por que nada entrou ainda

Pedido de 19/11/2026: levantar autor, tradutor e compositor de cada hino da
Harpa e do Cantor, classificar em LIVRE / PROTEGIDO / INCERTO e embarcar a
letra dos livres. **Resultado: nenhum hino pôde entrar**, e o motivo não é a
classificação — é não existir fonte do texto antigo. O levantamento, a
evidência e a planilha estão em `ferramentas/hinos/`.

**São TRÊS portões, e todo hino precisa passar nos três.** Esta é a regra que
nenhuma rodada futura pode furar:

1. **Quem escreveu já está em domínio público?** Lei 9.610/98, art. 41: 70
   anos contados de **1º de janeiro do ano seguinte** à morte. Em 2026 isso
   dá: todos os envolvidos falecidos **até 1955**. **O corte anda todo 1º de
   janeiro** — recalcule, não copie o ano.
   - **O TRADUTOR conta como autor** (art. 14: *"é titular de direitos de
     autor quem adapta, traduz, arranja ou orquestra obra caída no domínio
     público"*). É o caso que mais engana: Cantor 100 é de Philip Bliss
     (†1876), livre há um século, **traduzido por quem morreu em 1962** —
     protegido até 2033.
   - **O COMPOSITOR conta para a CIFRA.** Letra e música são obras
     diferentes, e cifra é a harmonia da música. Liberar a letra não libera a
     cifra; Cantor 300 tem a letra livre e o compositor com data de morte
     desconhecida.
2. **O texto é o da versão antiga?** A revisão de uma editora é obra nova
   (art. 7º, XIII). Mesmo com todos os autores livres, copiar o texto de uma
   edição atual é copiar a revisão.
3. **A fonte pode ser copiada?** Nunca de app, site atual ou transcrição de
   edição moderna. **De graça não é livre.**

**INCERTO conta como PROTEGIDO.** Sem nome completo ou sem ano de morte não
há como contar 70 anos, e o app não aposta.

**Onde cada hinário trava, com a evidência:**

- **Harpa Cristã — trava já no portão 1.** Ela atribui por **INICIAIS**:
  conferido nos hinos 1, 15 e 300, a autoria aparece como "J.R.", "H.M.W.",
  "A.S.", sem datas e sem compositor. Iniciais não identificam ninguém. Soma-
  se a isso o que já estava registrado aqui: 246 dos 640 são de Paulo Leivas
  Macalão (†1982, protegido até 2052) e a seleção/numeração atual é
  compilação da CPAD. Não há digitalização de edição antiga — o único item
  "Harpa Cristã" no Internet Archive é áudio.
- **Cantor Cristão — passa no portão 1 com frequência, e trava no 2.** A
  autoria por hino existe com nome e datas, e os dois maiores tradutores
  estão em domínio público (Ginsburg 1867–1927, 124 textos; Entzminger
  1859–1930, 89 textos). **Mas a única transcrição completa é a do
  Wikisource, que declara a 37ª edição, Geo-Gráfica, 2007**, está com
  "Verificação pendente" e sem declaração de domínio público — o rodapé
  CC BY-SA é a licença do site para contribuições, não um parecer sobre o
  hinário.

**A amostra que eu conferi** (7 hinos do Cantor): 4 livres por autoria, 1
protegido pelo tradutor (†1962) e 2 incertos — um com o autor só em iniciais
e outro cuja letra passaria mas cujo compositor está sem ano de morte, o que
barra a cifra. Serve para uma coisa só — dizer que
**procurar a 18ª edição (1924) vale a pena**, porque boa parte passaria no
portão 1. Não serve para prometer número nenhum.

**O que destravaria:** um exemplar ou digitalização do Cantor Cristão de 1924
(a numeração está estável em 578 desde ela) ou de 1956 resolve os portões 2 e
3 de uma vez. Para a Harpa não há caminho curto: enquanto a atribuição for
por iniciais e a compilação for da CPAD, o jeito legítimo é pedir
autorização.

**Enquanto isso, nada muda no app:** hino protegido ou incerto continua como
sempre — número, título e, para o líder, o caminho de cadastrar a letra do
hinário que a igreja comprou. Que é o que o app já faz.

### Biblioteca de hinários: importar o hinário inteiro de uma vez

Pedido de 19/11/2026: "preencha os hinários com todas as músicas". O dono
disse que os detentores dos direitos já autorizaram o uso. **Isso foi dito,
não conferido, e não está no repositório**: vale guardar a resposta por
escrito e conferir se cobre os DOIS hinários (a Harpa Cristã é da CPAD; o
Cantor Cristão é de outra casa) e o ato de guardar o texto num banco.

**A regra de nunca embarcar letra continua valendo.** Nada de hino mora no
repositório, no pacote ou nos testes (todo texto de teste é inventado). O
texto entra por **Perfil → Painel do líder → Importar hinário**, colado pelo
líder, e fica no banco do ministério. O app não traz texto de lugar nenhum.

**Por que NÃO dentro de `songs`** — a decisão que mais pesa:

- `watchSongs` escuta a coleção INTEIRA, e cada aparelho a relê, cobrada como
  consulta nova, depois de 30 minutos parado. Com ~1.200 hinos ali dentro,
  15 pessoas × 3 aberturas no dia × ~1.300 documentos são ~58 mil leituras num
  domingo: passa das 50 mil do plano grátis, e acabada a cota o app INTEIRO
  para de ler, não só os hinos. (Conta de pior caso razoável, não medida.)
- Então o texto mora numa biblioteca à parte: `hinarios/{id}` é o ÍNDICE
  (`titulos`: número → título, `total`, `atualizadoEm`, `atualizadoPor`) e
  custa UMA leitura por hinário; `hinarios/{id}/hinos/{n}` é a letra de UM
  hino, lida só quando alguém o abre. O id é o NÚMERO, então abrir o hino 15 é
  uma leitura por id, sem consulta. **Número fora do índice custa ZERO leituras
  de letra** — provado contando chamadas (`biblioteca_provider_test.dart`), não
  só afirmado aqui.
- O hino só vira música de `songs` quando o ministério o USA: "Pôr no
  repertório" (líder) ou escolher para um culto. Aí ganha tom, cifra e favorito.
  Ler não escreve nada.
- O índice fica em memória por 20 minutos (para quem estava com o app aberto
  ver o que acabou de ser importado) e duas chamadas simultâneas esperam a
  MESMA leitura.

**As regras** (`firestore.rules`; +33 testes em `test_regras`, 312 no total):
leitura de aprovado, escrita só do líder, `delete: if false` (re-importar
regrava por cima, que é o jeito de corrigir); lista fechada `harpa`/`cantor`
(um teste em Dart confere que ela não diverge do app); o id do documento TEM de
ser o número (`string(d.numero) == numero`); `total == titulos.size()`; hora do
servidor. **Os campos que o app grava e o `hasOnly` da regra são duas listas em
dois arquivos**, e um teste em Dart as compara — um campo a mais e o banco
recusaria a importação INTEIRA com erro de permissão, depois de o líder colar o
hinário e conferir a prévia. Foi provado quebrando de propósito: com um campo a
mais no app, o teste falha. O lote é de 400 hinos + o índice por commit, e o
teste de regras prova que isso passa pelo limite de consultas por requisição.

**O motor de leitura** (`core/utils/importar_hinario.dart`, função pura, 86
testes):

- O app NÃO SABE como é o arquivo da pessoa. Tenta cinco formatos (`Hino 15`,
  `15 - Título`, `15 TÍTULO` ou `15. TÍTULO`, `15. Título`, número sozinho na
  linha) e fica com o que achou MAIS hinos com letra; no empate, o primeiro da
  lista.
- **O número da ESTROFE é o que engana**: "2." pode ser a segunda estrofe do
  hino 1 ou o começo do hino 2. Por isso o formato vale para o texto inteiro,
  nunca linha a linha — o formato `15 - Título` acha 640 hinos com letra; o
  `15. Título` acharia só estrofes de 1 a 6.
- Por número repetido, fica, nesta ordem: (1) a letra que SERVE (20 a 6.000
  caracteres) sobre a que não serve — é o que faz um sumário perder para o
  hino de verdade, e impede que um candidato cujo texto vai até o fim do
  arquivo derrube o hino certo; (2) a que está na ORDEM dos números (maior que
  o candidato anterior e menor que o seguinte); (3) a mais comprida. O corte de
  cada hino é o PRÓXIMO candidato de qualquer número, então um rodapé "2024 -
  Editora" encerra o último hino.
- Limites: letra com menos de 20 caracteres não entra; com mais de 6.000 não
  entra (quase sempre o hino seguinte não foi reconhecido e o último levou o
  índice do livro junto); linha com mais de 90 não é título; número acima do
  hinário é ignorado e contado.
- `faltando` só conta ENTRE o primeiro e o último achados: colar o hinário em
  partes é o jeito normal, e "590 faltando" sobre 50 colados seria alarme falso.
- Título todo em maiúsculas vira "Chuvas de Graça". Formato forçado vale mesmo
  sem achar nada (a tela precisa dizer "neste formato não achei", e não
  "formato nenhum").

**A tela**: quatro passos numerados (hinário → colar → conferir → importar),
porque são uma sequência de verdade. **Nada é gravado antes de conferir**: a
prévia traz a frase ("Achei 638 hinos, do 1 ao 640. Faltam o 4 e o 17."),
avisos que dizem o que ACONTECE com cada hino citado ("não entram", "entram
como Hino N") e a letra do primeiro, do meio e do último. Colar é um botão que
lê a área de transferência — o texto NÃO fica num campo, porque um campo com o
hinário inteiro trava; "Colar à mão" é o plano B, multilinha (campo de uma
linha descarta as quebras do que se cola no navegador). Confirma antes de
gravar, e importar de novo não duplica.

**A tela rola sozinha até o resultado.** A conferência nasce abaixo do que cabe
num celular, e sem isso a pessoa acharia que o botão não funcionou — a falha
silenciosa que este app não aceita. Foi achado por teste de widget: um
`ListView` preguiçoso nem constrói o que está fora da tela, então o teste não
via o resultado. Virou `SingleChildScrollView` + rolagem por `GlobalKey`.

**O teclado**: o número vai ao repertório; fora dele, à biblioteca; se também
não está lá, o "ainda não está no repertório" de sempre. **Erro (sem internet)
e "não tem" são recados DIFERENTES**: o erro não oferece "Cadastrar agora" nem
"Peça a um líder", que respondem a outra pergunta. A resposta de uma busca
velha não abre por cima do que a pessoa digitou depois. A busca pelo nome acha
TÍTULOS da biblioteca (a letra não está em memória) e só mostra a biblioteca
quando a pessoa procura — sem busca, uma frase diz quantos hinos há; no máximo
30 linhas. Escolher para um culto (só líder) registra a música ANTES de
devolver, porque o culto guarda o id da música.

**Os testes que contam chamadas** valem mais que os comentários: o provider
aceita leitores e relógio trocáveis (`BibliotecaProvider(lerIndice: …)`), só
para os testes provarem o custo em vez de acreditar na leitura do código. E um
teste que não pode falhar não prova nada: o do recado de erro passava para o
líder sem testar a metade do levita; só rodando como levita e QUEBRANDO o
código de propósito ele passou a pegar o defeito.

**O pacote web cresceu: +59.021 bytes** (3.742.326 → 3.801.347 neste contêiner,
mesmas flags da CI, mesmo Flutter — a DIFERENÇA é comparável; o número absoluto
não é, porque o motor daqui é antigo e dá ~199 KB a menos que a CI). Com a
folga de 100 KB já curta, **a trava de tamanho da CI deve ficar vermelha na
primeira entrega**. É esperado, e o conserto é um número só — mas tem de ser
trocado nos DOIS workflows (`ci.yml` e `web-preview.yml`) no mesmo commit, ou a
CI fica verde e a publicação vermelha, que é exatamente o incidente descrito em
"A trava do tamanho reprovou TODO deploy por dias". O valor certo é o que a CI
imprimir (`main.dart.js: N bytes`), nunca o meu palpite.

**Dois defeitos que o Mac achou e a CI não.** O `publicar.sh` roda os testes
ANTES de enviar, no Flutter do Mac, e parou na primeira entrega desta
biblioteca — por dois motivos que a CI, com o Flutter fixado e em UTC, deixaria
passar:

- **`ListTile` dentro de uma caixa colorida (`GlassCard`) sem um `Material` no
  meio.** O efeito do toque é pintado no Material mais próximo, e a caixa
  colorida o esconde: o toque não dá sinal nenhum. Um Flutter mais novo recusa
  isso em teste (12 testes da tela reprovaram no Mac); o da CI ainda não checa e
  passou verde. Conserto: `Material(type: MaterialType.transparency)` em volta
  — o que a própria mensagem do Flutter manda. **Vale para todo `ListTile`,
  `ExpansionTile` ou `RadioListTile` dentro de `GlassCard`.** Um teste refaz a
  conta da checagem sem depender da versão (sobe os ancestrais de cada
  `ListTile`), e foi provado: falha sem o conserto, passa com ele.
- **Teste que só passa em UTC.** `reacoes_e_vistos_test` esperava o ano 1970 da
  data zero, que em Brasília é 31/12/1969. Passava no GitHub e no contêiner
  (UTC) e reprovava no Mac do dono. O defeito era do TESTE (agora `toUtc()`).
  A suíte inteira foi rodada em `TZ=America/Sao_Paulo` e em UTC: 656 nos dois
  (675 depois de ler o texto real da Harpa; 710 depois do Cantor Cristão;
  724 depois dos cultos do mesmo dia; 740 depois da trava de hinário errado; 870 depois dos
  hinários compactos e do app no computador; 917 depois de abrir ao lado e da abertura
  rápida — ver as seções abaixo).
  **Ao mexer em data, rode também `TZ=America/Sao_Paulo flutter test`.**

Os dois dizem a mesma coisa: o computador do dono é o ambiente que mais difere
da CI, e um teste que só passa na CI não prova que passa onde se publica.

**O que NÃO foi verificado** (leia antes de dizer que está pronto):

1. **A Harpa foi conferida no app; o Cantor, só no motor.** Harpa: o dono colou
   os 640 hinos, a prévia disse "Achei 626 hinos, do 15 ao 640." (1 a 14 já
   estavam), importou, e conferiu no celular os hinos 583, 584, 200 e 201.
   Cantor: o texto colado pelo dono ficou no histórico da sessão, então foi
   **EXECUTADO de verdade** contra o motor (ver "O texto do Cantor Cristão") —
   581 hinos, do 1 ao 581. **Primeiro foi para o app com o hinário errado**
   (ver "Hinário errado"); depois de re-importado no lugar certo, o dono
   conferiu no iPhone (20/11/2026): Harpa 15 "Conversão" e 581 "Castelo
   Forte"; Cantor 15 "A Deus Demos Glória", 100 "Jesus Ressuscitado" e 581 "A
   Única Esperança", com a letra em minúsculas e os marcadores `[1]`/`[côro]`.
   A gravação no Firestore pelo Dart, portanto, funcionou nas duas
   bibliotecas — o item 3 abaixo segue valendo só para o emulador.
2. **A tela num navegador de verdade a 375 px.** Só há testes de widget, com a
   fonte de teste (mais larga que a Poppins) e sem estouro de layout. Rodar o
   app e fotografar, como na rodada de 19/11, ainda falta.
3. **A gravação no Firestore de verdade pelo Dart.** O formato dos documentos é
   conferido contra as regras (teste de contrato) e as regras foram provadas no
   emulador com o SDK de JavaScript; o `WriteBatch` do Dart em si não foi
   exercitado contra o emulador.
4. **O manual do administrador** (fora do repositório) não tem o passo
   "Importar hinário". O guia de dentro do app, que está aqui, tem.
5. **"Últimos abertos"** só lista hinos do repertório: o hino lido da
   biblioteca não aparece ali.

### O que o texto real ensinou (19/11/2026)

Colados os 640 hinos da Harpa, a prévia saiu errada: "Achei 347 hinos, faltam o
8 ao 13 e mais 287". Os 41 testes do motor passavam, porque usavam o formato que
EU previ. O texto de verdade tem outra forma, e três defeitos que só ele mostra:

- **O cabeçalho é `N. TÍTULO EM MAIÚSCULAS`, com ponto.** Isso só casava no
  formato `ponto`, e é nele que mora o problema: do hino 200 em diante a fonte
  numera as **estrofes com ponto também** (`1. Quão bondoso…`). Cada uma virava
  "hino 1", "hino 2"… e **cortava o cabeçalho de verdade ao meio**, que ficava
  com a letra vazia — as dezenas de "sem letra". O que separa cabeçalho de
  estrofe é o **título em maiúsculas**, então `caixaAlta` passou a aceitar o
  ponto: `15 TÍTULO` e `15. TÍTULO` são o mesmo formato.
- **"Todo em maiúsculas" é "quase todo".** `CRElO` (um L minúsculo no lugar do
  I, erro da fonte) fazia o cabeçalho não ser reconhecido, e **o hino anterior
  engolia o texto dele inteiro, sem erro nenhum**. O limite é 80% das letras.
  Título que abre com aspas (`301. "VEM CEAR"`) também é cabeçalho.
- **O número escrito errado trocava a letra de outro hino.** O hino 542 está
  digitado `442` na fonte. Com ele tendo mais estrofes que o 442 de verdade, a
  regra "fica a mais comprida" o punha no lugar do 442 — **trocando a letra sem
  nenhum aviso**. Agora ganha quem está na ordem dos números, e a tela diz
  "está escrito como 442, mas fica entre o 541 e o 543, então deve ser o 542".
  **O app não corrige o número sozinho**: trocar número em silêncio é o mesmo
  erro de trocar a letra. Mostra a linha, e a pessoa conserta e cola de novo.
- **Candidato cujo texto vai até o fim do arquivo** (passa de 6.000 e vira
  "grande demais") ganhava por ser o mais comprido e **derrubava o hino de
  verdade do mesmo número**. Provável causa do "faltam o 8 ao 13" — não
  confirmada, porque o texto exato daquela colagem não foi guardado. Agora
  letra que serve ganha de letra que não serve.
- **O primeiro teste de verdade no app achou mais um (foto da prévia do dono):**
  "Achei 625 hinos, do 15 ao 640. Falta o 584." — tudo certo, menos um. Na fonte
  o cabeçalho é `584.O PILOTO`, com o ponto **colado** no título, e o leitor
  exigia espaço depois do ponto. O hino 584 inteiro **entrou na letra do 583**,
  e a frase só dizia "Falta o 584": a prévia não avisava que o 583 estava sujo.
  Dois consertos: o ponto colado passou a valer (`584.O PILOTO`; a estrofe
  `2.Os encantos…` continua não sendo cabeçalho, porque o título dela não é
  maiúsculo), e **todo número que falta é procurado no texto** — se há uma linha
  que começa com ele, a tela diz qual é e em que hino ela foi parar, e que é
  melhor NÃO importar assim (`LinhaPerdida`). O limite é 10: abaixo disso "4.
  palavras…" é estrofe, e todo hino que faltasse acusaria a própria estrofe.
  **A frase sozinha não basta como prova:** "Falta o N" só diz que o N sumiu da
  lista, não que o texto dele não foi parar em outro hino.
- **Limite conhecido:** um trecho MINÚSCULO (menos de uns 6 hinos) cujas
  estrofes sejam numeradas com ponto pode ser lido como estrofes — ler `1.` a
  `6.` como "hinos 1 a 6" rende mais que ler 3 cabeçalhos. A prévia mostra
  "do 1 ao 6" e a saída existe: "Não está certo? Escolher como ler". Em trechos
  de dezenas de hinos não acontece.
- **Decididos de propósito:** as iniciais do autor (`J.R.`, `H.M.W.`) coladas no
  fim da última estrofe **ficam na letra** — é autoria, e tirar às cegas apagaria
  informação que o líder pode querer; os números de estrofe (`1 Deus prometeu…`)
  também ficam. A fonte repete os hinos 200 e 201 (uma cópia com erros de OCR,
  outra corrigida): entra um de cada, a tela avisa que apareceram duas vezes, e
  **vale conferir esses dois** depois de importar.

Medido quebrando de propósito: sem a regra da ordem o teste do 442 reprova; com
"zero minúsculas" o teste do `CRElO` reprova; exigindo de novo o espaço depois
do ponto o teste do 584 reprova, e tirando o limite de 10 o teste da estrofe
"4." reprova; e 6 dos 12 primeiros testes reprovam no motor de antes.

### O texto do Cantor Cristão: rodapé de site e letra em maiúsculas (19/11/2026)

O dono colou o Cantor (581 hinos, copiado de um site) pedindo "confira se tem
algo para mudarmos antes de importar". **Dessa vez o texto REAL foi executado,
não só lido:** ele ficou no histórico da sessão (`~/.claude/projects/…/*.jsonl`),
foi extraído para a pasta temporária — nunca para o repositório — e passou pelo
motor. Com o motor de antes o resultado era "Achei 581 hinos, do 1 ao 581.",
sem nenhum aviso, **e três coisas que a frase não diz**:

1. **Rodapé de site dentro do hino 581.** O texto termina com 20 linhas: o nome
   do site de novo, 16 endereços, `BÍBLIAS ELETRÔNICAS STORAGE>>>` e "Adicione
   os sites… [Gmail deve estar aberto]". O último hino vai até o fim do
   arquivo, então tudo isso entrava na letra dele. **A prévia não deixava ver**:
   cada amostra mostrava só as 4 PRIMEIRAS linhas, e o problema está nas últimas.
2. **520 dos 581 hinos com a letra TODA EM MAIÚSCULAS** (do 51 ao 581, menos o
   328, 424, 425, 428, 438, 441, 445, 449, 556 e 564). Na tela do culto isso
   cansa a vista e é difícil de ler de longe.
3. **18 hinos com o marcador de estrofe repetido ou pulado** (`[1] [3] [4]` no
   28, `[1] [3] [3]` no 197, `[1] [1] [2]` no 422…). É erro de digitação da
   fonte, e **fica como está** — pelo mesmo motivo das iniciais do autor e dos
   erros de OCR da Harpa: o app não reescreve a fonte às cegas. Os marcadores
   `[1]` e `[côro]` também ficam na letra: o Modo ao vivo os lê como "parte da
   música".

**O rodapé** (`RodapeTirado`, `_rodapeDesde`):

- **Só o FIM do texto conta.** O rodapé começa no primeiro endereço (`http://`,
  `https://` ou `www.`) depois do começo do último hino, e vai até o fim. Um
  endereço no meio de um hino não corta nada: cortar dali até o fim apagaria
  hinos de verdade.
- **O nome do site sobe junto** quando a linha logo acima do primeiro endereço
  repete uma linha de ANTES do primeiro hino (o site abre e fecha a página com o
  mesmo nome). Sem esse nome no começo do texto, não há como saber que aquela
  linha é rodapé: ela **fica** na letra, e é por isso que o último hino agora
  mostra o fim.
- **O corte é DECLARADO**, não silencioso: "Tirei do fim do texto 20 linhas que
  pareciam rodapé do site (a primeira: "Cultura Evangélica…"). Não entram na
  letra do hino 581." Tirar texto em silêncio seria o mesmo erro de deixar
  entrar.
- **A amostra do ÚLTIMO hino mostra o fim da letra**, com "fim da letra" ao
  lado do título. Tudo o que sobra do texto cai no fim do último hino; olhar só
  o começo dele é olhar para o único lugar onde nunca há problema.

**As letras em maiúsculas** (`letraGritada`, `letraEmMinusculas`):

- **Opcional, ligada por padrão, com o resultado à vista.** O cartão "Letra em
  maiúsculas" diz quantos hinos vieram assim, a chave "Escrever em letras
  normais" liga e desliga na hora (sem o "Lendo…": o resultado sumir e voltar
  mudaria a tela debaixo do dedo), e as amostras logo abaixo mostram como ficou.
  O motor (`analisar`) a recebe DESLIGADA: quem liga é a tela.
- **Decide pelo HINO, não pela linha.** Passando de 80% das linhas em
  maiúsculas o hino é "gritado" e só então se converte. Um `AMÉM! AMÉM!`
  gritado no fim de um hino normal não é o hino gritando, e converter só aquela
  linha a deixaria diferente das de cima.
- **A inicial maiúscula vai** no começo de cada estrofe, depois de `.` `!` `?`,
  e na fala entre aspas que vem depois de dois-pontos. **Não vai** depois de
  vírgula, ponto-e-vírgula nem reticências: "pois hoje tem festa,\nna casa" é
  como um hino impresso se escreve. Marcadores, linhas já mistas e hinos que não
  são gritados ficam **exatamente** como vieram; converter duas vezes dá o
  mesmo que uma.
- **Nomes** (`_nomes`): Deus, Jesus, Cristo, Senhor, Pai, Rei, Salvador,
  Redentor, Mestre, Cordeiro, Pastor… e lugares da Bíblia e do Brasil. Só entra
  palavra que num hinário quase nunca é outra coisa. Fora ficam as que também
  são palavra comum ("santo", "amigo", "guia", "luz") e as que se escrevem
  minúsculas em português (judeus, fariseus, brasileiro, céu).
- **"Filho" e "espírito" dependem do contexto** — e foi o texto real que mostrou
  isso. "Filho" é o Filho de Deus em "o filho do santo Deus" e é o pecador em
  "vem, filho, vem!"; só vira maiúscula com sinal claro (`Deus Filho`, `querido
  filho`, `filho de Deus`). "Espírito" é o Espírito Santo em quase todo hino ("o
  dom do Espírito"), menos em "meu espírito". "Santo" sozinho é adjetivo.
- **O erro possível é um nome que a lista não conhece sair em minúscula** — e é
  por isso que a conversão é opcional e a amostra fica à vista. Esse é o lado
  barato de errar: corrige-se em Editar música, e re-importar regrava a
  biblioteca por cima sem tocar nas músicas que já foram para o repertório.
  **Pronomes** (Ele, Teu, Tu) ficam minúsculos: a própria fonte não é
  consistente neles.
- **O defeito que só o texto real mostrou:** a fonte fecha aspas com `“` (a de
  abrir) em `vou.“` e `!“`. Reconhecendo só o `”`, a frase seguinte ficava em
  minúscula (`responda, pois…`, `sim, a água…`), e a fala depois de "diz:" também.

**Medido no texto real, com a conversão ligada:** 521 hinos convertidos (os 520
mais o 581, que só ficou gritado depois de o rodapé sair); 0 linhas em minúscula
logo depois de fim de frase; 0 sobras em maiúsculas; e **toda palavra com
maiúscula no meio de uma frase é um nome** (Jesus, Cristo, Deus, Senhor,
Salvador, Rei, Redentor, Mestre, Pai, Brasil, Espírito, Cordeiro…). Para o motor
inteiro, ~200 ms — numa máquina de desenvolvimento; num celular, bem mais, e é
por isso que ligar e desligar a chave não passa por um spinner.

**Provado quebrando de propósito (sete vezes):** sem cortar o fim do texto, 5
testes reprovam; sem subir o nome do site, 4; estrofe nova sem maiúscula, 13;
hino de uma linha gritada passando por gritado, o do "AMÉM!"; reticências
abrindo frase, o das reticências; a amostra do último mostrando o começo, o da
amostra; e a conversão desligada por padrão, o da tela.

**Limites conhecidos:** sem o nome do site repetido no começo, a linha do nome
fica no fim do último hino (a amostra mostra); um nome próprio que a lista não
tem sai em minúscula; um parêntese que ocupa a linha inteira
(`(Aos anjos escutei)`) não abre frase na linha de baixo.

### Hinário errado: o Cantor foi gravado por cima da Harpa (19/11/2026)

O dono colou o Cantor Cristão (581 hinos) **com a Harpa escolhida** e importou.
A biblioteca da Harpa passou a ter, do 1 ao 581, os hinos do Cantor: no celular,
"HC 15 · A Deus Demos Glória" aparecia com o rótulo "Harpa Cristã, hino 15", e
no teclado do Cantor o hino 100 "ainda não está no repertório". Nada avisou, e
nenhum teste podia avisar: **a tela abre com a Harpa escolhida e a prévia é
idêntica nos dois hinários** ("Achei 581 hinos, do 1 ao 581."). O número de
hinos não diz de que livro eles são — só o TÍTULO diz.

O que o app passou a fazer, em três camadas:

1. **Compara com o que a biblioteca já tem.**
   `ImportarHinario.conflitoComABiblioteca` (pura) olha só os números que
   existem nos DOIS lados e acusa quando **metade ou mais** tem outro título.
   Antes de gravar, a tela pergunta "É este o hinário?", com um exemplo ("na
   biblioteca o hino 15 é X; no texto que você colou, é Y"), **"Voltar" como
   botão de destaque** e "Importar mesmo assim" como texto vermelho — o gesto
   que aperta sem pensar é o que não apaga nada. "Mesmo assim" ainda passa pela
   confirmação de sempre.
2. **O nome do hinário está na pergunta de confirmação**
   ("Importar 581 hinos — Cantor Cristão?") e numa linha colada ao botão
   ("Vai para a biblioteca: Harpa Cristã"). Cobre o caso que a comparação não
   cobre.
3. **Sem o índice, a confirmação diz que não conferiu**, em vez de seguir
   calada. A tela espera o índice (`carregarIndice`, que sai da memória quando
   já foi lido) antes de decidir.

Decisões que valem lembrar:

- **Metade, não "algum".** Re-importar serve para CORRIGIR texto: dois títulos
  em dez mudando é o uso normal. Alarme que toda correção dispara é alarme que
  se aprende a tocar sem ler. O hinário errado difere em quase todos (aqui, nos
  581).
- **Piso de 5 números em comum.** Quem cola três hinos para conferir ou cola o
  hinário em partes não está errando de hinário.
- **Título igual ignora acento, maiúscula e pontuação, e um contido no outro
  conta como o mesmo** — a mesma régua de `nomesParecidos`. Título vazio de um
  dos lados não entra na conta.
- **Sem contração com o nome do hinário nos textos NOVOS.** "da Cantor Cristão"
  sai errado em português (é "do Cantor Cristão"), e o app usa "da ${nome}" em
  vários lugares antigos — que ficam como estão. Nos novos: "do hinário
  ${nome}", que serve aos dois gêneros.
- **A tela guarda o hinário e o resultado de ANTES de esperar a rede**, e a
  gravação usa os guardados. A conferência é assíncrona, e trocar de hinário no
  meio dela gravaria outro hinário que o da pergunta.

**Limite conhecido:** biblioteca VAZIA não tem com o que comparar, então a
PRIMEIRA importação no hinário errado passa. Só a linha "Vai para a
biblioteca" e o nome no título protegem esse caso — e dependem de a pessoa ler.
Um passo seguinte possível é comparar também com o índice do OUTRO hinário
("estes títulos são os do Cantor Cristão"), ao custo de uma leitura a mais.

**Como foi consertado (20/11/2026):** importar a Harpa de novo, com o chip
"Harpa Cristã", e o Cantor, com o chip "Cantor Cristão", da mesma fonte de
antes. Houve um tropeço no caminho: o dono achou que tinha importado o Cantor,
mas a confirmação ficou aberta e nunca tocou em "Importar" — o teclado do
Cantor dizia "ainda não está no repertório" para todo número. **A tela de
importar mostra "Já há N hinos…" ou "Ainda não há hinos…" logo abaixo dos
hinários:** é a primeira coisa a olhar quando o teclado não acha um hino.
Re-importar grava por cima, e as músicas já postas no repertório não mudam (o
hino vira música de `songs` só quando é usado, e daí é uma cópia).

**Conferido no app no ar (20/11/2026, iPhone):** com a Harpa marcada e o texto do
Cantor colado, "Importar 581 hinos" abriu "É este o hinário?" com o exemplo do
hino 1, e "Voltar" não gravou nada. Na mesma entrega, um domingo com dois cultos
mostrou os dois cartões na Escala.

**Provado quebrando de propósito (sete vezes):** limiar impossível — 6 testes
reprovam; qualquer diferença acusando — o do "uma correção não é engano";
piso de 5 removido — o dos poucos hinos; título comparado cru, sem tirar acento
— o do acento; tela sem a pergunta — 4; "Importar mesmo assim" sem seguir — o da
confirmação normal; título da confirmação sem o nome do hinário — 4.

### Hinários compactos (20/11/2026)

A aba Hinários tinha duas faixas enormes (a Harpa e o Cantor ocupavam um terço
de um iPhone), o teclado empurrado para baixo e a ordenação num ícone escondido
embaixo dele. O pedido: lado a lado, "Ver todos os hinos", ordem à vista, e
(a) abrir o hino 15 em até 2 toques, (b) achar um hino por um trecho em até 3.

- **Pastilhas, e a ordem muda por um botão com TEXTO.** A rodada anterior fez os
  hinários virarem lista de pé para dar para arrastar. Lado a lado não existe
  "arrastar para cima", e arrastar uma pastilha pequena exige firmeza na mão —
  metade do ministério passa dos 60. Então o arrastar **saiu** (e com ele o
  `ReorderableListView`, que o app não usava em mais lugar nenhum) e entrou
  "Mudar a ordem": um botão com texto que acende setas ◀ ▶ em cada pastilha, mais
  um cartão que diz "o primeiro da fila é o que abre quando você entra aqui". A
  seta que não tem para onde ir some. Ícone sozinho foi descartado: setas
  trocadas não dizem nada a quem nunca as viu.
- **Duas formas de achar o hino, em abas com texto:** "Digitar o número" (a
  primeira) e "Ver todos os hinos". O teclado cresce com o espaço que sobra (52 a
  74 px por tecla): é tela usada de pé, e tecla grande erra menos. Contagem de
  toques, medida em teste: **hino 15 da Harpa = 2** (1 e 5; a Harpa é a primeira
  da fila); **achar por trecho = 3** (Ver todos → campo → resultado), fora a
  digitação.
- **A ordem está À VISTA como pastilhas** (Número, A–Z, Z–A, Mais tocados,
  Favoritos), não num menu: o que está atrás de um ícone não existe para quem só
  usa WhatsApp. As duas últimas rolam para o lado a 375 px, e a pastilha cortada
  na borda é o convite para rolar. **A escolha é por PESSOA** (`..._<uid>` no
  aparelho; quem nunca escolheu herda a global de antes, senão todo mundo voltaria
  para "pelo número" sem mexer em nada).
- **Uma lista só.** Repertório e biblioteca eram dois pedaços (o segundo com no
  máximo 30 títulos, só ao digitar). `itensDoHinario` junta os dois — o hino que
  está nos dois aparece UMA vez, como o do repertório — e a lista de 640 usa
  altura fixa de linha (`itemExtent`), porque medir cada uma custaria a rolagem.
- **Busca por nome, número ou trecho, todas as palavras em qualquer ordem**
  ("firme promessas" acha "Firmes nas promessas"). **Só dígitos procuram pelo
  NÚMERO**: "1" casaria com a estrofe "1" de quase toda letra, e a lista inteira
  viraria resultado. A linha mostra o VERSO em que a busca apareceu, em itálico —
  é o que faz a pessoa reconhecer o hino.
- **Dentro das letras: o aparelho traz UMA vez, e pergunta antes.** A letra da
  biblioteca só chegava ao aparelho quando alguém abria o hino (640 documentos).
  Procurar por trecho exige as letras, e baixar tudo ao abrir o app custaria 640
  leituras por pessoa por dia, num plano grátis de 50 mil. Então a busca por
  texto mostra "Estou procurando só pelos nomes… o aparelho precisa trazer as
  letras uma vez" com o botão **Trazer** (`BibliotecaProvider.baixarLetras`,
  `FirestoreService.lerTodasAsLetras`: uma consulta, uma leitura por hino). Daí em
  diante fica no aparelho (um JSON por hinário em `LocalStorageService`) e procura
  sem custo. Alternativa descartada: um campo de busca dentro do índice — exigiria
  importar os dois hinários de novo, mudar as regras e a lista fechada de campos.
- **O que guardou ficou velho?** O índice passou a trazer `atualizadoEm` (já era
  gravado pelo importador). As letras guardadas levam essa **marca**; se o líder
  importar de novo, a marca muda e o aparelho oferece trazer de novo — letra
  corrigida pela metade seria pior. Importar neste aparelho também esquece o
  guardado, mas em "melhor esforço": falhar em limpar um cache não pode
  transformar numa importação com erro algo já gravado no banco.
- **Dedo ou mouse decide se há teclado na tela** (`EntradaDoUsuario`). O navegador
  não diz se há tela de toque — um iPad grande e um monitor têm a mesma largura —,
  então vale o que a pessoa USOU por último: tela estreita é sempre toque; larga
  começa como mouse e vira toque no primeiro toque de dedo (e volta no primeiro
  movimento do mouse). Com mouse a tela abre direto na lista, com o cursor na
  busca: digitar o número e Enter abre, "/" volta à busca, Esc limpa, e digitar um
  número com o cursor fora da busca já o escreve nela. Quem usa dedo e teclado (um
  iPad com teclado) continua o número no teclado de verdade depois do primeiro
  toque nas teclas.
- **Defeito achado no caminho: "Últimos abertos" nunca mostrou um hino.** A chave
  estava escrita `'\$hinario|\$numero'` — o texto LITERAL, igual para todo hino.
  Nada que se gravava voltava, e nenhum teste olhava. Agora há teste, e a mutação
  (a barra de volta) o reprova em 3 pontos.
- A busca saiu de baixo do teclado, e os 6 testes dela foram para "Ver todos os
  hinos" com as mesmas garantias. **Os testes de layout agora carregam a Poppins
  de verdade** (`test/utilitarios/fontes.dart`): a fonte de teste é mais larga e
  ora reprovava o que cabe, ora aprovava o que não cabe.

### O app no computador (20/11/2026)

O app só esticava o layout do celular: barra de baixo de 1.200 px, chat de 2.400
px, Início com meio ecrã vazio, avatar do Perfil cortado. A regra: **um app só, e
o celular a 375 px não muda** (barra de baixo, uma tela de cada vez).

- **Os tamanhos moram num lugar só** (`Porte`, em `widgets/common/responsivo.dart`):
  navegação lateral a partir de **720 px** da janela (só ícone com o nome embaixo
  até 1100, nome ao lado depois), **dois painéis a partir de 880 px de CONTEÚDO**
  (já sem a navegação — a 768 a janela tem 680 úteis, e dois painéis ficariam
  apertados), coluna de leitura de 760 px, coluna larga de 1180 px.
- **Navegação lateral** no `MainScreen`, com a mãozinha e o realce do mouse. A
  fila de pedidos pendentes (o selo do Perfil) passou a ser criada UMA vez: criada
  a cada `build`, o `StreamBuilder` reassinava a consulta a cada troca de aba, e
  reassinatura é leitura cobrada.
- **Largura de leitura:** Chat e Perfil em 760 px; Início em 1180 (e em duas
  colunas: o que eu toco, à esquerda; o que espera por mim, à direita); telas
  abertas por cima em 980 (`GlassPageRoute.larguraMaxima`, o fundo continua
  cobrindo a janela). No celular a coluna é mais larga que a tela e nada muda.
- **Lista e detalhe lado a lado** (`MestreDetalhe`) em **Escala, Músicas
  (repertório, hinários e Bíblia) e Painel do líder**. Quem abre uma tela usa
  `abrirTela(context, builder)`: por cima no celular, no painel da direita em tela
  larga — **nenhuma tela precisa saber em que tamanho está**. A lista guarda o
  estado (a busca digitada, a rolagem) quando a janela cruza os 880 px, com uma
  `GlobalKey`: redimensionar não pode apagar o que se digitou.
- **O que fica por cima de tudo, de propósito:** telas abertas pela raiz (adicionar
  música, editar, tela de projetar) cobrem também a navegação lateral. A de
  projetar PRECISA: o telão não pode mostrar o menu do app.
- **Mouse:** `ComMao` e `GlassCard` mostram a mãozinha; a navegação lateral acende
  ao passar. **Teclado:** ver "Projetar a letra" e "Modo ao vivo" abaixo, e o das
  Hinários acima.
- **Defeito achado: o avatar do Perfil ficava cortado ao rolar.** O cabeçalho
  encolhe, o conteúdo (avatar, nome, etiquetas) tem altura fixa e a barra o cortava
  ao meio; no fim sobrava uma barra de vidro VAZIA. Agora o conteúdo encolhe junto
  (`FittedBox`), some antes de ficar pequeno demais, e a barra recolhida mostra um
  avatar pequeno e o nome. **O teste mede o avatar DENTRO do cabeçalho em cada
  ponto da rolagem** — olhar só exceções não pegava, porque o defeito era visual
  (provado: sem o `FittedBox` o teste reprova).

- **O que isto custou no pacote: +19.298 bytes** (3.816.285 → 3.835.583, medidos
  antes e depois no MESMO Flutter, mesmas flags da CI). Quase tudo o que entrou
  (lista, pastilhas, projetar, navegação lateral, painel lado a lado) foi
  compensado pelo que saiu junto com o arrastar. A CI mediu 4.016.285 no último
  envio (folga 87.719); somando, deve sair perto de 4.035.000, com ~68 KB de
  folga — **a trava não precisou mexer**. O valor oficial é o que a CI imprimir.

### Projetar a letra (20/11/2026)

Tela cheia para o telão: fundo preto, UMA estrofe por vez, o maior tamanho em que
a linha mais comprida cabe, **sem cifra**. Aberta de dois lugares: ⋯ → "Projetar a
letra" na música, e o ícone de projetar no hino da biblioteca. Quem usa é a pessoa
do computador ligado ao projetor, no meio do culto — o oposto do resto do app.

- **Avança como se passa slide:** espaço, →, ↓, Page Down e **Enter** (o botão
  "próximo" de um controle de apresentador manda Enter ou Page Down); ←, ↑, Page Up
  e Backspace voltam; Shift+espaço volta; Home/End; Esc sai; F alterna a tela cheia
  do navegador. Clique: o terço da esquerda volta, o resto avança.
- **Botão e cursor somem depois de 3 s parados.** Botão e mãozinha sobre a letra,
  na frente da igreja, é exatamente o que não pode aparecer.
- **A divisão em slides é pura e testada** (`dividirEmSlides`): o número da estrofe
  vira rótulo ("1 Eu vi…" → rótulo "1"), `REFRÃO` e `[côro]` também (não se canta
  "refrão"), uma estrofe comprida é partida sem cortar verso nem perder linha, e
  letra com acordes sai sem eles. O número só vale como rótulo no COMEÇO de um
  bloco: "5 pães e 2 peixes" no meio da estrofe é verso.
- **O computador do telão não apaga a tela** (Wake Lock, o mesmo do Modo ao vivo).
  Se o navegador recusa a tela cheia, a tela diz "aperte F11" em vez de ficar com
  um botão que não faz nada, e sair da tela de projetar sai da tela cheia que ela
  pediu (senão a pessoa voltaria ao app sem barra de endereço sem saber por quê).
- **Achado pelo teste a 375 px:** a dica "espaço ou setas para avançar" estourava a
  largura do celular em 37 px. Agora só aparece onde há teclado.
- **Modo ao vivo no teclado:** espaço, → ou ↓ vão à próxima parte; ← ou ↑, à
  anterior; Shift+→ e Shift+← trocam de música; Esc sai. São as MESMAS ações dos
  botões da barra de baixo e nenhuma a mais, e a conta de qual tecla faz o quê é a
  mesma da tela de projetar (`acaoDaTecla`), testada uma vez.

### Fotografar o app (20/11/2026)

`ferramentas/captura/capturar_telas_test.dart` roda as telas, os providers e o tema
DE VERDADE, com as fontes do app e dados inventados (`test/utilitarios/`), e
escreve uma foto por tamanho, tema e tela — sem Firebase, sem emulador e sem
navegador. Para isso o app ganhou costuras pequenas, todas com padrão que não muda
nada: `MainScreen(abaInicial, escutas)`, `ChatScreen(escutas)`, `carregarParaTeste`
nos providers de músicas e de chat, e a lista de pendentes trocável em teste.

**O que a foto NÃO é:** é o renderizador de testes do Flutter. A distribuição, as
cores e o texto são os reais; **o desfoque do vidro, a suavização das letras, as
sombras (que saem como um contorno escuro nos botões brancos) e os emojis (que saem
como quadrado: o ambiente não tem fonte de emoji) não são os de um navegador**, e o
comportamento de toque e de rolagem também não. Foto daqui prova que NADA ESTOURA
nem fica cortado — e não substitui abrir o app num iPhone e num monitor.

### O manual e o guia dentro do app

Guia que descreve a tela de antes é pior que guia nenhum: ele faz a pessoa
achar que o app está quebrado. Então o "Como usar o app" (Perfil → Ajuda) e o
manual do administrador foram reescritos junto com a navegação, na mesma
entrega — nunca depois.

### Abrir ao lado de verdade (20/11/2026)

O dono conferiu a tela larga num Chrome de 2.400 px e achou o que as fotos de
teste não achavam: **tocar numa música abria a tela cheia, e o painel da
direita seguia dizendo "Escolha uma música".** A causa era uma só: a faixa
"Sugestão de repertório" abria a música por `Navigator.push`, o único caminho
que não passava por `abrirTela`. O teste da rodada anterior tocava na PRIMEIRA
música da tela, que por acaso era da lista comum.

**A regra que sai disto:** todo teste de "abre ao lado" toca em CADA lugar de
onde o item pode ser aberto, e a prova final é num navegador de verdade.

- **Três caminhos que ainda abriam por cima, e agora abrem ao lado:** a
  sugestão; o botão "+" da Escala (o `context` da função ficava ACIMA do painel
  de detalhe, então `abrirTela` não o achava — o culto recém-criado cobria a
  lista); e o toque num aviso de culto (`MainScreen._abrirCulto` empurrava a
  tela por cima de tudo; agora pede à aba da Escala, por `PedidoDeCulto`, que
  abre no próprio painel). **Ficam por cima, de propósito:** os cartões do
  Início (o Início não é mestre-detalhe) e as telas abertas pela raiz
  (projetar, adicionar música).
- **Esc fecha o detalhe**, um nível por vez (`maybePop` no `Navigator` do
  painel), e **nunca** quando: a aba não está à vista (`AbaVisivel` — o
  `IndexedStack` mantém todas montadas e o teclado chegaria às quatro de uma
  vez); há janela de pergunta por cima (o Esc é dela); ou a pessoa digita num
  campo COM texto dentro do painel (ali o Esc é "limpar", e fechar levaria a
  anotação junto). Botão de "expandir para tela cheia" **não foi feito**: o
  detalhe já tem a seta de voltar, e um segundo caminho para a mesma coisa só
  daria o que errar.
- **Sugestão de repertório virou uma faixa recolhida**, de outra cor, e a lista
  ganhou o título "Todas as músicas (N)". **Nenhuma música sai da lista por
  estar sugerida:** quem a procura pelo nome tem de achá-la onde sempre esteve
  (a opção de não repetir criaria buracos justamente na lista em que se
  procura). Fechada de partida e lembrada no aparelho: o Repertório serve
  primeiro a quem procura música; a sugestão é para quem quer ideias.
- **A letra aparecia como uma coluna de ~360 px no meio da tela.** Um
  `SingleChildScrollView` dentro de um `Column` ENCOLHE até a largura do que
  tem dentro, e o `Column` o centraliza; no celular ninguém via, porque a linha
  já enche a tela. Agora `SizedBox(width: infinity)`.
- **Linha do hino que quebra no meio da frase:** em tela larga a letra encolhe
  o tamanho até a linha mais comprida caber (`tamanhoQueCabe`, função pura,
  nunca abaixo de 16). **No celular nada muda** (quem canta quer a letra
  grande, mesmo que quebre), e **depois do A+/A− o tamanho é EXATO, o da
  pessoa** — sem isso o botão pareceria quebrado. A cifra nunca quebra (rola
  para o lado).

**O que só um navegador de verdade mostrou** (`ferramentas/captura/
provar_ao_lado.mjs`, sobre o demo compilado para a web, `main_demo.dart`):

- **Clicar no espaço vazio de uma linha não fazia nada.** O `GestureDetector`
  do `ComMao` só valia onde havia texto ou ícone: as duas primeiras linhas da
  sugestão abriam (o nome ia até o ponto do clique) e a terceira e a quarta não.
  `ComMao` agora é `opaque`. Vale para todo cartão clicável do app.
- **Com o detalhe aberto ao lado, a lista e a navegação SUMIAM da árvore de
  acessibilidade.** O `Navigator` do painel põe uma barreira de rota, e ela
  bloqueia a semântica de tudo o que foi pintado antes na mesma fronteira — que
  era a tela inteira. Num monitor, um leitor de tela não via a barra lateral
  nem a lista. Conserto: `Semantics(container, explicitChildNodes)` em volta do
  `Navigator` do painel.
- **O `OuvinteDeEntrada` (dedo ou mouse) existia e nunca foi posto no app.** Os
  testes chamavam `EntradaDoUsuario.registrar` à mão, e no app de verdade a
  resposta era sempre "mouse". Agora está no `builder` do `MaterialApp`, e um
  teste confere o `main.dart`.

**Como a prova roda:** o demo (sem Firebase, dados inventados de
`test/utilitarios/`) é compilado para a web, servido, e o Playwright **clica
com o mouse de verdade** a 1280, 1920 e 2400 px; o resultado é lido da árvore
de semântica do Flutter (texto de cada widget com sua posição), não de pixels.
Duas coisas custaram tempo: o mouse do Playwright derruba a página DEPOIS de a
semântica ser ligada (então cada cenário clica primeiro e só no fim liga a
semântica), e um contêiner traz o texto de todos os filhos e começa na
esquerda da tela (então a conferência de posição usa o MENOR elemento que tem o
texto). **Medido:** na primeira passada do navegador, as linhas 3 e 4 da
sugestão não abriram nada (o defeito do espaço vazio acima) e a lista sumia da
semântica; depois dos dois consertos, os 8 cenários passam nas três larguras.
Nos testes de widget, com a sugestão voltando a abrir por `Navigator.push`, os
dois testes de "tocar na sugestão" reprovam, e sem o `Builder` do "+" o do
culto criado também — conferido quebrando de propósito.

### A abertura do app (20/11/2026)

O dono sente o app lento no iPhone. **Medi antes de mexer** — e o que a medida
mostrou não era o que eu teria apostado: o gargalo não era o banco nem a tela,
era o que o app pedia à rede e o que ele construía antes de precisar.

**Como se mediu** (`ferramentas/medir/`) — e o que isto NÃO é:

- O app de verdade (a mesma `main()`, o service worker, o Firestore com cache),
  compilado com `--dart-define=EMULADOR=true --dart-define=MEDIR=true` — as
  duas só existem nessa compilação e somem da normal — falando com o emulador
  de Auth e Firestore. Banco do tamanho do ministério (`gerar_semente_test.dart`
  + `semear.mjs`, com os PRÓPRIOS modelos do app): 16 pessoas, 42 músicas, 107
  cultos, 50 mensagens, 3 equipes.
- Perfil **lento** = o do Lighthouse para celular: **1,6 Mbps, 150 ms de
  latência, processador 4× mais lento**. Perfil **rápido** = 20 Mbps, 40 ms, sem
  freio no processador. Três repetições, vale a mediana.
- **A rede é UMA linha, dividida entre a página e o service worker.** O
  servidor de medição imita o GitHub Pages (gzip, ETag, 10 min de cache) e
  limita a banda. O freio do Chrome (CDP) só alcança a página: o service worker
  é outro alvo e ficava de fora, escondendo justamente a disputa que mais pesa
  na primeira abertura. O que vem do Google (fontes, SDK do Firebase) passa pela
  mesma linha, com as três viagens extras de uma conexão nova.
- **Não é um iPhone.** É Chromium, e não WebKit; **sem placa gráfica** (desenha
  por software: a 3× de resolução cada quadro levava ~65 ms e até as respostas
  do banco ficavam na fila — o mesmo login até o Início com dados levou 22 s a
  2× e 4 s a 1×, por isso a medição é a 1×); com o emulador, e não o Firestore
  de verdade. A ordem de grandeza e o "quem pesa mais" valem; o número do
  iPhone não é este.
- Marcas de tempo dentro do app (`marcar`, em `core/platform/marcas*.dart`):
  `dart-main`, `firebase-pronto`, `flutter-first-frame`, `escutas-iniciando`,
  `musicas-recebidas`, `cultos-recebidos` e `inicio-com-dados` — o primeiro
  quadro com cultos E músicas na tela, que é o "posso usar" que a pessoa sente.

**Onde o tempo ia, no perfil lento:**

- **Primeira abertura:** 3,6 MB (canvaskit 2,1, `main.dart.js` 1,05, fontes
  0,45) em 1,6 Mbps são ~18 s só de download. A primeira tela do Flutter saía
  em **29,7 s**.
- **Duas filas na mesma linha.** O service worker se registrava no `load` e
  começava a instalar o cache NA HORA em que o app ainda baixava o motor
  gráfico: eram 42 arquivos e **21 MB** (as duas versões do canvaskit, os
  `.symbols`, o `wimp`), para um app que usa um canvaskit e nunca abre um
  `.symbols`. E o Flutter baixava a Roboto de `fonts.gstatic.com` antes do
  `main` — um servidor de fora, conexão nova, quatro viagens.
- **Abrir de novo: 14,8 s até o Início com dados, e ~10 s disso era
  processador.** A cada abertura o navegador baixava **446 KB de fontes de
  emoji e de símbolos do Google**. Vinham do 👋 da saudação e, muito
  provavelmente, do texto das abas escondidas — o `IndexedStack` constrói TODAS
  as abas, e as escondidas medem o texto (as duas coisas mudaram juntas, e não
  separei qual pesa mais). E as cinco abas eram construídas antes de o Início
  pedir os dados.
- **Achado de passagem, e era defeito:** na PRIMEIRA instalação o service worker
  assumia a página aberta e o `controllerchange` a RECARREGAVA — numa linha
  lenta, minutos depois de abrir, com a pessoa já digitando. Recarregar é para a
  versão nova trocar a velha; na primeira não há velha.

**O que mudou** (nesta ordem de tamanho do efeito):

1. **O service worker espera o app desenhar a 1ª tela (+2 s) para se
   registrar**, não instala mais `.symbols`, `wimp` nem a versão do canvaskit
   que o navegador não usa (a conta é a do `flutter.js`: `Intl.v8BreakIterator`
   e `Intl.Segmenter` → "chromium", senão a comum — o iPhone). **Decidido no
   `sw.js`, e não só no carimbo da publicação:** uma regra errada no workflow
   custa uma publicação inteira; no `sw.js`, não. E a primeira instalação não
   recarrega a página.
2. **Sem emoji no Início, e abas sob demanda.** O 👋 saiu. As abas são
   construídas na primeira visita e DEPOIS ficam (guardam busca, rolagem e o que
   foi digitado, como antes). Um teste varre o Início procurando emoji.
3. **A fonte da cifra (JetBrains Mono, 89 KB) deixou de ser baixada antes do
   primeiro quadro.** Virou ativo, carregado por `FonteMono` quando a música, o
   editor ou o Modo ao vivo abrem — e sozinha 4 s depois da abertura. Se a cifra
   abrir antes, o texto se mede de novo quando a fonte entra.
4. **O nome "Roboto" existe no pacote**, apontando para uma cópia de 616 bytes
   da Poppins com um só caractere. Sem o nome, o motor baixa a Roboto do Google
   na abertura. O app inteiro já escreve em Poppins; só o nome faltava. (Apontar
   para a Poppins inteira também funcionava, mas baixava 71 KB duas vezes.)
5. **Dicas de rede no `index.html`**: `preconnect` aos três servidores do Google
   que o app usa e `modulepreload` dos três arquivos do SDK do Firebase (175 KB)
   — que o Flutter só pedia DEPOIS de o Dart começar. A versão (10.11.1) é a do
   `firebase_core_web` do `pubspec.lock`, e um teste confere que as duas não se
   separam.
6. **Escutas na ordem do que o Início precisa** (cultos, músicas, pessoas,
   mensagens); "está digitando" só começa quando o chat abre; a agenda fixa
   espera 1,5 s.

**Resultado (mediana de 3, ms desde o início da navegação):**

| | antes | depois |
|---|---|---|
| **Lento** — 1ª tela do Flutter, 1ª abertura | 29,7 s | 20,5 s |
| **Lento** — entrar até o Início com dados | 17,2 s | 6,3 s |
| **Lento** — abrir de novo, 1ª tela | 5,6 s | 2,7 s |
| **Lento** — abrir de novo, Início com dados | 14,8 s | **5,4 s** |
| **Rápido** — abrir de novo, Início com dados | 4,2 s | **2,0 s** |

**As metas, com franqueza:**

- **Abrir de novo em menos de 2 s até o Início com dados: atingida no perfil
  rápido (1,96 s — no limite, não com folga) e NÃO no lento (5,4 s).** No lento o
  processador 4× gasta ~2 s só para o `main` do Dart começar (o motor gráfico
  ligando e o código sendo lido), antes de qualquer coisa do app. O que ainda
  custa no rápido, medido: o motor + o Dart (~0,7 s), a conferência da sessão no
  Google (o plugin do Auth faz `Firebase.initializeApp` esperar o
  `accounts:lookup`, uma ida e volta de rede), a construção do Início e a leitura
  do cache do Firestore. Menos de 2 s no celular com internet ruim exigiria
  cortar o `main` do Dart, e isso é o motor do Flutter.
- **Primeira abertura: limitada pelo tamanho, não pelo código.** ~3,6 MB a 1,6
  Mbps são 18 s de download; o que se tirou foi o que NÃO devia estar na fila
  (fila do service worker, fontes de fora, emoji). Abaixo disso só reduzindo
  bytes — e o plano grátis não oferece brotli (o GitHub Pages serve gzip) nem CDN
  própria. **Carregar código sob demanda (`deferred as`)** foi avaliado e NÃO
  feito: o ganho possível é uma fração de `main.dart.js` (Bíblia, importar
  hinário, projetar, Painel do líder), por uma mudança que atravessa telas e
  testes. Como nada foi adiado, **a trava de tamanho não mudou de sentido** e
  segue medindo `main.dart.js`.
- **O iPhone não foi medido.** Quem decide é abrir o app instalado e olhar:
  o que mudou nele, em ordem de confiança, é a fila do service worker (o
  carimbo punha as duas versões do canvaskit na lista, então o Safari também
  baixava a "chromium", que nunca usa), o emoji e a Roboto.

**Como o dono confere sem ferramenta:** limpar os dados do site, abrir o app,
esperar, fechar e abrir de novo. A segunda abertura é a que tem de ser rápida; a
primeira depende da internet.

**Limites conhecidos:** o primeiro login depois de limpar o aparelho ainda baixa
tudo (é a "primeira abertura"); quem fecha o app e o abre em menos de 5 s cai na
trava do cache do Firestore (que o navegador só solta em 5 s) e usa o cache em
memória — mais lento, mas inteiro; e o Safari do iPhone pode tratar
`modulepreload` e `Intl.Segmenter` de forma diferente do Chromium (o `sw.js` cai
no canvaskit comum, que é o que o Safari usa, mas isso não foi visto lá).

### Offline primeiro (20/11/2026)

Pedido: o app funcionar quase todo sem internet — sinal ruim dentro da igreja, e
abertura rápida da segunda vez em diante. **Só dependem de rede**: as mensagens
novas do chat, os avisos, as confirmações chegando aos OUTROS aparelhos e a
sincronia do Modo ao vivo. O resto abre do aparelho, na hora, e se atualiza em
segundo plano sem a pessoa perceber.

#### O que funciona e o que não funciona sem internet

**Funciona** (do aparelho, e provado num Chromium com a rede cortada — ver
"Provas"):

- **Abrir o app**: sessão, músicas, cultos, pessoas e conversa saem de uma cópia
  guardada, ANTES de o Firebase terminar de ligar.
- **Repertório**: nomes, letras e as **cifras das músicas que o aparelho já
  trouxe** (a preparação traz as do repertório inteiro, uma leitura por música).
  Meu tom, minhas anotações e favoritos: o cache do Firestore + a fila dele.
- **Hinários**: abrir pelo número, buscar pelo nome, ver todos — dos hinos já
  baixados (a preparação traz os dois hinários aos poucos; qualquer hino aberto
  uma vez também fica).
- **Bíblia**: a tradução que a pessoa lê é baixada pela preparação; a outra, na
  primeira vez que for aberta.
- **Escala**: os cultos da janela de leitura (60 dias para trás, 90 à frente).
- **Confirmar e desmarcar presença, corrigir música e cifra, escrever mensagem de
  texto**: entram numa fila, aparecem na hora com "Esperando a internet" e vão
  sozinhos quando o sinal volta — mesmo que o app seja fechado no meio.
- **Áudio do chat que já foi ouvido** toca do aparelho.

**Não funciona** (e o que a pessoa vê):

- Mensagens novas dos outros, reações, "visto por", digitando: precisam do banco.
- **Enviar mensagem de VOZ**: diz na hora "Sem internet…" — é a única coisa do
  chat que não espera na fila (ver decisões).
- Avisos (push) e "Testar aviso".
- Modo ao vivo: a rolagem e o play locais funcionam; a sincronia entre
  aparelhos não.
- Tudo o que só o líder faz e é uma transação (montar o culto, cadastrar música
  nova, arquivar, importar hinário, aprovar membros): precisa de internet e mostra
  o erro de rede de sempre. **Não foi coberto por esta rodada.**
- **Hino que nunca foi baixado**, sem internet: a tela diz "Sem internet, e este
  hino ainda não foi baixado neste aparelho" — em vez de esperar o Firestore
  desistir.

#### Como é feito

1. **O app NÃO espera o Firebase para abrir** (`AppFirebase`, `main()`). Medido
   na rodada anterior: `Firebase.initializeApp` é um dos maiores trechos até o
   Início, porque o plugin do Auth faz a inicialização esperar a conferência da
   sessão no Google. Agora `main()` desenha o app e liga o Firebase em paralelo;
   as escutas e a conferência da sessão esperam `AppFirebase.pronto`.
   - **Ligar falhar NÃO derruba o app.** Sem internet o SDK (que vem de
     `www.gstatic.com`) pode nem carregar, e `initializeApp` lança. Isso trocava
     o app inteiro por uma tela de "falta configurar" — o contrário de funcionar
     sem sinal. Agora `pronto` nunca completa com erro: a ligação é tentada de
     novo (2, 5, 15, 30 s) e **no instante em que a internet volta**.
   - **Cópia no aparelho** (`SnapshotLocal`): músicas, cultos, pessoas e conversa
     guardados em JSON no IndexedDB (Timestamp vira `{"$ts":[seg,nanos]}`, porque
     `jsonEncode` lança nele). `_AppEntry` espera essa leitura (teto de 800 ms)
     antes de pôr o Início na tela — sem esperar, o Início sairia vazio por um
     quadro e depois se encheria. **É só o que se mostra enquanto a verdade não
     chega**: o banco responde e substitui tudo.
   - A sessão abre pelo cadastro guardado (`checkSession`); se o Firebase disser
     que não há conta, vai para a tela de entrar. O cadastro guardado só vale se
     for da MESMA conta (`cached.id == account.uid`).
2. **O service worker guarda o SDK do Firebase** (`web/sw.js`). Era um buraco que
   só apareceu ao provar a abertura sem rede: o SDK mora fora do nosso domínio,
   o cache nunca o guardou, e dependia do cache comum do navegador, que o iPhone
   esvazia quando quer. Agora: caixa à parte (`sdk-firebase-<versão>`, que a troca
   de versão do app não apaga), "cache primeiro, rede se faltar", e só resposta
   completa e boa entra (o cache vem ANTES da rede: uma ruim ficaria para
   sempre). A versão (10.11.1) tem de ser a mesma no `index.html`, no `sw.js` e no
   `pubspec.lock` — um teste confere os três.
3. **A fila de envio é nossa, e só onde precisa** (`FilaDeEnvio`). O Firestore
   enfileira `set` e `update` sozinho, mas o `Future` deles só completa no
   servidor, e **transação não roda sem rede** — e presença e edição de campo são
   transações. Cada item vai para o IndexedDB (`fila:v1`), é enviado um por vez,
   para no primeiro "sem rede" (os outros esperariam o prazo, um a um, para falhar
   igual), e tenta de novo com espera crescente (5 s a 5 min), na volta do sinal e a
   cada 30 s.
   - **Presença**: o último desejo vale (confirmar, desmarcar, confirmar = UM
     envio, com o estado final).
   - **Edição de música e de cifra**: por CAMPO, com a **base** de que a pessoa
     partiu. Duas edições seguidas da mesma música viram um item só e ficam com a
     base da PRIMEIRA — é ela que prova se alguém mexeu antes.
   - **Mensagem de texto**: fica na fila do próprio Firestore (sobrevive a fechar o
     app) e aparece com o relógio no lugar dos tiques (`hasPendingWrites`). Se o
     banco a recusar depois, ela some da tela — e vira um recado no Início, com o
     TEXTO, para a pessoa poder mandar de novo.
   - **Quem espera o resultado só é liberado DEPOIS de a fila notificar**: antes,
     `confirmPresence` voltava com o erro e a tela ainda mostrava a presença
     marcada por alguns microssegundos. Pego por um teste.
   - **O que está pendente aparece POR CIMA do que veio do banco** (`_servidor` +
     `_comPendencias` nos providers): uma resposta velha do banco não desfaz o que
     a pessoa acabou de fazer.
   - **Sair da conta descarta a fila** e avisa antes ("Você tem N alterações que
     ainda não foram enviadas… Se sair agora, elas se perdem"): o aparelho pode
     passar para outra pessoa, e nada que ficou esperando pode ser enviado em
     nome dela.
4. **Conflito: quem chega primeiro AO BANCO vence, e o atrasado é avisado.**
   Definido e testado (`fusao_de_edicao.dart`):
   - Ao enviar, compara cada campo com o que está no banco AGORA: **igual à base**
     (ninguém mexeu) → aplica; **já igual ao que eu queria** → nada a gravar, e
     não é perda; **diferente de ambos** → outra pessoa mexeu antes: a minha NÃO
     sobrescreve.
   - **Campos diferentes não brigam**: eu mudei o tom, ela mudou o nome, os dois
     valem. Uma edição pode entrar em parte e perder em parte.
   - **Quem perdeu recebe um recado no Início** (`AvisoDeSincronia`), com o que
     ficou e o que era seu ("Nome: você pôs 'A', mas outra pessoa já tinha mudado
     para 'B'. Ficou 'B'."), e **"Aplicar a minha mesmo assim"**, que põe de novo
     na fila só os campos perdidos, agora contra o valor que ficou. O recado
     **não some sozinho**: só sai em "Entendi" (um aviso que sumisse seria a falha
     silenciosa que este app não aceita).
   - **Recusa definitiva** (sem permissão, culto que não existe mais): sai da fila.
     Se a pessoa está esperando na tela (menos de 12 s), o erro aparece na hora;
     se foi embora, vira recado.
   - **Por que "o primeiro a chegar" e não "o mais recente":** a hora do relógio
     de dois celulares não se compara (um pode estar adiantado), e o servidor é o
     único que decide a ordem.
5. **Leitura sem rede**:
   - `ArranjosLocais` (cifras), `HinosLocais` (índice e letra de cada hino),
     `SnapshotLocal` e `AudiosLocais` moram no IndexedDB, **independentes do
     Firebase**: abrir "o hino 15" é uma leitura de disco. Cada letra leva a
     MARCA da importação de que veio; quando o líder importa de novo, a marca
     muda e a cópia velha deixa de valer.
   - **Com cópia, o banco atualiza em segundo plano e a falha dele não é erro.**
     `carregarIndice` devolve na hora o que o aparelho tem. Só espera o banco
     quando não há cópia, ou quando o índice já estava na memória e venceu (os 20
     minutos de sempre) — a semântica de antes, que os testes antigos protegem.
   - **Cifra: cópia vale 15 minutos** (`ArranjosLocais.validade`). Antes, TODA
     abertura de música lia o arranjo no banco (uma leitura), mesmo com a cifra já
     na tela. Dentro do prazo a cópia basta; depois, o banco é consultado em
     segundo plano — e uma cifra corrigida por outro líder chega na abertura
     seguinte.
   - **A resposta do banco só substitui o que está na tela se ele de fato
     respondeu** (`lerArranjoDoServidor` devolve `ok`): `getArrangement` devolvia
     nulo para "esta música não tem cifra" e para "não consegui perguntar", e quem
     trata os dois igual apaga da tela uma cifra que existe só porque o sinal caiu.
6. **Preparação em segundo plano, com ORÇAMENTO** (`PreparoOffline`). Ver "A conta
   das leituras" — é onde o plano grátis aperta. Roda 8 s depois de o banco ligar e
   de novo aos 60 s; é seguro repetir. Ordem: cifras do repertório (uma leitura
   cada; "não tem cifra" também é resposta guardada), índice de cada hinário, letras
   dos hinos em páginas de 50 por número, hinário por hinário na ordem que a pessoa
   escolheu, e a Bíblia (um arquivo, **não passa pelo banco**, então não gasta
   leitura).
7. **Áudios do chat** só baixam quando a pessoa toca; depois ficam no aparelho com
   **limite de 12 MB**, soltando o que foi ouvido há mais tempo (`planejarDespejo`,
   pura). Áudio maior que o limite inteiro NÃO esvazia o cache: não se guarda.
8. **O aparelho apagou os dados do site** (o iPhone faz isso quando falta espaço).
   O app deixa DUAS marcas em lugares que o navegador guarda separados
   (`localStorage` e IndexedDB) e confere ao abrir: as duas → tudo certo; nenhuma
   → primeira vez; **só uma → apagaram um dos lugares**. Aí o app esquece o que é
   DERIVADO (cota do dia, progresso, cifras, hinos, cópia, áudios) e baixa de novo
   aos poucos, sem erro e sem pedir nada. **A fila de envio e os recados NUNCA são
   tocados**: o que a pessoa fez e não chegou ao banco é dela. O app também pede
   `navigator.storage.persist()`.
   - **O limite que nenhum código esconde:** se o navegador apagar TUDO, a sessão
     do Firebase vai junto (mora no mesmo IndexedDB), e a pessoa precisa entrar de
     novo — uma vez. Provado: apagado tudo, o app abre na tela de entrar, sem erro,
     e entrando os dados voltam sozinhos. Pedir a senha não é "pedir algo por
     causa do apagamento": é a conta que se foi.
9. **A faixa de rede só fala quando faz diferença** (`textoDaFaixa`, pura): nada
   com internet e nada pendente; nada nos primeiros 10 s sem internet (elevador,
   troca de wi-fi); "Sem internet. O app está mostrando o que já baixou" depois
   disso; "Atualizado há X" só se os dados passam de 30 min; "Enviando N
   alterações…" só se uma ação demora mais de 5 s COM internet. **Ela empurra o
   conteúdo para baixo em vez de flutuar**: o rodapé do chat é o campo de texto, e
   uma pílula flutuando o cobriria. **A árvore tem a mesma forma com e sem faixa**:
   se o filho mudasse de lugar quando ela aparece, a aba seria reconstruída e a
   busca digitada se perderia por causa de um elevador.
   - "Atualizado há X" parte da **última vez que o BANCO respondeu de verdade**
     (snapshot que não veio do cache — por isso `includeMetadataChanges: true`),
     e com internet e uma escuta aberta ela é empurrada para agora a cada minuto.

#### Decisões que tomei sozinho (e por quê)

- **Fila própria só onde o Firestore não dá conta.** Mensagem de texto e
  preferências pessoais (tom, anotação, favoritos) ficam na fila do SDK, com
  espera de 2–4 s e SEM `await` no servidor. Duplicar a fila para elas criaria
  dois lugares que discordam.
- **Mensagem de voz NÃO espera na fila.** Pesa até 800 KB, e guardá-la à espera de
  sinal faria a pessoa achar que foi enviada — e chegar horas depois, fora de hora.
- **Mensagem que chega tarde NÃO dispara aviso**: o Worker só avisa se foi
  escrita há menos de 2 minutos (a trava contra reavisar mensagem velha), e está
  certa: ninguém quer o "oi" de uma hora atrás. Vale também para a presença
  confirmada sem sinal: o líder só é avisado se ela chegar em 2 minutos.
- **"Primeiro a chegar ao banco vence"** em vez de mesclar texto: letra e cifra
  são texto corrido, e mesclar dois textos editados por pessoas diferentes
  produz um terceiro texto que ninguém escreveu.
- **Cota diária de preparação: 250 leituras por aparelho — e ela se CALA em dia
  movimentado** (4+ aberturas do app no dia). **[Mudou em 21/11/2026: 150 e a
  3ª abertura — ver "Orçamento de leituras".]** 250 é o equivalente a mais UMA abertura
  fria por aparelho; num domingo com seis, 30 pessoas já passam de 43 mil só
  abrindo, e somar 7.500 estouraria os 50 mil. A trava de dia movimentado entrou
  DEPOIS da prova em navegador e é coberta por teste de unidade (e mutação), não
  pela prova. Ver a conta abaixo.
- **A cópia de uma cifra vale 15 minutos**, não "para sempre": cifra errada no
  domingo é o erro mais caro deste app.
- **Editar música parte da música COMO ESTÁ AGORA** (`_viva`), não da cópia de
  quando a tela abriu: com a fila, a conta de "o que mudei" seria feita contra o
  valor errado e desfaria, de carona, o que outra pessoa mudou.
- **Sair da conta descarta a fila**, com aviso antes.
- **A mensagem recusada tarde some da tela e volta como recado com o texto**:
  deixá-la na tela como "enviada" seria mentir; sumir sem recado, também.

#### Armadilhas desta rodada (o que custou caro)

- **`Firebase.apps` LANÇA na web** antes de o plugin ligar ("Null check operator
  used on a null value"). A primeira versão de "tentar ligar de novo" perguntava
  a ele se o app já existia — e o app ficou sem banco, em silêncio, em toda
  abertura. Os testes de unidade passavam (não têm Firebase); **quem achou foi a
  medição com o app de verdade**: 0 documentos entregues numa abertura que
  devia entregar 238. Agora guarda-se o próprio resultado de `initializeApp`
  (`_appDoFirebaseCriado`) e se trata `duplicate-app`.
- **O service worker NÃO guardava o SDK do Firebase** (ver "Como é feito", 2).
  Sem rede, o SDK não carregava, `initializeApp` lançava, e a abertura virava a
  tela de "falta configurar". Só apareceu desenhando a prova de abrir o app com a
  rede cortada.
- **O emulador do Firestore IGNORA o `resumeToken`.** O app mandou o token em
  todas as aberturas "quentes" (6 e 11 pedidos com ele) e o emulador entregou
  os 221 documentos mesmo assim. Então **a abertura quente NÃO é medível por ele**:
  o zero dela, em produção, vem da regra de 30 minutos do Firebase (documentada),
  não de uma medida minha. O que se mediu foi o que dá: quantos documentos uma
  consulta nova entrega (= o custo de cada abertura depois de 30 min parado).
  **Isto também corrige a rodada anterior**: lá escrevi "medido: 202 → zero" a
  partir do que o SDK reporta ao app (`docChanges` vazio depois da resposta do
  servidor), que não distingue "o servidor mandou só o que mudou" de "mandou
  tudo e o SDK comparou". O número de produção continua valendo pela regra, não
  pela medida.
- **Os scripts de medição não terminavam**: o proxy e o servidor deixam conexões
  abertas, o processo não sai, e uma sequência de medições esperava o primeiro
  para sempre — enquanto as execuções seguintes disputavam a mesma porta do proxy.
  Os números dessa fase foram descartados e refeitos, uma instância de cada vez.
  Todo script de medição agora termina com `process.exit`.
- **Estado estático entre testes.** `Armazem` (e a cópia do hinário nele) é
  estático: um teste que lê um hino deixava o hino para o teste seguinte, e 15
  testes antigos reprovaram por isso. Todo teste que mexe nele começa com
  `setUp(Armazem.esvaziar)`.
- **Um teste de fila reprovou por ordem de microssegundos**: `enfileirar`
  devolvia o resultado ANTES de a fila notificar, então a tela ainda mostrava a
  presença marcada. Quem espera só é liberado depois de salvar e notificar.
- **Mutação que sobreviveu**: tirar `indice.remove(id)` do cache de áudio não
  reprovava nada, porque o teste regravava um áudio sem outro mais antigo ao lado.
  O teste agora regrava com um terceiro que seria despejado à toa.
- **`getArrangement` devolvia nulo para duas coisas** ("não tem cifra" e "não
  consegui perguntar"): o mesmo erro de `lerDoc`, já registrado. Agora
  `lerArranjoDoServidor` devolve `ok`.
- **O Início dizia "nada pendente" com um recado de edição perdida na tela**:
  os recados não vêm de um Provider, e a linha não os escutava.

- **A ordem salva dos hinários é VAZIA por padrão.** A preparação a usava direto
  e nunca baixou um hino — o orçamento parava nas cifras, sem erro. Os testes
  passavam listas explícitas. Foi a medição no navegador que mostrou
  (`PreparoOffline.idsDosHinarios`, com teste do caso vazio).
- **Vazio vindo do CACHE não é resposta** (`ignorarVazioDoCache`). Sem rede e com o
  cache do Firestore vazio, a primeira notificação é uma lista vazia marcada
  `fromCache` — e é a única. Tratada como verdade, apagava os cultos restaurados do
  aparelho ("Nenhum culto marcado") e, 2 s depois, regravava a cópia vazia por cima
  da boa. Cultos, músicas, conversa e pessoas. Só o SERVIDOR diz "não há nada".
- **O service worker guardava a resposta de QUALQUER navegação no lugar do
  `index.html`.** Abrir uma imagem do escopo fazia o app abrir como imagem, para
  sempre (o cache vem antes da rede). Só resposta HTML atualiza.
- **O motor do Flutter derruba a página quando se toca com a semântica ligada**
  (com mouse, com toque e com evento de DOM — os três). O roteiro de prova TOCA por
  coordenadas e só no fim liga a semântica para LER. As coordenadas são as do app a
  390 px; uma tela que mude de lugar reprova o cenário e deixa a foto.
- **O CI da rodada passada estava VERMELHO e ninguém viu** (5 testes: abrir_ao_lado,
  campo_multilinha, letra_em_tela_larga, projetar_tela, responsivo). Passavam aqui e
  no Mac; no Flutter 3.50.0 exato da CI o aviso "fontsChange" que o motor manda ao
  carregar a fonte da cifra chega depois do fim do teste ("An animation is still
  running even after the widget tree was disposed"). Conserto: `FonteMono.desligada`
  + `test/flutter_test_config.dart`. **Não foi possível rodar o Flutter exato da CI
  aqui: só a CI confirma.** Quem olha o verde precisa olhar o CI, não só o
  `publicar.sh`.
- **A trava do tamanho passa do limite com esta rodada**: +71.659 bytes (3.844.913 →
  3.916.572, mesmo Flutter) dão ~4.115.673 na CI (deslocamento medido de ~199 KB), 11 KB
  acima do limite de 4.104.004. A base dos DOIS workflows subiu para 4.115.673 —
  **uma estimativa; vale o que a CI imprimir.** Ainda: **os workflows do meu clone
  estavam desatualizados** (BASE 3.868.219 e 3.610.328, enquanto o repositório
  publicado tem 4.001.604 nos dois), porque o Mac editou a base por fora. O patch dos
  workflows foi montado contra o conteúdo do repositório publicado, não contra o meu
  clone, e a aplicação foi provada num repositório de teste com deslocamento de
  linhas.

#### A conta das leituras (plano grátis: 50 mil por dia)

O que se MEDIU, com um proxy entre o app e o emulador que conta os documentos
entregues (`ferramentas/medir/medir_leituras.mjs`; o app é compilado com
`--dart-define=PORTA_FIRESTORE=8081`):

| | antes | depois |
|---|---|---|
| Abertura fria (entrar e ver o Início): documentos entregues | 238 | 238 |
| Abertura "quente" no emulador | 221 | 221 |
| Abrir uma música (cifra) | 1 leitura por abertura | 0 a 1 (nenhuma por 15 min) |
| Preparação, dia 1 | 0 | 250 (limite 250) |
| Preparação, dia 2 | 0 | 250 (limite 250) |

**O 221 "quente" NÃO é o custo de produção.** O app mandou o `resumeToken` em
todas as aberturas quentes e o emulador devolveu tudo de novo — ele não
implementa a regra. Em produção, escuta religada em menos de 30 minutos só é
cobrada pelo que MUDOU (regra documentada do Firebase, não medida aqui). O que
a medida dá é o custo de uma consulta NOVA: 238 documentos, que é o
que cada abertura depois de 30 min parado custa.

**A conta por dia, para 30 pessoas** (aberturas frias × 238 + músicas
abertas + preparação), contra os 50 mil:

| Cada pessoa por dia | antes | depois, 1ª semana | depois, regime |
|---|---|---|---|
| 1 abertura fria, 5 músicas | 7.290 (14%) | 14.670 (29%) | 7.170 (14%) |
| 3 aberturas frias, 10 músicas | 21.720 (43%) | 29.010 (58%) | 21.510 (43%) |
| 6 aberturas frias (domingo), 15 músicas | 43.290 (86%) | 42.990 (85%) | 42.990 (85%) |

- **A preparação é o único custo novo, e é limitada**: no máximo 250 por
  aparelho por dia, só enquanto os dois hinários (1.221 documentos) e as cifras
  (uma leitura por música) não estão inteiros — da ordem de uma semana —, e
  depois disso zero. Sem o teto, baixar tudo no primeiro dia seria 30 × ~1.260 =
  ~38 mil leituras só nisso.
- **O que cai**: abrir música deixou de custar uma leitura por abertura.
- **Não está na conta**: o que o chat, os cultos e as confirmações mudam durante
  o dia (os mesmos de antes), e as leituras que a PESSOA provoca de propósito
  (abrir um hino que não foi baixado, "Trazer" as letras).

#### Provas (Chromium com a rede cortada)

`ferramentas/medir/provar_offline.mjs`. **A rede é cortada em TRÊS lugares**: o
servidor do app, o proxy do emulador e os endereços do Google (SDK e login) —
`context.setOffline` só pega a página, e o service worker continuaria enxergando
o servidor. Um teste que passa porque algo respondeu por baixo dos panos não
prova nada. A tela é lida pela árvore de semântica do Flutter; os toques são por
coordenadas, ANTES de ligar a semântica (com ela ligada o motor derruba a página
em qualquer tipo de toque).

- ✔ entrou com internet e o Início tem dados (2531 ms)
- ✔ a preparação guardou as cifras do repertório (42 cifras)
- ✔ a preparação guardou letras de hinos, dentro do orçamento (207 hinos da Harpa, 250 leituras de 250)
- ✔ a Bíblia foi baixada (um arquivo, fora do banco)
- ✔ o SDK do Firebase está guardado no aparelho (3 arquivos) (3 arquivos)
- ✔ abre o app e mostra o Início com dados (1490 ms)
- ✔ o cartão do culto está na tela
- ✔ confirmar presença: fica "Esperando a internet" e NÃO dá erro
- ✔ a confirmação está na fila, guardada no aparelho (1 item(ns))
- ✔ a faixa "Sem internet" aparece (só depois de 10 s)
- ✔ depois de fechar e abrir de novo, a confirmação continua pendente
- ✔ lê uma música com a CIFRA, sem internet (4 ms)
- ✔ abre o hino 77 da Harpa pelo número, sem internet (34 ms)
- ✔ hino que nunca foi baixado: o app diz que falta internet (sem travar)
- ✔ lê Gênesis 1 da Bíblia, sem internet (31 ms)
- ✔ vê a escala dos cultos, sem internet (13 cultos à vista)
- ✔ a presença chegou ao banco sozinha
- ✔ a fila esvaziou (0 item(ns))
- ✔ a faixa de rede sumiu
- ✔ o carimbo "confirmadoEm" foi gravado junto (o aviso ao líder depende dele)
- ✔ apagado o armazém do app: abre sozinho, sem erro e sem pedir nada (2347 ms)
- ✔ e não caiu na tela de entrar
- ✔ o app baixou as cifras de novo por conta própria (42 cifras de volta)
- ✔ as marcas de conferência foram refeitas
- ✔ apagado TUDO (login incluído): o app abre na tela de entrar, sem erro
- ✔ entrando de novo, os dados voltam sozinhos (2492 ms)

**26 de 26**, depois de achar e consertar cinco defeitos que só o navegador mostrou (ver "Armadilhas"). As fotos ficam em `/tmp/provas-offline` (não vão para o repositório: são telas de um banco de teste).

#### Velocidade (o medidor da rodada passada, 3 repetições, mesma máquina e mesmo dia)

| | rodada passada | agora, versão ANTERIOR (mesmo dia) | agora, versão NOVA |
|---|---|---|---|
| *Celular com internet ruim* | | | |
| 1ª abertura — 1ª tela | 20,5 s | 20,4 s | 20,6 s |
| Entrar até o Início com dados | 6,3 s | 6,1 s | 6,0 s |
| Abrir de novo — 1ª tela | 2,7 s | 2,4 s | 2,3 s |
| **Abrir de novo — Início com dados** | 5,4 s | 5,1 s | 4,6 s |
| *Rede e máquina decentes (20 Mbps, 40 ms, CPU sem freio)* | | | |
| Abrir de novo — 1ª tela | 0,8 s | 0,8 s | 0,7 s |
| **Abrir de novo — Início com dados** | 2,0 s | 1,8 s | 1,8 s |

"Versão anterior" é o commit `666697c` recompilado agora, com as mesmas flags: a
coluna "rodada passada" vem dos JSONs de ontem e serve só de referência (a
máquina e o dia mudam).

- **Abrir de novo, Início com dados — celular lento: ~5,1 s → ~4,6 s** (a versão
  anterior, medida hoje; 5,4 s na rodada passada). **Rápido: ~1,84 s → ~1,76 s**
  (1,96 s na rodada passada): continua abaixo de 2 s, com folga maior.
- **O ganho é modesto no celular lento, e a razão é de CPU:** o app agora desenha
  com a cópia do aparelho sem esperar o Firebase, mas ler e decodificar a cópia
  (JSON de 107 cultos, 42 músicas, 16 pessoas, 50 mensagens) também custa, e com o
  processador 4× mais lento isso pesa. O que ficou de graça foi esperar a rede.
- **Primeira abertura (lento): 20,4 s → 20,6 s — PIOROU ~0,27 s (1,3%)**, e nas
  três repetições. A meta era não piorar, e **não foi cumprida à risca**: o código
  cresceu ~72 KB (+ `offline.js`), e isso é baixado antes da primeira tela.
  É pouco, mas é real, e fica dito.
- Entrar até o Início com dados: sem diferença (6,06 s → 5,99 s, dentro do ruído).

#### O que NÃO foi medido

- **O Safari do iPhone**, nada. Tudo foi num Chromium. Não se viu lá: se o service
  worker assume a página a tempo de guardar a Bíblia na preparação; se
  `navigator.storage.persist()` é concedido ao app instalado; quando e como o iOS
  apaga os dados (e se leva o IndexedDB do app e o login juntos, como se supõe);
  como o Firestore se porta com cache persistente no WebKit; e o tempo de
  abertura. **O que o iPhone decide** — abrir o app instalado em modo avião — é a
  prova que falta, e está nos passos da página de entrega.
- A regra dos 30 minutos do Firebase (o emulador a ignora).
- Leituras de produção de um domingo inteiro.
- O que as telas do líder (montar culto, cadastrar música, importar hinário)
  fazem sem internet.
- O CI com o Flutter exato: o conserto dos 5 testes (ver "Armadilhas") só se
  confirma lá.

### Orçamento de leituras (21/11/2026)

Prioridade máxima da rodada: **um domingo movimentado não pode chegar perto das
50 mil leituras grátis por dia.** A conta da rodada anterior dava 85% para 30
pessoas, e o grosso não era a preparação: eram os **238 documentos de cada
abertura fria** — 107 cultos, 50 mensagens, 42 músicas, 16 pessoas, 3 equipes —
relidos inteiros, por pessoa, cada vez que o app voltava depois de mais de 30
minutos. O iPhone mantém o app instalado vivo por dias, então "voltar" acontece
seis vezes num domingo.

**A pergunta que guiou tudo: o que o Início realmente precisa para aparecer?**
Um culto (o próximo), as minhas músicas dele, e duas ou três pendências. Não
precisa de 107 cultos, nem de 50 mensagens, nem do repertório inteiro.

#### O que foi feito (do que mais pesava para o que menos)

1. **Cultos: só 2 dias atrás até 28 à frente ficam sempre ligados** (~21
   documentos, eram 107). O resto é lido **por necessidade**: o mês que o
   calendário mostra, e os 60 dias de histórico só quando o líder abre "Escolher
   músicas" ou a ordem "mais tocados" (`ScaleProvider.garantirMes` /
   `garantirHistorico`). Quem precisa do futuro inteiro (tirar alguém de todos os
   cultos) pede `garantirFuturo` — 90 dias — antes de calcular o que mexer.
2. **Chat: a conversa só é escutada com ele à vista.** O Início conta as não
   lidas por uma consulta agregada (`count()`, 1 leitura por até mil mensagens)
   mais a última mensagem — DUAS leituras, em vez de 50 —, descontando as que eu
   mandei desde a última vez (`LocalStorageService.contarMinhaMensagem`: sem
   isso eu veria "1 mensagem nova" depois de escrever). Sair da aba pára a
   escuta; voltar a recomeça.
3. **Repertório: lido POR NECESSIDADE, e o Início resolve cada música do culto
   pelo id** (`SongsProvider.getSongById` pede a que falta, uma leitura; o texto
   é "Carregando…" enquanto isso, **"Música removida" só depois de o banco
   confirmar que não existe**, e "ainda não baixada" quando não deu para
   perguntar). A lista inteira vem quando a aba Músicas, o cadastro (aviso de
   duplicata), a escolha de músicas do culto, o teclado de hinos ou o painel do
   chat a pedem (`atualizarSeVelho`, prazo de 12 h), e uma vez pela preparação
   num aparelho que nunca a teve. **Isto tira a dependência do TAMANHO do
   repertório:** 42 músicas passam despercebidas, 300 gastavam sozinhas um quinto
   da cota em seis aberturas.
   - **Três músicas soltas não são o repertório.** Músicas buscadas por id vão
     para outra cópia no aparelho (`songs-avulsas`); só a lista inteira vai para
     `songs`, **com a hora da leitura completa, não a de agora** — senão uma
     música cadastrada à mão estenderia o prazo da lista e esconderia por 12 h o
     que OUTRA pessoa cadastrou (`repertorioCompleto` separa as duas coisas).
   - "Música cadastrada por outra pessoa não aparece na lista" tem saída na
     tela: na busca sem resultado, **"Atualizar a lista de músicas"** (custa o
     repertório, e é a pessoa que decide). No culto ela aparece de qualquer
     jeito, porque o culto a resolve pelo id.
4. **Pessoas (nomes): lidas uma vez, prazo de 24 h** (`AuthProvider.prazoDasPessoas`),
   e **equipes e agenda só para o líder** (eram 4 documentos por abertura para
   uma lista que quem não é líder não vê). A única vez que um levita precisa das
   equipes é "Sair do ministério", que agora as lê antes (`AgendaProvider.garantir`).
5. **Preparação: cota 150 por dia** (era 250) **e silêncio a partir da 3ª
   abertura do dia** (era a 4ª) — decisão do dono. E ela não renova mais o
   repertório todo dia: só o baixa se o aparelho nunca o teve.

**O que ficou sempre ligado, e por quê:** a janela curta de cultos (as
confirmações dos outros aparelhos), o próprio cadastro e a lista de pedidos de
entrada do líder. É o que muda durante o dia e alguém precisa ver.

#### O contador: medir em produção, de graça

O emulador **ignora o `resumeToken`**, então a regra dos 30 minutos — a que
decide se voltar ao app custa o resultado inteiro ou só o que mudou — **não é
medível nele**. Em vez de acreditar na documentação do Firebase, o app mede:

- **`ContadorDeLeituras`** conta, na memória de cada aparelho, as leituras que
  provoca, e grava **uma escrita agregada** (`FieldValue.increment`) em
  `usoDiario/{dia}` quando vai para segundo plano e de 15 em 15 minutos (se há
  20+ leituras a gravar). Com 30 pessoas são algumas centenas de escritas por
  dia, de 20 mil grátis, e **nenhuma leitura**.
- **São DUAS contas no mesmo documento**: `leituras` (com a regra: religar dentro
  de 30 min custa só o que mudou) e `leiturasSemRegra` (a pior hipótese: toda
  religação custa o resultado inteiro). **A que ficar mais perto do painel de
  uso do Firebase diz se a regra vale.**
- **O dia é o da COTA, e a cota vira à meia-noite do Pacífico**, não à de
  Brasília (`diaDaCota`, com a virada do horário de verão dos EUA testada): um
  culto de domingo às 21h30 em Brasília ainda é domingo para o Firebase.
- Em `porFonte` fica de onde veio cada leitura (`cultos`, `musicas`, `pessoas`,
  `chat`…), para o próximo "o que mais gasta?" não precisar de nova medição.
- Quem lê esse documento é o modo de economia (uma leitura a cada 10 min por
  aparelho); gravar é de qualquer aprovado, **mas cada gravação é limitada** pela
  regra (nenhum aumento passa de 20 mil; o contador só cresce; a hora é a do
  servidor; id é uma data; ninguém apaga) — um aparelho com defeito, ou alguém
  falando direto com a API, não liga o modo de economia de todo mundo com um
  número absurdo. 15 testes de regra, **cada um provado quebrando a regra de
  propósito.**

- **Provado de ponta a ponta no emulador, com as regras de verdade**: uma
  abertura de levita com cache vazio. O proxy viu chegar **55 documentos
  distintos** (74 entregues); o contador do app gravou `usoDiario/2026-11-21`
  com **54** (cultos 21, pessoas 16, músicas 16 por id, resumo do chat 1) e
  `aberturas: 1`. A diferença de 1 é o que se espera: o app não conta o próprio
  cadastro (1–2 leituras por abertura) e o proxy não vê a contagem agregada do
  chat. `ferramentas/medir/medir_leituras.mjs` repete isso (o app é posto em
  segundo plano, que é o que dispara a gravação) e imprime as duas contas lado a
  lado.

**COMO PROVAR OU DERRUBAR A REGRA DOS 30 MINUTOS** (o dono faz, depois de um dia
de uso com o app novo; leva cinco minutos):

1. Firebase Console → **Firestore Database → aba "Uso"** → escolha o dia → anote
   as **leituras**. (Os dias do console também viram à meia-noite do Pacífico.)
2. Firestore → coleção `usoDiario` → o documento daquele dia (`2026-11-23`):
   anote `leituras` e `leiturasSemRegra`.
3. Compare. **Se o painel ficar perto de `leituras`**: a regra vale, e a
   estimativa serve. **Se ficar perto de `leiturasSemRegra`**: a regra NÃO está
   valendo para este app (cache desligado? segunda aba?) e os 30 minutos são
   mito para nós — a conta de todas as tabelas abaixo deve usar a outra coluna.
   **Se passar de AMBAS**, há leitura que o app não está contando: procure em
   `porFonte` qual fonte parece pequena demais e confira se a leitura dela passa
   pelo contador.
4. Mande os números (painel, `leituras`, `leiturasSemRegra`, `aberturas`) e eu
   atualizo a conta.

**O app não vê a fatura, vê os documentos que chegam.** Isto é estimativa — e
a tela diz "cerca de". Não conta: o próprio cadastro (1–2 por abertura), as
leituras de regra (`get()` dentro de `firestore.rules`, cobradas à parte) e o
que um aparelho antigo (versão sem o contador) lê.

#### A rede de proteção

- **60% (30 mil): amarelo na Saúde do sistema**, só para o líder, com a frase
  "Hoje o app já usou cerca de 31,2 mil das 50 mil leituras grátis (62%)…".
  **Não acende o aviso vermelho do Início**: o app já se segura sozinho, e o
  líder só tem o que saber.
- **80% (40 mil): modo de economia automático** (`ModoEconomia`). Suspende o que
  NÃO é essencial até amanhã — a preparação em segundo plano, a atualização
  automática do repertório e das pessoas, o histórico de cultos (conforto).
  **Continua**: a escala de agora, a cifra que a pessoa abriu, o chat,
  confirmar presença, e a leitura por id de música de culto. Ninguém vê isto
  na tela, exceto o líder na Saúde do sistema: um app que se segura e conta
  para todo mundo ensina a ter medo dele.
- **95%: vermelho**, e só aí acende o aviso do Início — é quando a cota acaba
  antes do fim do dia e o app INTEIRO deixaria de ler.
- **O uso de ontem não vale hoje**: um aparelho que ficou aberto a noite toda
  não pode continuar em modo de economia com o dia já zerado.
- **Falha ao ler o contador é "não sei", nunca vermelho** (o wi-fi da igreja não
  é um banco quebrado).

#### Medido, com o mesmo proxy (30 e 60 pessoas)

O proxy (`ferramentas/medir/proxy_leituras.mjs`) agora também diz **de onde**
vêm os documentos e quantos são **distintos por consulta**. Isso importou: o
emulador às vezes entrega o resultado de uma consulta **duas vezes**, 270 ms
depois, com um só pedido do app (conferido: um único `addTarget` para a lista de
pessoas), e só na abertura com cache vazio. **O número de 238 da rodada
anterior já tinha essa duplicação dentro** (219 distintos), e é medido aqui do
mesmo jeito para a comparação ser justa. Ver os dois é a honestidade possível:
o que o app pede é o "distintos"; o que o emulador mandou é o outro; **o que o
Firebase cobra fica entre os dois e só o contador de produção diz**.

Banco do tamanho do ministério (16 pessoas, 42 músicas, 107 cultos, 50 mensagens,
3 equipes), mesmas flags, mesmo dia, versão anterior (`f2db2c7`) recompilada:

| Uma abertura | antes | depois (líder) | depois (levita) |
|---|---|---|---|
| **Aparelho novo / cache vazio** ("fria") | 238 (219 distintos) | 79 (58) | 74 (55) |
| **Primeira do dia** (cópias de nomes e repertório vencidas) | 221 | 46 (42) | 41 (39) |
| **Depois de 30 min, com cópia fresca** (o "vaivém" de um domingo) | 221 | 30 (26) | 25 (23) |

De onde vêm (depois, levita, vaivém): cultos 21, pessoas 2 (o próprio
cadastro), chat 1. A primeira do dia soma 16 pessoas. A de aparelho novo soma
as músicas dos próximos cultos, buscadas pelo id (16).

**A meta de "abertura fria abaixo de 40", com franqueza:**
- **O vaivém (cada volta depois de 30 min): 238 → 25–30. Atingida, com folga.**
  É a abertura que se repete, e a que a conta de 238 × 6 descrevia.
- **A primeira do dia: 41 (levita) a 46 (líder). NÃO atinge 40 à risca.** O piso
  é 21 cultos + 16 pessoas (que se renovam a cada 24 h) + 3 a 5 de cadastro,
  equipe e chat. Para ficar abaixo de 40 teria de encurtar a janela de cultos
  (de 28 para 14 dias, tirando ~10) ou deixar os nomes por 72 h — e as duas têm
  preço que não valia: janela curta quebra o "próximo culto" quando a escala
  tem um buraco, e nome velho deixa quem saiu do ministério contando como "não
  leu" nos tiques azuis do chat. **O melhor número possível sem esse preço é o
  que está aqui.**
- **Aparelho novo: 74–79.** Piso de 43 sem nenhuma música (21 cultos + 17
  pessoas + 3 equipes + 1 mensagem + conta). Acontece UMA vez por aparelho (e
  de novo se o iPhone apagar os dados do site).

**O dia de um ministério** — leituras por dia e % das 50 mil. As colunas
"antes" usam os 238 por abertura que o dono cita (os 85% dele); "depois" usa os
números medidos acima (os "entregues", que são o teto), 10% de líderes, mais
**o que a rodada acrescentou**: uma visita ao chat custa agora a conversa
(50), porque a escuta só existe com ele à vista, e a aba Músicas custa o
repertório (42) uma vez a cada 12 h para quem a abre.

| 30 pessoas | antes | depois, 1ª semana | depois, regime |
|---|---|---|---|
| 1 abertura, 1 visita ao chat, 5 músicas | 14.940 (30%) | 7.545 (15%) | 3.045 (6%) |
| 3 aberturas, 2 visitas ao chat, 10 músicas | 29.520 (59%) | 11.127 (22%) | 6.627 (13%) |
| **Domingo: 6 aberturas, 3 chats (2 cheios), 15 músicas** | 43.890 (88%) | 9.540 (19%) | **9.540 (19%)** |
| Domingo, PIOR CASO: 6 aberturas, 3 chats cheios, todos na aba Músicas | 44.490 (89%) | 12.480 (25%) | 12.480 (25%) |

| 60 pessoas | antes | depois, 1ª semana | depois, regime |
|---|---|---|---|
| 1 abertura, 1 visita ao chat, 5 músicas | 29.880 (60%) | 15.090 (30%) | 6.090 (12%) |
| 3 aberturas, 2 visitas ao chat, 10 músicas | 59.040 (**118%**) | 22.254 (45%) | 13.254 (27%) |
| **Domingo: 6 aberturas, 3 chats (2 cheios), 15 músicas** | 87.780 (**176%**) | 19.080 (38%) | **19.080 (38%)** |
| Domingo, PIOR CASO | 88.980 (**178%**) | 24.960 (50%) | 24.960 (50%) |

- **A meta de "domingo de 30 pessoas × 6 aberturas abaixo de 25%": atingida no
  caso realista (19%), e no PIOR caso fica em 24,96% — em cima da linha, sem
  margem.** Só as 180 aberturas custam ~10% (5.070 de 50.000); o resto é chat,
  aba Músicas e cifras. O pior caso supõe que TODOS abram a aba Músicas e que as
  seis aberturas e os três chats estejam sempre a mais de 30 minutos um do outro
  — e o modo de economia, em 80%, existe para o dia em que algo assim aconteça.
- **Com 60 pessoas** a versão anterior estourava o plano num dia comum (118%) e
  no domingo passava do dobro; a de agora fica em 27–38% (50% no pior caso).
  Cabe, sem folga para crescer mais que isso.
- **Estas contas valem para 42 músicas. Com 300, a aba Músicas custa 300 e o
  pior caso de 30 pessoas passa de 30%** — o repertório "por necessidade" é o que
  impede isso de aparecer na abertura, mas quem abre a lista ainda a paga.
- **Tudo é estimativa a partir de um emulador.** A de produção sai do
  `usoDiario`, pelo passo a passo acima.

#### O que NÃO foi feito, e por quê

- **Encurtar a janela de cultos para 14 dias nos levitas.** Tiraria ~10
  documentos de cada abertura, mas a agenda fixa e o "próximo culto" assumem a
  janela de 4 semanas, e um buraco na escala viraria "nenhum culto marcado" —
  uma frase falsa. Fica como a próxima alavanca, com a regra "se não há culto
  futuro nos 14 dias, abre a janela até 28".
- **Atualização incremental do repertório por campo `atualizadoEm`.** Exigiria
  gravar o campo em todo caminho que escreve música (cadastro, edição, fila,
  arquivar, colar cifra), mudar a regra, e preencher o campo nas músicas que já
  existem — e o app não tem como fazer esse preenchimento sem chave de
  administrador. A leitura por necessidade tirou o custo da abertura sem isso.
- **Documento-resumo "próximos cultos" mantido pelo Worker.** Trocaria 21
  leituras por 1, mas faria o Worker reescrever o resumo a cada confirmação de
  presença (escrita por culto, por pessoa), e o resumo ficaria atrás da verdade
  durante o culto, que é quando mais importa. Avaliado e descartado.
- **A segunda abertura de uma consulta com `resumeToken` no emulador**: continua
  não medível lá (ver acima).
- **Chat com menos de 50 mensagens na primeira carga.** A tela não tem "ver
  mensagens anteriores"; cortar esconderia conversa sem aviso.

#### Armadilhas desta rodada

- **O número do emulador mentiu em duas direções.** Em uma, duplicava a lista de
  pessoas só na abertura com cache vazio (e só alguns builds, por causa de
  tempo); na outra, não implementa a regra dos 30 minutos. Daí o contador de
  produção, e daí o proxy reportar "distintos".
- **`getSongById` agora tem efeito colateral** (pede ao banco) e é chamado de
  dentro de `build`. Por isso o pedido é agendado (`scheduleMicrotask`) e o aviso
  só sai depois que o banco responde — notificar de dentro do `build` é erro do
  Flutter. Nas telas de teste, `carregarParaTeste` desliga o banco (`_semBanco`),
  senão cada tela tentaria falar com um Firestore que não existe.
- **Um teste de "abrir ao lado" estava frágil por data**: ele procurava "Aliança
  eterna" na sugestão do dia, e a sugestão é sorteada pela data. Passava num dia
  e falhava no seguinte — **também na CI**, num dia qualquer. Agora lê o nome da
  primeira sugestão.
- **A lista de pessoas ainda não conhece quem se cadastrou depois.** Em culto
  gerado pela agenda fixa o nome vem do cadastro, e quem entrou há menos de 24 h
  aparece como "Alguém" nos aparelhos que ainda não renovaram. Conhecido; o
  líder que aprova vê o nome na hora, porque a tela Membros escuta.
- **`atualizarPessoasSeVelho` e `atualizarSeVelho` não renovam em modo de
  economia** — a menos que a tela esteja vazia, ou que a própria pessoa peça.

## O que não existe (e o relatório de auditoria aponta)

Busca de música na internet, anexo de imagem no chat, PDF da escala, foto de
perfil, e transformar uma mensagem do chat em decisão da agenda.

E **o líder não define a senha de ninguém** — não por falta de código, mas
porque exigiria uma chave de administrador cujo escopo menor possível é
"entrar como qualquer pessoa do ministério". Ver "Recuperar a senha".
