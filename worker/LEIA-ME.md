# O mini-servidor dos avisos

Isto é o que faz a notificação de mensagem nova chegar **com o app fechado**.

Aviso com o app fechado precisa de alguém de pé quando ninguém está olhando.
No Firebase isso seria uma Cloud Function, que exige o plano Blaze — cartão de
crédito. Então é um Worker da Cloudflare, no plano gratuito: **100 mil pedidos
por dia**, e um ministério usa algumas centenas por mês.

## O que ele faz, e o que não faz

Ele **não** recebe mensagem nem grava nada no chat. Quem grava é o app, com as
regras do Firestore valendo. O Worker só:

1. confere o ID token do Firebase de quem pediu, com as chaves públicas do
   Google;
2. lê no Firestore que a pessoa está aprovada, e que a mensagem existe, é
   dela e acabou de ser escrita;
3. manda o aviso cifrado para cada aparelho inscrito, menos o do autor.

Se o Worker cair, o chat continua inteiro. Só não chega notificação.

Ele entra no Firestore **como um líder comum, com e-mail e senha** — o mesmo
robô da faxina do chat. Não com chave de conta de serviço: aquela chave ignora
todas as regras do banco e, se vazar, dá acesso a tudo. A senha do robô se
troca e acabou.

## As rotas

```
GET  /            diz se está de pé e o que falta configurar
GET  /saude       diz se o ROBÔ DELE entra e está aprovado
POST /avisar      mensagem nova no chat (chamado pelo app)
POST /pedido      "novo pedido de entrada" (app, por quem está pendente)
POST /escalado    "você foi escalado" (app, só líder)
POST /confirmou   "alguém confirmou ou desmarcou" (app, avisa os líderes)
POST /vespera     lembrete da véspera (job do GitHub, só líder)
POST /agenda      cria os cultos da agenda fixa (job do GitHub, só líder)
POST /testar      avisa só os aparelhos de quem pediu
```

Nenhuma delas aceita nada sem o ID token do Firebase verificado, com uma
exceção explicada no código: `/pedido` atende quem ainda está `pendente`,
porque é justamente desse cadastro que o líder precisa saber. `/escalado`,
`/vespera`, `/agenda` e `/confirmou` exigem que a pessoa seja **líder** — e os
robôs são líderes comuns.

## Quando algo não funciona, abra `/saude`

A raiz (`/`) diz se os segredos estão **preenchidos**. `/saude` diz se eles
**funcionam**, e a diferença custou duas noites de rotina falhando: a raiz
respondia `{"configurado":true,"falta":[]}` enquanto toda chamada era
recusada, porque ter `ROBO_EMAIL` preenchido não é o mesmo que o robô
conseguir entrar, e conseguir entrar não é o mesmo que o cadastro dele estar
aprovado no banco.

Abra `https://<seu-worker>.workers.dev/saude` no navegador. Não precisa de
login, e não devolve nada sigiloso — só se o robô entra e qual é a função do
cadastro **dele**:

| O que vem | O que fazer |
| --- | --- |
| `"robo":"entra e está líder"` | nada; o problema é outro |
| `"entra":false` | `ROBO_EMAIL` / `ROBO_SENHA` na Cloudflare |
| `não tem acesso ao banco` | o cadastro do robô não está aprovado, ou `FIREBASE_API_KEY` e `FIREBASE_PROJECT_ID` são de projetos diferentes |
| `NÃO TEM cadastro em users` | a conta foi criada direto no console do Firebase e nunca passou pelo cadastro do app — ela não aparece em Membros, então ninguém consegue aprová-la |
| `o cadastro dele está "levita"` | promova o robô a líder em Membros |

## SÃO DUAS CONTAS DE ROBÔ, e isso engana

- **`ROBO_EMAIL` / `ROBO_SENHA`, na Cloudflare:** com quem o **Worker** fala
  com o banco. Toda leitura que ele faz é com esta conta — inclusive a
  leitura do cadastro de *quem chamou*. Se esta conta não estiver aprovada
  como líder, **tudo** é recusado, mesmo que quem chamou seja líder.
- **`FAXINA_EMAIL` / `FAXINA_SENHA`, nos segredos do GitHub:** com quem os
  **jobs** (faxina do chat, lembrete da véspera, agenda) se identificam.

Podem ser a mesma conta, e é mais simples que sejam. Quando são diferentes, o
engano é cruel: a tela mostra 👑 Líder para a conta que você aprovou, e o
Worker é recusado por causa da outra.

**O lembrete da véspera não precisa de segredo novo.** O job do GitHub entra
com a conta do robô (`FAXINA_EMAIL` / `FAXINA_SENHA`, que já existem) e manda
o ID token; o endereço do Worker sai de `lib/core/constants/avisos_config.dart`,
que está no repositório. Um segredo compartilhado entre o GitHub e a
Cloudflare seria uma coisa a mais para vazar, girar e esquecer.

