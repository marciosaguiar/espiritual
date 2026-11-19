#!/usr/bin/env bash
#
# Roda tudo o que precisa passar e publica o app.
#
# COMO USAR
#
#   bash ferramentas/publicar.sh
#
# POR QUE ESTE ARQUIVO EXISTE
#
# Já aconteceu de uma entrega ir para o GitHub e a publicação falhar em
# silêncio por dias, com o app no ar parado numa versão antiga. E já
# aconteceu de uma regra do banco quebrada só aparecer quando alguém não
# conseguiu entrar. Os dois casos se evitam rodando as mesmas coisas que a
# CI roda, ANTES de enviar — e é isso que este script faz.
#
# Ele pergunta antes de cada passo que muda algo fora do seu computador.

set -euo pipefail
cd "$(dirname "$0")/.."

perguntar() {
  printf '%s [s/N] ' "$1"
  read -r resposta
  [ "$resposta" = "s" ] || [ "$resposta" = "S" ]
}

echo "═══ 1. Analisar o código ═══"
# A CI falha com qualquer "error"; os "info" e "warning" são aceitos.
if flutter analyze 2>&1 | grep -E '^ *error'; then
  echo
  echo "Tem erro de código. Corrija antes de publicar."
  exit 1
fi
echo "Sem erros."
echo

echo "═══ 2. Testes do app ═══"
flutter test
echo

echo "═══ 3. Testes das rotinas e do servidor de avisos ═══"
node --test worker/teste/*.mjs
node --test web/teste/*.mjs
node --test ferramentas/teste/*.mjs
echo

echo "═══ 4. Testes das regras do banco ═══"
# Precisam de Java e sobem o emulador do Firestore. É o único passo lento.
if perguntar "Rodar os testes das regras? (demora ~1 min, precisa de Java)"; then
  (cd test_regras && npm test)
else
  echo "Pulado. Se você mexeu em firestore.rules, rode antes de publicar:"
  echo "  cd test_regras && npm test"
fi
echo

echo "═══ 5. Enviar para o GitHub ═══"
echo "Ramo: $(git rev-parse --abbrev-ref HEAD)"
git log --oneline origin/HEAD..HEAD 2>/dev/null || git log --oneline -3
echo
if perguntar "Enviar?"; then
  git push
  echo
  echo "Enviado. A publicação do site roda sozinha no GitHub, em alguns"
  echo "minutos. Confira em Actions se ficou verde."
else
  echo "Nada enviado."
  exit 0
fi
echo

echo "═══ 6. Regras do banco ═══"
echo "Só é preciso quando a entrega mexeu em firestore.rules."
if perguntar "Publicar as regras do Firestore?"; then
  firebase deploy --only firestore:rules
fi
echo

echo "═══ 7. Servidor dos avisos ═══"
echo "Só é preciso quando a entrega mexeu na pasta worker/."
if perguntar "Publicar o servidor dos avisos (Cloudflare)?"; then
  (cd worker && npx wrangler deploy)
  echo
  echo "Conferindo se ele subiu bem..."
  # A rota /saude diz se o robô entra e se é líder. É o jeito mais rápido de
  # saber se a publicação deu certo de verdade.
  node -e '
    const fs = require("fs");
    const dart = fs.readFileSync("lib/core/constants/avisos_config.dart", "utf8");
    const m = /worker\s*=\s*.([^"\x27]+)./.exec(dart);
    if (!m) { console.log("não achei o endereço do Worker"); process.exit(0); }
    fetch(m[1].replace(/\/+$/, "") + "/saude")
      .then((r) => r.text())
      .then((t) => console.log("  " + t))
      .catch((e) => console.log("  não respondeu: " + e.message));
  '
fi
echo
echo "Pronto. Abra o app no celular e confira Perfil → Saúde do sistema."
