# Textos bíblicos

Os dois arquivos `.json` **não vêm no patch**: são 7,7 MB, e um patch com
eles dentro passa de 3 milhões de caracteres, impossível de colar no
Terminal. Eles são gerados por:

```bash
bash ferramentas/baixar-biblia.sh
```

O script busca o texto na fonte, confere que vieram os 66 livros e que
nenhum capítulo está vazio, e grava no formato abaixo. Rodar de novo dá
exatamente o mesmo resultado. Depois de rodar, os arquivos **precisam ser
commitados**: é o GitHub Pages que os serve para o app.

Dois arquivos, um por tradução, no formato que a tela de leitura espera:

```json
{ "sigla": "BLIVRE", "nome": "Bíblia Livre",
  "credito": "...", "licenca": "...", "licencaUrl": "...",
  "livros": [ { "s": "gn", "c": [ ["versículo 1", "versículo 2"], ... ] } ] }
```

Os livros vêm na ordem canônica (39 do Antigo Testamento, 27 do Novo), com as
siglas em minúsculas. Os nomes por extenso ficam em
`lib/core/constants/livros_biblia.dart`, não aqui: são os mesmos para as duas
traduções e repeti-los custaria espaço por nada.

**Estes arquivos NÃO entram no pacote inicial do app.** São ativos do Flutter,
que na web só são baixados quando a tela pede. O `web/sw.js` também os deixa
de fora do que guarda na instalação, justamente para não baixar 2,4 MB de
Bíblia numa abertura de app que talvez nem passe pela Bíblia; quando a pessoa
abre uma tradução, o arquivo é guardado no aparelho na mesma hora.

## De onde veio cada texto, e sob que licença

### Bíblia Livre (BLIVRE) — 3,76 MB (≈1,2 MB comprimido)

**Licença: Creative Commons Atribuição 3.0 Brasil.** NÃO é domínio público.
A licença exige crédito, e por isso o crédito exigido pelo projeto viaja
dentro do próprio arquivo, no campo `credito`, e a tela de leitura o mostra.

- Projeto: https://sites.google.com/site/biblialivre/
- Licença: https://github.com/blivre/BibliaLivre/blob/master/LICENCA.md
- Texto obtido de https://github.com/damarals/biblias (releases, `BLIVRE.json`)

### Almeida 1911 (ALM1911) — 3,82 MB (≈1,2 MB comprimido)

**Domínio público.** João Ferreira de Almeida morreu em 1691, e a edição de
1911 está livre pelo decurso de prazo — a ortografia do arquivo ("No
principio creou Deus", "abysmo") confirma que é a edição histórica, e não uma
revisão moderna, que seria protegida. O Project Gutenberg distribui a mesma
obra (nº 62383) com o aviso "Public domain in the USA".

- Texto obtido de https://github.com/damarals/biblias (releases, `ALM1911.json`)

## O que NÃO pode entrar aqui

NVI, ARA, NAA, ARC, ACF, NTLH e companhia pertencem a editoras. Não importa
que se ache o arquivo na internet: distribuir é com a editora. Quem quiser
ler nessas traduções usa o botão "Abrir no YouVersion".