Para disparar o lembrete à mão: GitHub → Actions → "Lembrete da véspera" →
Run workflow. Ele tem trava de uma vez por dia, então rodar duas vezes não
manda dois lembretes — para forçar, o corpo aceita `{"forcar": true}`.

## Passo a passo, do zero

Tudo isto é de graça e não pede cartão. Leva uns 20 minutos na primeira vez.

### 1. Gerar o par de chaves do VAPID

No Terminal do seu Mac, na pasta do projeto:

```bash
npx web-push generate-vapid-keys
```

Sai algo assim:

```
Public Key:
BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U
Private Key:
UUxI4O8-FbRouAevSmBQ6o18hgE4nSG3qwvJTfKc-ls
```

Guarde as duas. A **pública** vai no app (é pública mesmo, viaja em todo
aviso). A **privada** só na Cloudflare, e em nenhum outro lugar — quem a tiver
manda notificação para o ministério inteiro.

### 2. Criar a conta na Cloudflare

1. Vá em `dash.cloudflare.com/sign-up`.
2. E-mail e senha. Confirme pelo e-mail que chega.
3. Não precisa escolher plano, não precisa cadastrar domínio, não pede cartão.
   Se ele insistir em escolher um produto, escolha **Workers & Pages**.

### 3. Publicar o Worker

No Terminal, na pasta do projeto:

```bash
cd worker
npm install
npx wrangler login      # abre o navegador para você autorizar
npx wrangler deploy
```

No fim ele imprime o endereço, assim:

```
https://levitasync-avisos.SEU-USUARIO.workers.dev
```

**Guarde esse endereço.** É a primeira das duas linhas que vão no app.

### 4. Cadastrar os sete segredos

Um comando por segredo. Cada um pergunta o valor e você cola — o valor não
fica no histórico do Terminal nem no repositório.

```bash
npx wrangler secret put VAPID_PUBLIC          # a Public Key do passo 1
npx wrangler secret put VAPID_PRIVATE         # a Private Key do passo 1
npx wrangler secret put VAPID_ASSUNTO         # mailto:seu-email@exemplo.com
npx wrangler secret put FIREBASE_API_KEY      # a mesma de firebase_options.dart
npx wrangler secret put FIREBASE_PROJECT_ID   # o id do projeto no Firebase
npx wrangler secret put ROBO_EMAIL            # o e-mail do robô líder
npx wrangler secret put ROBO_SENHA            # a senha do robô líder
```

O **robô líder** é uma conta comum do app, criada pelo cadastro normal e
promovida a `admin` no console do Firebase. Pode ser a mesma que a faxina do
chat já usa (`FAXINA_EMAIL` / `FAXINA_SENHA` nos segredos do GitHub). Se ainda
não existe: cadastre `robo@seu-dominio` pelo app, e no console do Firebase vá
em Firestore → `users` → o documento dele → `role` → `admin`.

Para conferir que ficou de pé, abra o endereço do Worker no navegador. Ele
responde algo como:

```json
{ "app": "LevitaSync — avisos do chat", "configurado": true, "falta": [] }
```

Se `falta` tiver nomes, é segredo que não entrou.

### 5. Colar as duas linhas no app

Em `lib/core/constants/avisos_config.dart`:

```dart
static const String worker = 'https://levitasync-avisos.SEU-USUARIO.workers.dev';
static const String chavePublica = 'BEl62iUYgUivxIkv...';   // a Public Key
```

Enquanto essas duas linhas forem as de exemplo, o app **não** mostra o botão
de ativar avisos — ele explica o que falta, em vez de dar erro de rede.

Depois: `git commit`, `git push`, e o GitHub Pages publica.

### 6. Publicar as regras do banco

A coleção `pushSubs` é nova, e sem as regras no ar ninguém consegue se
inscrever:

```bash
firebase deploy --only firestore:rules
```

### 7. Ativar no celular

No app: **Perfil → Avisos do chat → Ativar avisos**, e aceite a pergunta do
navegador.

No **iPhone**, o aviso só funciona com o app instalado na tela de início. Se
não estiver, em vez do botão aparece o passo a passo de instalar. Isso é do
iOS, não do app.

Depois toque em **Testar aviso**. Se a notificação aparecer, está pronto.

## Mexer depois

```bash
npm test             # os 30 testes, sem precisar publicar
npx wrangler deploy  # publica de novo
npx wrangler tail    # vê os erros ao vivo, enquanto você testa no celular
```

`npx wrangler tail` é o que responde "por que não chegou aviso": ele mostra
cada pedido e o motivo da recusa.

## O que o teste prova, e o que não prova

`npm test` faz o papel do aparelho que recebe: gera um par de chaves como o
navegador geraria, pede ao Worker que cifre, e **decifra de volta**. Se o
texto voltar igual, um celular de verdade também abre.

Isso importa porque um erro na cifra **não aparece no envio**: o serviço de
push aceita os bytes, responde 201, o aviso chega ao aparelho e some sem nada
na tela.

O que o teste **não** prova: a permissão do Safari no iPhone, e a entrega de
verdade pelo Google e pela Apple. Isso só o celular na mão diz.
