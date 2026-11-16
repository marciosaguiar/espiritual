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
flutter test                   # 203 testes
```

Testes das regras de segurança (sobem o emulador do Firestore; exigem Node e Java):

```bash
cd test_regras && npm install && npm test    # 171 testes
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
171 testes passem com as duas versões juntas. O `.npmrc` dá a licença; sem ele
só com `npm install --legacy-peer-deps`.

O mini-servidor dos avisos tem testes próprios, que não precisam de emulador
nem de Flutter:

```bash
node --test worker/teste/*.mjs               # 30 testes
```

## Estado atual

Funciona e está testado. O que **ainda falta para o app rodar de verdade** é
configuração, não código:

1. Criar o projeto no Firebase (Firestore em produção + Authentication por
   e-mail/senha + plano Blaze com orçamento).
2. `flutterfire configure` — preenche `lib/firebase_options.dart` e os
   arquivos nativos, que hoje têm valores de exemplo.
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
2. ~~**Aviso de mensagem nova** no chat~~ — **feito**, por Worker da
   Cloudflare em vez de Cloud Function (ver "Avisos do chat"). Os outros
   gatilhos combinados ficam para depois, e agora são pequenos: escalado,
   lembrete da véspera e "novo pedido de entrada" para o líder são a mesma
   cifra e o mesmo leque de envio, com outro gatilho.
3. **Reações e "visto por"** no chat.
4. **Líder redefine senha de um membro.** Só com o Admin SDK, em Cloud
   Function — o Firebase não deixa um app trocar a senha de outra pessoa.
   Fica pequeno depois que as Functions existirem.

Quando as Functions existirem, mover a função do usuário para um *custom
claim* no token: as regras passam a ler `request.auth.token.role` e somem as
leituras extras que hoje cada `get()` dentro da regra cobra.

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

## O que não existe (e o relatório de auditoria aponta)

Busca de música na internet, anexo de imagem no chat, PDF da escala, foto de
perfil, transformar uma mensagem do chat em decisão da agenda, reações e
"visto por" no chat, e aviso de escalado / lembrete da véspera / "novo pedido
de entrada" (o mecanismo já existe; falta o gatilho).
