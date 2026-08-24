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
;; The same variable set globally — below, and nil — would be the answer for a
;; buffer that declares nothing: `*scratch*', an agenda, a file in some project.
;;
;; The note vaults of `vulpea-config.el' are wired to this in
;; `vulpea-vault/semantic.el': the vault being left is closed on the server when
;; `vulpea-vault-switch' switches away from it, and a buffer that belongs to no
;; org-semantic vault falls back to the active vulpea vault, so `C-c n s'
;; searches the notes from anywhere.
;;
;; THE TWO WOULD COMPETE, and the global setting would win: that advice is
;; `:after-until', which runs only when `org-semantic-vault' comes back empty.
;; So the setting below is left nil deliberately — the vault switched to is a
;; better answer than a fixed one — and a default, if ever wanted, goes inside
;; the advice rather than here.
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
  ;; `s' and `S' are the pair grep and `consult-ripgrep' established: the
  ;; capital is the same search, narrowed to the directory point is in.  It
  ;; is `s' with a `dir:' predicate already in the prompt, so the scope is
  ;; text that can be widened or deleted there rather than a hidden argument.
  :bind (("C-c n s" . org-semantic-find)
         ("C-c n S" . org-semantic-find-in-directory)
         ("C-c n ." . org-semantic-find-at-point)
         ("C-c n R" . org-semantic-reindex))
  :init
  ;; The indexes are kept current, but NOT by `org-semantic-auto-reindex-mode',
  ;; which is left off.  That mode is one trigger and not the policy: its whole
  ;; content is an `after-save-hook', and vulpea's file watcher already reports
  ;; a save — along with everything a save cannot report, a rename or a delete
  ;; in Dired, a `git pull', a folder arriving from a sync.  One watcher for
  ;; two indexes; turning the mode on as well would sign the same change twice
  ;; and add nothing.  The wiring is in `vulpea-vault/semantic.el', and it
  ;; calls `org-semantic-auto-reindex-touch', which is independent of the mode.
  ;;
  ;; What is done here is loading the package, because a touch does nothing
  ;; until something has: the guard on vulpea's side is `featurep', so that a
  ;; session which opens no note pays for none of this.  The first org buffer
  ;; is where that stops being true — and is quiet, unlike the middle of a save
  ;; — so the load happens there, once, from a hook that removes itself.
  ;;
  ;; To go back to save-driven reindexing, enable the mode here instead: the
  ;; two are additive, and a change signalled twice still costs one run.
  (defun org-semantic-config-load-on-first-note ()
    "Load org-semantic, once, when the first org buffer appears.
So that the reindex touches from `vulpea-vault/semantic.el', which do
nothing until the package is loaded, are live for the rest of the
session."
    (remove-hook 'org-mode-hook #'org-semantic-config-load-on-first-note)
    (require 'org-semantic))
  (add-hook 'org-mode-hook #'org-semantic-config-load-on-first-note)
  :custom
  ;; `org-semantic-executable' and `org-semantic-install-directory' are both
  ;; left at their defaults: the binary is looked for in
  ;; ~/.config/emacs/org-semantic/ and then on PATH, which is what a user
  ;; without this configuration gets.  See the Commentary for the symlink that
  ;; keeps the development build in that first place.
  ;;
  ;; Which vault a buffer that declares none belongs to — `*scratch*', an
  ;; agenda, a file in some other project.  A fixed directory is the wrong
  ;; answer here, because `vulpea-vault-switch' moves between vaults during a
  ;; session, so this names the function that follows it.  A note inside a
  ;; declared vault keeps that vault: a declaration is answered first.
  ;;
  ;; The function lives in `vulpea-vault/semantic.el', which is where everything
  ;; the two packages have to agree on lives.  It was `:after-until' advice on
  ;; `org-semantic-vault' until this setting could hold a function.
  (org-semantic-vault-root #'vulpea-vault-semantic-vault)

  ;; Build both indexes on `M-x org-semantic-reindex': the lexical one is
  ;; seconds on top of a semantic run, and `M-s' / `M-l' in the results buffer
  ;; choose between them, which is only useful when both exist.
  (org-semantic-index-mode "both")

  ;; Never answer from an index that is being rebuilt.  Off by default, and on
  ;; here because the indexes are kept current automatically: a note saved a
  ;; moment ago is exactly the one being looked for, and a list drawn from the
  ;; version before it is the wrong answer rather than merely an old one.
  ;;
  ;; The cost lands almost entirely on runs that are seconds long, because that
  ;; is what the watcher makes: `org-semantic-auto-reindex-touch' reaches
  ;; `org-semantic-index', so those runs belong to this Emacs and the search is
  ;; simply held until the run replies.  Nothing polls, and it cannot hang — the
  ;; reply arrives whether the run works or fails.  A deliberate `C-c n R' is
  ;; the case that costs minutes, and there the wait is the point.
  ;;
  ;; A run in another program — a shell, a cron job, a second Emacs — is refused
  ;; instead, since this Emacs cannot know when that one finishes.  The buffer
  ;; then says so and asks for the search again.
  (org-semantic-require-fresh-index t)

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
