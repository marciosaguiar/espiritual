#!/usr/bin/env bash
#
# Aplica no repositório o patch que está na área de transferência.
#
# COMO USAR
#
#   bash ferramentas/aplicar.sh
#
# Antes: toque em "Copiar o patch" na página que o Claude entregou.
#
# POR QUE ESTE ARQUIVO EXISTE
#
# O comando de aplicar é uma linha só — `pbpaste | base64 -d | gunzip |
# git am` —, mas ele falha de jeitos que não explicam nada: com uma mudança
# não salva no repositório, com o patch pela metade, com o `git am` parado no
# meio. Este script confere as três coisas antes e, se algo der errado,
# desfaz e diz o que fazer.
#
# Ele NÃO envia nada para o GitHub: aplicar e publicar são dois passos de
# propósito, para dar tempo de rodar os testes no meio.

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Ler a área de transferência, no Mac ou no Linux ──────────────────────
colar() {
  if command -v pbpaste >/dev/null 2>&1; then
    pbpaste
  elif command -v wl-paste >/dev/null 2>&1; then
    wl-paste
  elif command -v xclip >/dev/null 2>&1; then
    xclip -o -selection clipboard
  else
    echo "Não achei como ler a área de transferência." >&2
    echo "No Mac isso é o pbpaste, que já vem instalado." >&2
    exit 1
  fi
}

# ── 1. O repositório precisa estar limpo ─────────────────────────────────
#
# `git am` com mudança não salva recusa no meio e deixa o repositório num
# estado que assusta. Melhor parar antes e dizer o que fazer.
#
# EXCEÇÃO: arquivos que o PRÓPRIO FLUTTER regenera a cada `flutter pub get` e a
# cada teste (a lista de pacotes e o registro de plugins). O `publicar.sh` roda
# os dois, então, depois de qualquer publicação, o repositório amanhece "sujo"
# por causa deles — e o `aplicar.sh` recusava o patch seguinte por um motivo
# que ninguém mexeu. Esses arquivos voltam sozinhos ao que está no repositório,
# e o script diz que fez isso. Qualquer OUTRO arquivo modificado continua
# parando tudo: aí pode ser trabalho de verdade.
REGENERADOS='(^|/)pubspec\.lock$|(^|/)GeneratedPluginRegistrant\.(java|m|swift)$|(^|/)generated_plugin_registrant\.(cc|h|cmake)$|(^|/)generated_plugins\.cmake$'

MODIFICADOS=$( { git diff --name-only; git diff --cached --name-only; } | sort -u )
if [ -n "$MODIFICADOS" ]; then
  GERADOS=$(printf '%s\n' "$MODIFICADOS" | grep -E "$REGENERADOS" || true)
  OUTROS=$(printf '%s\n' "$MODIFICADOS" | grep -vE "$REGENERADOS" || true)

  if [ -n "$OUTROS" ]; then
    echo "Há mudanças não salvas no repositório:"
    printf '%s\n' "$OUTROS" | sed 's/^/  · /'
    echo
    echo "Guarde-as antes:   git stash"
    echo "Ou jogue fora:     git checkout ."
    exit 1
  fi

  echo "Arquivos que o Flutter regenera sozinho voltam ao normal:"
  printf '%s\n' "$GERADOS" | sed 's/^/  · /'
  # `-q` + `--` : só estes arquivos, sem tocar em mais nada.
  printf '%s\n' "$GERADOS" | xargs git checkout HEAD --
  echo
fi

RAMO=$(git rev-parse --abbrev-ref HEAD)
echo "Ramo atual: $RAMO"
echo "Último commit: $(git log --oneline -1)"
echo

# ── 2. Decodificar o patch ───────────────────────────────────────────────
TMP=$(mktemp "${TMPDIR:-/tmp}/levita-patch.XXXXXX")
trap 'rm -f "$TMP"' EXIT

if ! colar | base64 -d 2>/dev/null | gunzip > "$TMP" 2>/dev/null; then
  echo "O que está copiado não é um patch do LevitaSync."
  echo
  echo "Toque em \"Copiar o patch\" na página e rode de novo. Se você copiou"
  echo "outra coisa no meio (um link, um texto), é isso."
  exit 1
fi

if [ ! -s "$TMP" ]; then
  echo "O patch chegou vazio. Copie de novo na página."
  exit 1
fi

# O título vem codificado no arquivo (`=?UTF-8?q?feat:=20a=20B=C3=ADblia...`):
# quem decodifica é o próprio git, que é o que vai gravar o commit.
echo "O patch traz:"
DIR_PATCH=$(mktemp -d "${TMPDIR:-/tmp}/levita-mbox.XXXXXX")
trap 'rm -f "$TMP"; rm -rf "$DIR_PATCH"' EXIT
git mailsplit -o"$DIR_PATCH" "$TMP" >/dev/null
for mensagem in "$DIR_PATCH"/*; do
  git mailinfo /dev/null /dev/null < "$mensagem" | sed -n 's/^Subject: /  · /p'
done
echo

# ── 3. Aplicar ───────────────────────────────────────────────────────────
if git am "$TMP"; then
  echo
  echo "Aplicado. Agora:"
  echo "  bash ferramentas/publicar.sh"
  echo
  echo "Esse script roda os testes antes de enviar, e pergunta sobre as"
  echo "regras do banco e o servidor dos avisos."
else
  echo
  echo "O patch não entrou. Desfazendo para o repositório não ficar no meio."
  git am --abort || true
  echo
  echo "Causa mais comum: este patch foi feito a partir de outro commit."
  echo "Diga ao Claude em qual commit você está:"
  echo "  $(git log --oneline -1)"
  exit 1
fi
