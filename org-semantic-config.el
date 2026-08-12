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
;; Which vault is searched is NOT decided here.  A vault says so itself, in its
;; own `.dir-locals.el':
;;
;;   ((nil . ((org-semantic-vault-root . t))))
;;
;; and failing that the nearest directory above holding `.org-semantic' is the
;; vault.  The note vaults of `vulpea-config.el' are wired to this in
;; `vulpea-vault/semantic.el': the vault being left is closed on the server
;; when `vulpea-vault-switch' switches away from it, and a buffer that belongs
;; to no org-semantic vault at all falls back to the active vulpea vault, so
;; `C-c n s' searches the notes from anywhere.
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
  ;; Build both indexes on `M-x org-semantic-reindex': the lexical one is
  ;; seconds on top of a semantic run, and `m' in the results buffer swaps
  ;; between them, which is only useful when both exist.
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
