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
;; The binary is not installed system-wide here, so `org-semantic-executable'
;; falls back to the release build inside the checkout — see
;; `org-semantic-config-executable'.

;;; Code:

(defconst org-semantic-config-checkout
  (expand-file-name "~/Documents/Programming/Emacs/org-semantic")
  "The org-semantic repository, holding both the Lisp and the Rust binary.

Spelled out again in the `:straight' recipe below, which cannot use it:
a use-package recipe is literal data, not an expression, so a symbol
there reaches straight as a symbol and fails as a directory name.")

(defun org-semantic-config-executable ()
  "Return the org-semantic binary to run.

Installed copy first — `cargo install' puts one on PATH, and that is
what a shell run of `org-semantic index' would use, so preferring it
keeps the two from being different releases.  Failing that, the release
build inside the checkout, which is what a development machine has.

The default name is returned when neither exists, so the failure is
org-semantic's own \"binary not found\" rather than a nil argument
travelling into `make-process'."
  (or (executable-find "org-semantic")
      (let ((built (expand-file-name "target/release/org-semantic"
                                     org-semantic-config-checkout)))
        (and (file-executable-p built) built))
      "org-semantic"))

(use-package org-semantic
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
  (org-semantic-executable (org-semantic-config-executable))
  ;; Build both indexes on `M-x org-semantic-reindex': the lexical one is
  ;; seconds on top of a semantic run, and `m' in the results buffer swaps
  ;; between them, which is only useful when both exist.
  (org-semantic-index-mode "both")
  ;; The indexing policy is deliberately left nil.  It is compared *whole*, so
  ;; a partial one reads as a change to everything it omits and fails the
  ;; search against an index built without it; nil searches the index as it
  ;; stands, which is what a command-line run does.
  (org-semantic-config nil))

(provide 'org-semantic-config)
;;; org-semantic-config.el ends here
