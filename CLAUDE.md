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
flutter test                   # 323 testes
```

Testes das regras de segurança (sobem o emulador do Firestore; exigem Node e Java):

```bash
cd test_regras && npm install && npm test    # 236 testes
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
node --test worker/teste/*.mjs               # 48 testes
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
2. ~~**Avisos**: mensagem nova, "você foi escalado" e lembrete da
   véspera~~ — **feito**, por Worker da Cloudflare em vez de Cloud Function
   (ver "Avisos do chat" e "Avisos da escala"). Falta só "novo pedido de
   entrada" para o líder, que é o mesmo leque de envio com outro gatilho.
3. ~~**Rolagem sincronizada no culto**~~ — **feito** (ver "Modo Culto ao
   vivo").
4. ~~**Reações e "visto por"** no chat~~ — **feito**, com responder citando
   e @menção (ver "Reações, citação e visto por").
5. **Líder redefine senha de um membro.** Só com o Admin SDK, em Cloud
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

## O que não existe (e o relatório de auditoria aponta)

Busca de música na internet, anexo de imagem no chat, PDF da escala, foto de
perfil, transformar uma mensagem do chat em decisão da agenda, e aviso de
"novo pedido de entrada" para o líder (o mecanismo já existe; falta o
gatilho).
