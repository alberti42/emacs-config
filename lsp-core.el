;;; lsp-core.el --- LSP core configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Base LSP configuration used by language-specific modules.
;;

;;; Code:

(use-package lsp-mode
  :straight (lsp-mode
             :type git
             :host github
             :local-repo  "/Users/andrea/Documents/Programming/Others/fork-lsp-mode"
             :branch "merged"
             ;; :branch "fix/diagnostics-remap-on-edit"
             :repo "alberti42/fork-lsp-mode")
  :commands (lsp lsp-deferred)
  :init
  ;; Use plists for JSON (faster + lower GC pressure than hash-tables).
  ;; Requires `LSP_USE_PLISTS=true' in the environment at byte-compile time (set
  ;; in `early-init.el').  It is reported to improve the performance.
  (setq lsp-use-plists t)
  (setq lsp-keymap-prefix "C-c l")
  ;; Use flycheck for diagnostics (richer display, fringe stays fixed — no jitter).
  (setq lsp-diagnostics-provider :flycheck)
  ;; Whether to suppress "no server installed" popups for file types like plist/XML.
  (setq lsp-warn-no-matched-clients t)
  ;; All servers are managed externally (zinit/system); never prompt to
  ;; download or auto-install them via lsp-mode.  This also prevents lsp-mode
  ;; from creating empty store directories that confuse server-present? checks.
  (setq lsp-enable-suggest-server-download nil)
  ;; File watchers off: on a `client/registerCapability' for
  ;; `workspace/didChangeWatchedFiles', lsp-mode synchronously walks the
  ;; whole workspace tree (`lsp--all-watchable-directories') on the main
  ;; thread — a 2 GB repo froze Emacs ~60s per activation.  Language
  ;; servers (basedpyright et al.) watch their own files, so this is
  ;; largely redundant.
  (setq lsp-enable-file-watchers nil)
  ;; Enable lsp integration with completion-at-point
  (setq lsp-completion-enable t)
  ;; Completion is handled by corfu+cape, not company-mode.  The command below
  ;; prevents lsp-mode from trying to configure company-mode for
  ;; completion. Without it, lsp-mode assumes company-mode is the completion
  ;; frontend and tries to set it up automatically — printing a warning when
  ;; it's not found.  The naming is misleading: it doesn't disable LSP
  ;; completion (CAPF is registered before this cond), it disables lsp-mode's
  ;; company auto-setup.
  (setq lsp-completion-provider :none)
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 4 1024 1024))
  ;; Whether to display breadcrumb headers.  Note: multiple LSP servers may
  ;; fight over header-line-format, resulting in conflicts and partial
  ;; overwrites.
  (setq lsp-headerline-breadcrumb-enable t)
  ;; auto-guess-root makes lsp-mode use project.el to detect the workspace root
  ;; instead of using cache.
  (setq lsp-auto-guess-root t)
  ;; without-session stops lsp-mode from consulting/updating the session file
  ;; `~/.config/emacs/.lsp-session-v1' at all. The session file becomes
  ;; irrelevant and stops growing.
  (setq lsp-guess-root-without-session t)
  ;; ElDoc: show LSP hover info in the echo area (signature only).
  ;; lsp-eldoc-render-all nil keeps it to one line; full docs are available
  ;; on demand via C-c l h h (`lsp-describe-thing-at-point').
  (setq lsp-eldoc-enable-hover t)
  ;; If this is set to nil, eldoc will show only the symbol information.
  (setq lsp-eldoc-render-all nil)
  ;; `lsp-completion-no-cache' and `lsp-completion-use-last-result' kept at
  ;; their defaults (caching enabled, last result reused on interrupt).
  ;; `cape-capf-buster' wraps `lsp-completion-at-point' in the LSP Super-Capf
  ;; below and busts the cache when the typed prefix changes, which is the right
  ;; invalidation granularity.
  :config
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)
  ;; We disable LSP server alive (https://github.com/nobody-famous/alive-lsp)
  ;; for lisp files because it requires a server running on port 8006.
  (add-to-list 'lsp-disabled-clients 'alive-lsp))

;;; -- flycheck integration for diagnostic -------------------------------------
;;
;; - Diagnostics flow: LSP server → lsp-mode → flycheck → flycheck-annotate-mode
;;
;; - Code actions flow: LSP server → lsp-mode → sideline-lsp (queried directly
;;                      per line, bypassing flycheck)
;; 
;; Flycheck is purely an error-reporting framework.  Code actions are an
;; LSP-specific feature, so sideline-lsp talks to lsp-mode directly to fetch
;; them.

;; Force-requiring lsp-diagnostics ensures its faces (e.g.
;; `lsp-flycheck-info-unnecessary' for "unused" diagnostics) are defined
;; before any server sends a diagnostic that references them — otherwise
;; early diagnostics trigger "Invalid face reference" warnings.
(use-package lsp-diagnostics
  ;; No package fetch — file ships inside lsp-mode; disable straight's
  ;; default auto-install behaviour for this block.
  :straight nil
  :after lsp-mode)

;; flycheck: lsp-mode's flycheck integration already passes :id code? to
;; flycheck-error-new (see lsp-diagnostics--flycheck-start), so diagnostic
;; codes (e.g. "reportPossiblyUnbound") are natively available in flycheck
;; via flycheck-error-id — no override needed here.
(emacs-config-patch-package 'flycheck
                            "preserve-wrap-prefix.patch")

(use-package flycheck
  :init
  ;; left-fringe: fringes are always present in GUI frames (no layout jitter)
  ;; and degrade gracefully in TTY.
  (setq flycheck-indication-mode 'left-fringe)
  ;; Disable the continuation fringe indicator on wrapped error lines.
  ;; The main indicator (before-string) is sufficient; the continuation
  ;; indicator in wrap-prefix conflicts with before-string when both
  ;; land on the same visual line (word-wrap boundary).
  (setq flycheck-indication-mode-continuation nil)
  ;; Remove the per-buffer error cap (default 400).  When a checker exceeds
  ;; it, flycheck *discards all* its errors and disables the checker for the
  ;; buffer — so nothing is highlighted, the fringe stays empty, and
  ;; `flycheck-list-errors' shows nothing, even though the diagnostics exist.
  ;; That default targets runaway code linters; LTEX+ on a long prose document
  ;; (e.g. a sizeable .org/.md file) routinely flags >400 items legitimately,
  ;; which would otherwise silently suppress every squiggle in the buffer.
  (setq flycheck-checker-error-threshold nil)
  :config
  ;; Widen the ID column in `flycheck-list-errors' so diagnostic codes are
  ;; readable; the default width of 6 clips everything past a few characters.
  ;; One can also use M-x `tabulated-list-widen-current-column' (}) /
  ;; `tabulated-list-narrow-current-column' ({) to adjust the current column's
  ;; width interactively (the change is buffer-local and doesn't persist).
  (setf (aref flycheck-error-list-format 4) '("ID" 18 t))

  ;; The default `flycheck-highlighting-style' is
  ;;
  ;;   (conditional 4 level-face (delimiters "" ""))
  ;;
  ;; This means that regions >4 lines are rendered with empty-string delimiters
  ;; → effectively invisible.  Replace the empty delimiters with real glyphs so
  ;; longer diagnostic regions (e.g. misspelled words flagged by LTEX+) are
  ;; visible alongside the short-region wave underline.
  (setq flycheck-highlighting-style
        '(conditional 4 level-face (delimiters "»" "«")))

  ;; -- Inline diagnostics (native, Flycheck 38+) -----------------------------
  ;; `flycheck-annotate-mode' renders diagnostics inline, replacing the old
  ;; `sideline-flycheck' backend.  The error ID is shown by default — its
  ;; `flycheck-annotate-format-function' is `flycheck-error-format-message-and-id',
  ;; exactly what the retired `fork-sideline-flycheck' patch added.
  ;;
  ;;   - current line -> `below': full message(s) stacked under the line, so a
  ;;     long LTEX+/prose diagnostic is fully readable.
  ;;   - other lines  -> `sideline': compact "most-severe (+N)" flushed to the
  ;;     window's right edge (lsp-ui-sideline style).  In a prose buffer whose
  ;;     text fills the width it just trails the text; set
  ;;     `flycheck-annotate-other-lines-style' buffer-locally to `below' or nil
  ;;     there if that reads as too noisy.
  (setq flycheck-annotate-current-line-style nil
        flycheck-annotate-other-lines-style nil)
  ;; Enable inline diagnostics wherever flycheck runs.  For on-demand use
  ;; instead, drop this hook and toggle `M-x flycheck-annotate-mode' per buffer
  ;; (or `global-flycheck-annotate-mode' for everywhere).
  (add-hook 'flycheck-mode-hook #'flycheck-annotate-mode))

;;; -- Sideline setup (code actions only) --------------------------------------
;;
;; `sideline-lsp' shows LSP code actions ("do this to fix it") inline at the
;; right, queried per line directly from lsp-mode.  Diagnostics are no longer
;; shown here — they moved to native `flycheck-annotate-mode' (see the flycheck
;; block above).  `sideline-mode' is loaded but not auto-enabled; toggle it with
;; `M-x sideline-mode' when you want to see code actions.
;;
;; (The former `local/sideline.el' right-margin experiment — an unstable patch
;; adding `sideline-display-area' to route prose labels into the margin — has
;; been dropped; `flycheck-annotate-mode's `below' style covers that need.)

(use-package sideline
  ;; Loaded but NOT auto-enabled: `sideline-mode' is left off by default and
  ;; toggled on demand via `M-x sideline-mode'.
  :commands (sideline-mode)
  :init
  (setq sideline-backends-right '(sideline-lsp)
        ;; Stack right-side labels downward starting at point's line, so the
        ;; first label aligns with the paragraph the diagnostic refers to
        ;; rather than ending one row above it.
        sideline-order-right 'down
        sideline-backends-right-skip-current-line nil))

(use-package sideline-lsp
  :commands (sideline-lsp)
  :init
  (setq sideline-lsp-code-actions-prefix "💡"))

;; `sideline-flycheck': diagnostics are now rendered by native
;; `flycheck-annotate-mode' (configured in the `flycheck' block above).  To
;; restore the sideline backend, reinstate a `use-package sideline-flycheck'
;; block, add `sideline-flycheck' back to `sideline-backends-right', and drop
;; the `flycheck-annotate-mode' hook.

;;; -- yasnippet setup ---------------------------------------------------------

;; yasnippet (the snippet expansion engine consumed by lsp-mode for placeholder
;; completion candidates) is configured separately in `yasnippet-config.el' and
;; loaded from `init.el' before this module.  Snippet *insertion* is bound to
;; `C-c y' (`yas-insert-snippet') — intentionally not
;; auto-popup-completion-driven; see `yasnippet-config.el' for the rationale.

;;; -- LSP completion wrapper --------------------------------------------------

;; `lsp-completion-mode' (enabled per buffer when an LSP client attaches)
;; prepends `lsp-completion-at-point' to `completion-at-point-functions'.
;; We replace that bare entry with a wrapped form that adds two
;; behaviours:
;;
;; 1. `cape-capf-buster' invalidates the LSP cache whenever the typed prefix
;;    changes, forcing lsp-mode to re-issue the request on every keystroke.
;; 2. `cape-capf-properties :exclusive 'no' makes the chain fall through to
;;    subsequent CAPFs (`cape-file' inside path strings, `cape-tex' after `\',
;;    the prose Super-Capf, ...) when LSP returns no candidates.  This replaces
;;    the older `:filter-return cape-nonexclusive' advice on
;;    `lsp-completion-at-point' → exclusivity now lives next to the CAPF that
;;    needs it instead of being injected via advice.
;;
;; Commentary on `cape-capf-buster' vs. `isIncomplete'
;;
;; The LSP `textDocument/completion' response carries an `isIncomplete'
;; flag:
;;
;;   - `isIncomplete: false' → "this list is complete for this prefix;
;;     if the user types more chars you can filter it client-side, no
;;     need to ask me again."
;;   - `isIncomplete: true'  → "list is partial; come back to me on
;;     the next keystroke."
;;
;; lsp-mode honours that: with `false' it caches the response and
;; filters locally; with `true' it re-queries each keystroke.
;;
;; `cape-capf-buster' invalidates the CAPF cache whenever the typed
;; prefix changes, so wrapping `lsp-completion-at-point' in it is
;; equivalent to overriding `isIncomplete: false' from the server
;; and treating every response as `isIncomplete: true'.
;;
;; That is intentionally conservative.  Reasons we want it:
;;
;;   1. Server bugs — basedpyright, pylsp, rust-analyzer, etc. have
;;      all at various points sent `isIncomplete: false' even when
;;      their candidate list was filtered or truncated.  Trusting the
;;      flag → may miss candidates that "should" be there.
;;   2. Context vs. prefix — `isIncomplete' describes the list for
;;      the current prefix, but a single keystroke can move across a
;;      syntactic boundary (`.', string delimiter, scope change)
;;      where the correct candidate set is genuinely different from a
;;      client-side filter of the cached list.
;;   3. Cost is negligible — one extra round-trip per keystroke to a
;;      local server is sub-millisecond; far cheaper than the cost of
;;      a stale popup.
;;
;; To honour the server's hint instead, drop `cape-capf-buster' below
;; and leave `lsp-completion-no-cache' / `lsp-completion-use-last-result'
;; at their defaults.

(defun emacs-config--lsp-completion-setup ()
  "Wrap `lsp-completion-at-point' with cache busting and non-exclusivity."
  (when (fboundp 'cape-capf-buster)
    (setq-local completion-at-point-functions
                (cons
                 ;; prepend our wrapped CAPF to the front of the list
                 (cape-capf-properties
                  (cape-capf-buster #'lsp-completion-at-point)
                  :exclusive 'no)
                 ;; drop the bare lsp-completion-at-point
                 (delq #'lsp-completion-at-point
                       (copy-sequence completion-at-point-functions))))))

(add-hook 'lsp-completion-mode-hook
          #'emacs-config--lsp-completion-setup)

(provide 'lsp-core)

;;; lsp-core.el ends here
