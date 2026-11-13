# Testes das regras do Firestore

As regras de segurança são a única coisa que separa o banco da internet, e
são escritas numa linguagem que não compila junto com o app: um erro nelas só
aparece quando alguém não consegue entrar. Estes testes rodam as regras no
emulador oficial e conferem cada permissão.

Eles já pegaram um defeito real: o app grava `photoUrl: null` em todo
cadastro, e `null is string` dava falso, o que fazia as regras recusarem
criar conta, editar o próprio perfil e promover um membro.

## Como rodar

Precisa de Node e Java (o emulador é um .jar).

```bash
cd test_regras
npm install
npm test
```

O `emulators:exec` sobe o emulador, roda os testes e derruba tudo no fim.
Nada toca o banco de verdade.

## O que é verificado

- Cadastro: aceita conta nova, recusa quem tenta nascer líder, recusa usar o
  id de outra pessoa, recusa nome curto e recusa trazer `passwordHash`.
- Sem login: não lê usuários, músicas nem o chat.
- Funções: ninguém se autopromove; o líder promove; ninguém apaga conta.
- Músicas e arranjos: levita lê, só líder escreve e só líder apaga.
- Preferências: nem o líder lê a anotação de outra pessoa.
- Escala: o levita só consegue mexer no campo de presença; o resto é do líder.
- Chat: mensagem só em nome próprio, não vazia, e não se edita nem se apaga.
- Coleção sem regra definida fica bloqueada.
