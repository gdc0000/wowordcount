# wowordcount — Design del modulo jamovi

Data: 2026-08-24
Autore: Gabriele Di Cicco (con ox-alpha)
Stato: approvato

## 1. Obiettivo

Portare la logica di conteggio lessicale stile LIWC di
[WordCount](https://github.com/gdc0000/WordCount) (app Streamlit Python)
in un modulo jamovi nativo in R, seguendo la struttura dei moduli standard
(es. [gamlj](https://github.com/gamlj/gamlj)).

L'utente porta il proprio dizionario (wordlist); il modulo conta, per ogni
categoria del dizionario e per ogni documento del dataset: occorrenze,
percentuale sui token. Restituisce anche metriche globali (token, tipi).

Vincolo primario: l'utente tipo è un ricercatore in psicologia con laptop
da 8 GB di RAM → overhead minimo, nessuna dipendenza pesante.

## 2. Decisioni prese

| Decisione | Scelta |
|---|---|
| Linguaggio | R nativo (jmvtools), niente reticulate/Python runtime |
| Input dizionario | Solo TextArea paste (jamovi non ha file picker nelle analisi) |
| Formato dizionario | TSV con header `DicTerm` + colonne categoria; `X` = appartenenza; suffisso `*` = wildcard prefisso; termini multi-parola ammessi |
| Output | Colonne nel dataset + tabella riassunto; niente plots, niente inferenziale |
| `detected_words` | Checkbox opzionale, default OFF |
| Nome modulo | `wowordcount` |

## 3. Architettura

Modulo jamovi standard generato/conforme a jmvtools:

```
wowordcount/
├── DESCRIPTION
├── NAMESPACE
├── R/
│   ├── dictionary.R      # parsing dizionario incollato
│   ├── tokenizer.R       # pulizia, tokenizzazione, n-grams
│   ├── counter.R         # matching exact/wildcard + trie, conteggi
│   └── wordcount.b.R     # classe analisi jamovi (orchestrazione)
├── jamovi/
│   ├── wordcount.a.yaml  # definizione UI
│   └── wordcount.r.yaml  # definizione risultati
├── inst/
│   └── tests/            # fixture golden test
└── tests/testthat.R      # unit test
```

### 3.1 dictionary.R — parsing

Input: stringa multilinea dalla TextArea.

- Lettura con `read.delim(text = ..., sep = "\t", colClasses = "character")`.
- Prima colonna obbligatoria: `DicTerm` (case-insensitive). Errore chiaro se manca.
- Colonne successive = categorie. Cella contiene `X` (case-insensitive,
  trimmed) → termine appartiene alla categoria.
- Termine con `*` finale → wildcard prefisso.
- Termine multi-parola (contiene spazi interni) → match su n-gram.
- Terminazione righe vuote / celle vuote / spazi: ignorate.
- Output: quattro strutture lookup equivalenti all'originale Python:
  - `exact_single`: lista `categoria -> set(termini)`
  - `wildcard_single`: lista `categoria -> vettore(prefissi)`
  - `exact_multi`: lista `categoria -> set(ngram)`
  - `wildcard_multi`: lista `categoria -> vettore(prefissi)`
- Output secondario per tabella riessunto: nome categoria, n termini esatti,
  n prefissi, n termini multi-parola.

### 3.2 tokenizer.R — tokenizzazione

Parità 1:1 con `_tokenize_document` / `_generate_ngrams` Python:

- lowercase dell'intero documento
- rimozione caratteri non `[A-Za-z0-9_\s']` (equivalente regex `\w\s'`;
  attenzione a Unicode: usare regex PCRE con classi Unicode o `stringi`
  se già disponibile — decisione presa in implementazione, vincolo =
  stesso comportamento dell'originale)
- split su whitespace
- unigram = token singoli
- n-grams generati **solo** per le lunghezze richieste dal dizionario
  (`required_ngram_lengths`, max 5), come nell'originale — ottimizzazione
  chiave per memoria

### 3.3 counter.R — conteggio

Parità 1:1 con `_analyze_document`:

- per ogni token: match esatto (lookup set) + match prefisso (trie)
- per ogni n-gram delle lunghezze richieste: match esatto + prefisso (trie)
- trie realizzate con environment annidate (equivalente dict annidati)
- conteggio per categoria ponderato per frequenza token/ngram (table())
- raccolta parole rilevate per categoria solo se `detected_words` ON
- output per documento: `n_tokens`, `n_types`,
  `{cat}_word_count` (intero), `{cat}_word_perc` (proporzione su n_tokens;
  0 se n_tokens == 0), eventualmente `{cat}_detected_words`

### 3.4 wordcount.b.R — analisi jamovi

UI (wordcount.a.yaml):

- Variabile testo (single variable picker, tipo `variable`, filtro testo)
- TextArea dizionario (obbligatoria; errore se vuota al run)
- Checkbox `detected_words` default false

Risultati (wordcount.r.yaml):

- Aggiunta colonne al dataset via API "create variables" (stessa usata da
  `jmv::descriptives`): `n_tokens`, `n_types`, una coppia count/perc per
  categoria, opzionalmente detected_words
- Tabella "Dictionary summary": Categoria, Termini esatti, Prefissi
  wildcards, Termini multi-parola
- Progress bar durante elaborazione documenti

Elaborazione:

- parse dizionario una sola volta per run
- loop streaming documento-per-documento sul character vector della
  variabile selezionata; nessuna copia del dataset
- assegnazione valori colonna per colonna al termine

## 4. Gestione errori

| Caso | Comportamento |
|---|---|
| TextArea vuota | errore: "Incollare un dizionario" |
| Header `DicTerm` mancante | errore con esempio di formato atteso |
| Nessuna categoria valida | errore |
| Dizionario senza alcun termine riconosciuto nel corpus | warning nella tabella summary |
| Documento NA/vuoto | n_tokens=0, tutti i count 0 |
| Dataset molto grande | progress bar; elaborazione O(documento) streaming |

## 5. Performance (vincolo 8 GB)

- zero dipendenze esterne dove possibile: base R puro; eventuale uso di
  `stringi`/`stringr` solo se già bundlato con jamovi (verificare in
  implementazione)
- n-grams solo per lunghezze richieste dal dizionario
- lookup via environment/set, mai scansione del dizionario per token
- nessun oggetto intermedio grande: Counter-like tramite `table()`
- detected_words OFF by default (stringhe lunghe evitate)

## 6. Testing

1. **Unit test (testthat)**: parser dizionario (casi: header errato, wildcard,
   multi-word, X case-insensitive, celle sporche); tokenizer (parità con casi
   noti); counter (conteggi attesi su mini-corpus).
2. **Golden test**: fixture input (dizionario + corpus) e output attesi
   generati dal codice Python originale (`app/text_analysis.py`) → garanzia
   parità numerica tra Streamlit e modulo jamovi. Fixture salvate in
   `inst/tests/golden/`.
3. **End-to-end**: installazione via `jmvtools::install()`, run su dataset
   esempio incluso, verifica colonne create.

## 7. Fuori scope

- Plots, correlazioni, ANOVA (jamovi li offre già nativamente)
- Dizionari precaricati nel modulo
- Upload file
- Supporto lingue con tokenizzazione speciale (CJK)
