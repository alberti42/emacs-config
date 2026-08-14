;;; org-semantic-config.el --- Semantic and lexical search over org notes -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `org-semantic' searches a tree of org notes by meaning (embeddings) or by
;; word (BM25).  It is one Rust binary plus this Emacs front-end: no database
;; server, no Python.  The binary is driven over a pipe — `org-semantic serve'
;; speaks JSON-RPC on stdio, so `jsonrpc.el' (the library Eglot runs on) is the
;; whole of the transport — and one process holds every vault, the embedding
;; model loaded once for all of them.
;;
;; Two things this module owns, and nothing else:
;;
;; - the straight recipe pointing at the local checkout (the package is
;;   developed here; see AGENTS.md on rebuilding a local-repo package after
;;   editing it), and
;; - the settings and key bindings.
;;
;; Which vault is searched is mostly NOT decided here.  A vault says so itself,
;; in its own `.dir-locals.el':
;;
;;   ((nil . ((org-semantic-vault-root . t))))
;;
;; and Emacs applies that when a note is opened, so a note carries its vault
;; before anything has been indexed.  That is the only thing that finds a vault:
;; the `.org-semantic' directory is derived data and is never consulted, since
;; where it lives is not the vault's to promise — it may be moved out of a synced
;; folder entirely.
;;
;; The *same* variable set globally — below — is the answer for a buffer that
;; declares nothing: `*scratch*', an agenda, a file in some project.
;;
;; The note vaults of `vulpea-config.el' are wired to this in
;; `vulpea-vault/semantic.el': the vault being left is closed on the server when
;; `vulpea-vault-switch' switches away from it, and a buffer that belongs to no
;; org-semantic vault falls back to the active vulpea vault, so `C-c n s'
;; searches the notes from anywhere.
;;
;; NOTE THAT THE TWO FALLBACKS COMPETE, and the global setting wins.  That
;; advice is `:after-until', which runs only when `org-semantic-vault' comes back
;; empty — and with the setting below it never does.  So `C-c n s' from
;; `*scratch*' searches the vault named there rather than the vault currently
;; switched to.  To have the active vault keep winning, leave the setting nil and
;; put the constant inside the advice instead:
;;
;;   (or vulpea-vault-directory "~/org/Work")
;;
;; The Lisp comes from the checkout; the *binary* deliberately does not.  It is
;; found where org-semantic looks for one by itself —
;; `org-semantic-install-directory', which defaults to
;; ~/.config/emacs/org-semantic/ — so nothing about the binary is configured
;; here and this exercises the path a user takes.  Pointing it at the checkout
;; would make this the only machine the configuration works on, and would hide
;; anything wrong with the lookup everyone else depends on.
;;
;; To keep running the build in the checkout without downloading anything, put
;; a symlink there:
;;
;;   mkdir -p ~/.config/emacs/org-semantic
;;   ln -sf ~/Documents/Programming/Emacs/org-semantic/target/release/org-semantic \
;;          ~/.config/emacs/org-semantic/org-semantic
;;
;; `cargo build --release' then updates what Emacs runs, with no copying — and
;; the lookup is still the real one, so a mistake in it shows up here.

;;; Code:

(use-package org-semantic
  ;; The path is spelled out rather than named: a use-package recipe is literal
  ;; data, not an expression, so a symbol here would reach straight as a symbol
  ;; and fail as a directory name.
  :straight (org-semantic
             :type git
             :host github
             :local-repo "/Users/andrea/Documents/Programming/Emacs/org-semantic"
             :repo "alberti42/org-semantic"
             ;; The Lisp lives under lisp/; straight's default recipe would
             ;; look for *.el at the repository root and find nothing.
             :files ("lisp/*.el"))
  ;; Deferred: the process starts on the first search, not at startup, and
  ;; every entry point below is autoloaded.  `vulpea-vault/semantic.el' is
  ;; written to match — it never loads this package, it only acts when
  ;; something else already has.
  :defer t
  :bind (("C-c n s" . org-semantic-find)
         ("C-c n S" . org-semantic-find-at-point)
         ("C-c n R" . org-semantic-reindex))
  :custom
  ;; `org-semantic-executable' and `org-semantic-install-directory' are both
  ;; left at their defaults: the binary is looked for in
  ;; ~/.config/emacs/org-semantic/ and then on PATH, which is what a user
  ;; without this configuration gets.  See the Commentary for the symlink that
  ;; keeps the development build in that first place.
  ;;
  ;; The vault to search from a buffer that is in none: `*scratch*', an agenda,
  ;; a file in some other project.  A note in either notes vault carries its own
  ;; root from that vault's `.dir-locals.el', so this never overrides one of
  ;; those — but it does pre-empt the vulpea fallback, which only runs when the
  ;; question comes back empty.  See the Commentary.
  (org-semantic-vault-root "~/org/Work")

  ;; Build both indexes on `M-x org-semantic-reindex': the lexical one is
  ;; seconds on top of a semantic run, and `M-s' / `M-l' in the results buffer
  ;; choose between them, which is only useful when both exist.
  (org-semantic-index-mode "both")

  ;; The indexing policy, stated whole.  It is compared whole, so a setting left
  ;; out is not left alone — it takes its default — and a policy that disagrees
  ;; with the one an index was built under fails the search rather than
  ;; answering from passages split by rules no longer held.
  ;;
  ;; Everything here is org-semantic's own default except `:languages', which
  ;; names the three this vault is written in: that confines the lexical
  ;; classifier to those, instead of letting it guess among all 176 and label a
  ;; link-only note Portuguese.
  ;;
  ;; Vectors, not lists, and no commas between the elements: a comma inside a
  ;; quoted form is the symbol `\,', which serialises to JSON as an object and
  ;; is silently accepted as far as Emacs is concerned.
  (org-semantic-config
   '(:languages ["en-US" "de-DE" "it-IT"]
     :fold_diacritics :json-false
     :blocks (:src     (:semantic "placeholder" :lexical t)
              :example (:semantic "placeholder" :lexical t)
              :results (:semantic :json-false   :lexical t)
              :quote   (:semantic t             :lexical t)
              :verse   (:semantic t             :lexical t))
     :planning_line (:semantic :json-false :lexical t)
     :chunk (:semantic_tokens 350 :lexical_chars 1500)
     :exclude_tagged ["noexport" "ARCHIVE"]
     :todo_keywords ["TODO" "DONE"])))

(provide 'org-semantic-config)
;;; org-semantic-config.el ends here
