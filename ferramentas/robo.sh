#!/usr/bin/env bash
#
# Troca a senha do robô nos TRÊS lugares em que ela precisa combinar.
#
# COMO USAR
#
#   bash ferramentas/robo.sh
#
# POR QUE ESTE ARQUIVO EXISTE
#
# A senha do robô vive em três lugares, e eles precisam dizer a mesma coisa:
#
#   1. a conta dele no Firebase Authentication (a senha de verdade);
#   2. o segredo ROBO_SENHA na Cloudflare, que o servidor dos avisos usa;
#   3. o segredo FAXINA_SENHA no GitHub, que as rotinas diárias usam.
#
# Trocar em um e esquecer os outros é o defeito mais caro que este projeto já
# teve: o robô para de entrar, as rotinas falham todas as noites, e o motivo
# fica num log que ninguém abre. Levou dias para ser descoberto — e a causa
# era uma chave digitada à mão com um caractere errado.
#
# Daí este script. Ele NÃO guarda senha nenhuma: pede na hora, não ecoa na
# tela, não grava em arquivo, e não entra no histórico do terminal.
#
# O QUE ELE NÃO FAZ
#
# Trocar a senha na conta do Firebase. Isso não dá pelo terminal sem chave de
# administrador, que este projeto não usa de propósito — quem tem essa chave
# entra como qualquer pessoa do ministério. Então o primeiro passo é no
# console, com as suas próprias mãos, e o script espera por você.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "═══ Trocar a senha do robô ═══"
echo
echo "ORDEM IMPORTA. Entre o passo 1 e o passo 3, o robô fica sem conseguir"
echo "entrar — então faça os três de uma vez, agora, e não pela metade."
echo

# ── 1. A conta, no console do Firebase ───────────────────────────────────
echo "PASSO 1 — no navegador, no console do Firebase:"
echo
echo "  Authentication → a conta do robô → menu dos três pontos"
echo "  → \"Redefinir senha\" ou \"Editar\" e ponha a senha nova."
echo
echo "Use uma senha longa e sem significado. Ninguém precisa decorá-la: ela"
echo "vive só nos dois segredos abaixo."
echo
printf 'Já trocou a senha no console? [s/N] '
read -r r
if [ "$r" != "s" ] && [ "$r" != "S" ]; then
  echo "Então pare aqui. Trocar os segredos antes da conta deixaria o robô"
  echo "fora do ar sem necessidade."
  exit 0
fi
echo

# ── 2. A senha, lida sem aparecer na tela ────────────────────────────────
printf 'Digite a senha NOVA (não vai aparecer): '
read -rs SENHA
echo
printf 'Digite de novo, para conferir: '
read -rs SENHA2
echo
if [ "$SENHA" != "$SENHA2" ]; then
  echo "As duas não são iguais. Nada foi mudado; rode de novo."
  exit 1
fi
if [ ${#SENHA} -lt 12 ]; then
  echo "Essa senha tem menos de 12 caracteres. Como ninguém precisa decorá-la,"
  echo "não há motivo para ela ser curta. Nada foi mudado; rode de novo."
  exit 1
fi
echo

# ── 3. Cloudflare ────────────────────────────────────────────────────────
echo "PASSO 2 — Cloudflare (o servidor dos avisos)..."
if ! command -v npx >/dev/null 2>&1; then
  echo "npx não encontrado. Instale o Node e rode de novo."
  exit 1
fi
printf '%s' "$SENHA" | (cd worker && npx wrangler secret put ROBO_SENHA)
echo "  ROBO_SENHA trocado."
echo

# ── 4. GitHub ────────────────────────────────────────────────────────────
echo "PASSO 3 — GitHub (as rotinas diárias)..."
if ! command -v gh >/dev/null 2>&1; then
  echo
  echo "O comando gh não está instalado, então o segredo do GitHub NÃO foi"
  echo "trocado — e, enquanto ele não for, as rotinas diárias vão falhar."
  echo
  echo "Faça à mão agora:"
  echo "  github.com → o repositório → Settings → Secrets and variables"
  echo "  → Actions → FAXINA_SENHA → Update"
  exit 1
fi
printf '%s' "$SENHA" | gh secret set FAXINA_SENHA
echo "  FAXINA_SENHA trocado."
echo

unset SENHA SENHA2

# ── 5. Conferir ──────────────────────────────────────────────────────────
echo "═══ Conferindo ═══"
echo
echo "Perguntando ao servidor dos avisos se o robô consegue entrar."
echo "(ele guarda a resposta por 5 minutos, então pode levar um instante)"
echo
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
echo
echo "Se aparecer \"entra e está líder\", está tudo certo."
echo
echo "Se aparecer que ele NÃO entra, espere 5 minutos e confira de novo"
echo "pelo app, em Perfil → Saúde do sistema. Se continuar, a senha da conta"
echo "e a dos segredos não são a mesma: rode este script outra vez, respondendo"
echo "\"s\" no passo 1, e digite com cuidado a MESMA senha que você pôs no"
echo "console."
echo
echo "Depois confira no app: Perfil → Saúde do sistema."
