#!/usr/bin/env bash
#
# Baixa e prepara os textos bíblicos em assets/biblia/.
#
# Por que isto é um script, e não arquivos no repositório desde o começo:
# são 7,7 MB de texto, e um patch com eles dentro passa de 3 milhões de
# caracteres — impossível de colar no Terminal. O script busca o texto na
# fonte, converte para o formato que o app lê e deixa tudo pronto para o
# commit. Rodar de novo dá exatamente o mesmo resultado.
#
# Uso:  bash ferramentas/baixar-biblia.sh
# Exige: curl e python3 (os dois já vêm no macOS).
#
# A procedência e a licença de cada texto estão em assets/biblia/LEIA-ME.md.
# Resumo: Bíblia Livre é Creative Commons Atribuição 3.0 Brasil (exige
# crédito, que vai dentro do arquivo), Almeida 1911 é domínio público.

set -euo pipefail
cd "$(dirname "$0")/.."

ORIGEM="https://github.com/damarals/biblias/releases/latest/download"
TEMPORARIA="$(mktemp -d)"
trap 'rm -rf "$TEMPORARIA"' EXIT

mkdir -p assets/biblia

# Uma função com dois argumentos, e nada de expansão esperta dentro do laço.
# O bash do macOS é o 3.2, de 2007, e com `set -u` ele tropeçava em
# "${PAR##*:}" — "unbound variable" num script que roda redondo no Linux.
baixar() {
  echo "Baixando $1…"
  curl -sSL --fail --max-time 300 -o "$TEMPORARIA/$1.json" "$ORIGEM/$1.json"
}

baixar BLIVRE
baixar ALM1911

python3 - "$TEMPORARIA" <<'PYTHON'
import json, sys, gzip, os

temporaria = sys.argv[1]

TRADUCOES = {
    "blivre": {
        "origem": "BLIVRE.json",
        "sigla": "BLIVRE",
        "nome": "Bíblia Livre",
        # Crédito exigido pela licença, copiado do README do projeto.
        "credito": (
            "Todas as Escrituras em português citadas são da Bíblia Livre (BLIVRE), "
            "Copyright © Diego Santos, Mario Sérgio, e Marco Teles, "
            "http://sites.google.com/site/biblialivre/ - fevereiro de 2018. "
            "Licença Creative Commons Atribuição 3.0 Brasil "
            "(http://creativecommons.org/licenses/by/3.0/br/). "
            "Reprodução permitida desde que devidamente mencionados fonte e autores."
        ),
        "licenca": "Creative Commons Atribuição 3.0 Brasil (CC BY 3.0 BR)",
        "licencaUrl": "http://creativecommons.org/licenses/by/3.0/br/",
    },
    "alm1911": {
        "origem": "ALM1911.json",
        "sigla": "ALM1911",
        "nome": "Almeida 1911",
        "credito": (
            "Almeida 1911, tradução de João Ferreira de Almeida (1628–1691), "
            "edição de 1911. Obra em domínio público."
        ),
        "licenca": "Domínio público",
        "licencaUrl": "",
    },
}

for ident, meta in TRADUCOES.items():
    bruto = json.load(open(os.path.join(temporaria, meta["origem"]), encoding="utf-8"))
    if len(bruto) != 66:
        raise SystemExit(f"{ident}: esperava 66 livros, vieram {len(bruto)}")

    livros, versos = [], 0
    for livro in bruto:
        capitulos = [[v.strip() for v in cap] for cap in livro["chapters"]]
        if not capitulos or any(not c for c in capitulos):
            raise SystemExit(f"{ident}: livro {livro['abbrev']} com capítulo vazio")
        versos += sum(len(c) for c in capitulos)
        livros.append({"s": livro["abbrev"].lower(), "c": capitulos})

    saida = {k: v for k, v in meta.items() if k != "origem"}
    saida["livros"] = livros
    texto = json.dumps(saida, ensure_ascii=False, separators=(",", ":"))
    open(f"assets/biblia/{ident}.json", "w", encoding="utf-8").write(texto)

    cru = len(texto.encode())
    comprimido = len(gzip.compress(texto.encode(), 9))
    print(f"  {ident:8} 66 livros, {versos} versículos, "
          f"{cru/1048576:.2f} MB ({comprimido/1048576:.2f} MB no fio)")
PYTHON

echo
echo "Pronto. Agora:  flutter test   e depois  git add assets/biblia && git commit"
