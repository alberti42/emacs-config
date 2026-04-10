# lsp-ltex-plus.el — Minimal lsp-mode Client for ltex-ls-plus

## Overview

`lsp-ltex-plus.el` is a self-contained lsp-mode client for
[ltex-ls-plus](https://github.com/ltex-plus/ltex-ls-plus), the LanguageTool-based
grammar and spell checker for Markdown, LaTeX, Org, plain text, and
reStructuredText. It replaces the
[lsp-ltex](https://github.com/emacs-languagetool/lsp-ltex) package with
a much smaller, more transparent implementation.

### Why not lsp-ltex?

The `lsp-ltex` package has several problems discovered during debugging:

- It calls `_ltex.checkDocument` to trigger diagnostic checks. This command reads
  the file **from disk**, not from the LSP in-memory buffer. It silently fails
  with `{"success": false, "errorMessage": "Could not read file ..."}` for unsaved
  buffers and may return stale content for saved ones.
- The `ltex.languageToolHttpServerUri` was set to `https://api.languagetoolplus.com/v2`.
  ltex-ls-plus appends `/v2/check` to that URI, producing
  `https://api.languagetoolplus.com/v2/v2/check`, which returns HTTP 404. The
  server silently got 0 matches from every check.
- A large amount of custom async scheduling code was layered on top of the broken
  `_ltex.checkDocument` call, creating hard-to-debug race conditions.

All of these issues are absent from `lsp-ltex-plus.el`.

---

## How ltex-ls-plus Works (Protocol-Level)

Understanding the server's protocol behaviour is essential. The following was
determined by running a raw Python LSP client against `ltex-ls-plus` directly,
without any Emacs involvement.

### Checking is triggered by standard LSP notifications

The server checks a document automatically in response to:

- `textDocument/didOpen` — on first open
- `textDocument/didChange` — on every edit (when `ltex.checkFrequency = "edit"`)

**There is no need to call `_ltex.checkDocument` from the client.** Standard
lsp-mode behaviour (sending `didOpen`/`didChange`) is sufficient.

### Every check is preceded by `workspace/configuration`

Before publishing diagnostics, the server always sends a
`workspace/configuration` request to the client, asking for the full `ltex`
settings namespace. The client must respond with the current settings (language,
API credentials, dictionary, etc.) before the server will proceed.

lsp-mode handles this automatically via `lsp-register-custom-settings`. Each
registered setting is a `(json-path variable-symbol)` pair; lsp-mode evaluates
the symbol and builds the JSON response when the server asks.

Because the settings are read from live Lisp variables at request time, updating
a variable (e.g. adding a word to `ltex--words`) is immediately visible on the
next check without restarting the server.

### `_ltex.checkDocument` reads from disk

Manual testing confirmed that `_ltex.checkDocument` attempts to open the file
path from the filesystem, not from the server's in-memory document buffer. It
returns `{"success": false, "errorMessage": "Could not read file ..."}` for any
file that is not saved to disk at that exact path. This command is never used in
`lsp-ltex-plus.el`.

### Document sync is full (not incremental)

The server advertises `textDocumentSync: 1` (full sync). Every `didChange`
notification sends the complete buffer contents. The server re-checks the full
document each time; it may internally optimise which paragraphs to re-check, but
this is opaque to the client.

### Action commands are client-side

`_ltex.addToDictionary`, `_ltex.disableRules`, and `_ltex.hideFalsePositives` are
code action commands that appear in the server's `textDocument/codeAction`
response. They are meant to be handled **entirely by the client** — the server
never receives them via `workspace/executeCommand`. lsp-mode supports this via the
`:action-handlers` field of `lsp-register-client`.

After updating the local dictionary, the client sends
`workspace/didChangeConfiguration` to notify the server that settings have
changed. The server re-fetches settings via `workspace/configuration` and
immediately re-checks the document with the updated dictionary.

### LanguageTool HTTP API URI

ltex-ls-plus appends `/v2/check` to the value of `ltex.languageToolHttpServerUri`
when making requests. The correct value is therefore the base hostname without any
path:

```
https://api.languagetoolplus.com
```

Not `https://api.languagetoolplus.com/v2` (which would produce the double-`/v2`
path `…/v2/v2/check`, returning HTTP 404).

---

## Architecture

```
lsp-ltex-plus.el
│
├── Dictionary persistence
│   ├── ltex-dictionary-file        — path to stored-dictionary file
│   ├── ltex--words                 — in-memory plist (:en-US ["word" ...])
│   ├── ltex--load-words            — read from disk into ltex--words
│   ├── ltex--save-words            — write ltex--words to disk
│   └── ltex--add-words             — add & deduplicate, then save
│
├── Settings variables
│   └── ltex-language, ltex-enabled, ltex-check-frequency,
│       ltex-lt-server-uri, ltex-lt-username, ltex-lt-api-key, …
│
├── Action handlers (client-side)
│   ├── ltex--action-add-to-dictionary
│   ├── ltex--action-disable-rules
│   └── ltex--action-hide-false-positives
│
├── lsp-mode registration (with-eval-after-load 'lsp-mode)
│   ├── lsp-language-id-configuration — tex-mode→"latex", git-commit-mode→"plaintext"
│   ├── lsp-register-custom-settings  — all ltex.* settings → Lisp variables
│   └── lsp-register-client           — server-id ltex-ls-plus, :add-on? t
│
└── Per-buffer activation
    ├── ltex-enable                 — sets lsp-auto-guess-root, lsp-enable-file-watchers,
    │                                 then calls lsp-deferred
    └── hooks on markdown-mode, tex-mode, text-mode, org-mode, rst-mode,
        git-commit-mode
```

### Key design decisions

**`:add-on? t` and `:priority -1`**
ltex-ls-plus is a grammar checker, not a language server in the traditional
sense. Setting `:add-on? t` allows it to run alongside other servers (e.g.
`texlab` for LaTeX). Setting `:priority -1` ensures it never takes precedence
over a real language server.

**`lsp-auto-guess-root t` (buffer-local)**
ltex-ls-plus has no concept of a project root. Without auto-guessing, lsp-mode
prompts the user to select a root for every standalone file. Setting this
buffer-locally suppresses the prompt.

**`lsp-enable-file-watchers nil` (buffer-local)**
Without disabling file watchers, lsp-mode may start watching the entire home
directory tree for files sitting in `$HOME`. ltex-ls-plus has no use for file
watching.

**No `_ltex.checkDocument`**
As documented above, this command does not work for in-memory buffers.
`didChange` triggers re-checks reliably.

---

## Configuration Variables

| Variable | Default | Description |
|---|---|---|
| `ltex-debug` | `nil` | Enable verbose `[ltex]` messages in `*Messages*` |
| `ltex-language` | `"en-US"` | BCP 47 language tag |
| `ltex-enabled` | `["markdown" "org" "plaintext" "latex" "restructuredtext"]` | Language IDs to check |
| `ltex-check-frequency` | `"edit"` | `"edit"`, `"save"`, or `"manual"` |
| `ltex-diagnostic-severity` | `"warning"` | Flymake severity level |
| `ltex-java-initial-heap` | `64` | JVM initial heap in MB |
| `ltex-java-max-heap` | `512` | JVM max heap in MB |
| `ltex-lt-server-uri` | `"https://api.languagetoolplus.com"` | LanguageTool HTTP server base URI (no `/v2`) |
| `ltex-lt-username` | `""` | LanguageTool.org account username |
| `ltex-lt-api-key` | `""` | LanguageTool.org API key |
| `ltex-dictionary-file` | `<user-emacs-directory>/lsp-ltex-plus/stored-dictionary` | Dictionary persistence file |

Credentials are read from environment variables `LANGUAGETOOL_USERNAME` and
`LANGUAGETOOL_API_KEY` at startup (inside `ltex--setup`, which runs
`with-eval-after-load 'lsp-mode`).

---

## Dictionary Persistence

Words added via the "Add to dictionary" code action are stored in
`ltex-dictionary-file`. The format is a plain Elisp plist:

```elisp
(:en-US ["word1" "word2"] :de-DE ["Wort"])
```

This format is intentionally compatible with the `lsp-ltex-plus` package's
`stored-dictionary` file, making migration seamless.

The file is read into `ltex--words` at setup time. Because `ltex--words` is
registered with `lsp-register-custom-settings`, lsp-mode includes its current
value in every `workspace/configuration` response. Adding a word updates
`ltex--words` in memory and saves to disk, and the server sees the change on its
next `workspace/configuration` request (triggered immediately via
`workspace/didChangeConfiguration`).

To inspect the current dictionary interactively: `M-x ltex-list-words`.

### API-side dictionary

The LanguageTool HTTP API also supports a server-side personal dictionary (via
`POST /words/add`). ltex-ls-plus does not use this. Words added via
`_ltex.addToDictionary` are stored locally (in `ltex-dictionary-file`) and sent
to the server as part of `ltex.dictionary` in `workspace/configuration`.

---

## Dependencies

- **Emacs** 29+
- **lsp-mode** (for `lsp-register-client`, `lsp-register-custom-settings`, etc.)
- **ltex-ls-plus** binary on `PATH` (the Java language server)
- **Java** runtime (required by ltex-ls-plus)
- Optional: LanguageTool Premium account (username + API key) for enhanced
  grammar checking via `https://api.languagetoolplus.com`

---

## Installation (current — dotfiles)

`lsp-ltex-plus-config.el` is loaded as an optional module from `init.el`:

```elisp
(emacs-config-load-module
 'lsp-ltex-plus-config
 "Could not load lsp-ltex-plus-config.el; LTEX+ is disabled.")
```

It loads `lsp-ltex-plus.el` (the client module) and configures the activation hooks.

---

## Future MELPA Package Notes

For packaging on MELPA, the following changes will be needed:

- Add a proper package header:
  ```elisp
  ;; Package-Requires: ((emacs "29.1") (lsp-mode "8.0"))
  ;; Version: 0.1.0
  ;; Keywords: lsp languagetool grammar spell-checking
  ;; URL: https://github.com/...
  ```
- Replace the `defvar` defaults for `ltex-lt-username` / `ltex-lt-api-key`
  (currently read from env vars at startup) with `defcustom` entries so users
  can configure them via `M-x customize`.
- Convert `ltex-dictionary-file` to a `defcustom`.
- The `lsp-language-id-configuration` entries and `lsp-register-client` call
  should move inside the package's `provide` form or a proper `define-minor-mode`
  entry point rather than a bare `with-eval-after-load`.
- Consider whether `ltex-enable` should be exposed as a proper minor mode so
  users can toggle it per-buffer.
- Add `ltex--action-disable-rules` and `ltex--action-hide-false-positives`
  persistence (currently these actions are executed but not saved across
  sessions).
- Write ERT tests covering dictionary load/save/add-words round-trips.

---

## Debugging

Set `ltex-debug` to `t` to enable verbose logging:

```elisp
(setq ltex-debug t)
```

This logs:
- `ltex--setup` execution and all registered setting values
- `ltex-enable` invocations with buffer name, major mode, and detected language ID
- Every `lsp-configuration-section` response sent to the server
- Dictionary load/save/add operations
- Action handler invocations

For raw LSP wire-level logging (all JSON-RPC messages):

```elisp
(setq lsp-log-io t)
```

Messages appear in the `*lsp-log*` buffer. Server stderr (Java log output) is in
the `*ltex-ls-plus::stderr*` buffer.
