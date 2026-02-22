;;; completion.el --- Completion system orchestration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module orchestrates completion across Emacs:
;; - Minibuffer completion UI (Vertico preferred; Icomplete/Fido fallback)
;; - Completion styles (including Orderless)
;; - In-buffer completion UI (Corfu) and extra CAPF sources (Cape)
;;
;; Keep leaf modules in completions/.

;;; Code:

;; Make `M-x' context-aware by default.
;;
;; Emacs can filter the set of commands shown by `execute-extended-command'
;; based on whether they apply in the current context (major mode, minibuffer,
;; active completion UIs, etc.). This improves signal-to-noise in `M-x' and also
;; hides internal/transient commands from packages like Corfu, which are not
;; meant to be called directly.
;;
;; If you ever miss a command in `M-x', this is the knob to revisit.
(use-package emacs
  :straight nil
  :init
  (setq read-extended-command-predicate #'command-completion-default-include-p))

;; Styles / matching
(emacs-config-load-module
 "completions/styles"
 "Could not load completions/styles.el; using default completion styles.")

(emacs-config-load-module
 "completions/orderless"
 "Could not load completions/orderless.el; Orderless is disabled.")

;; Minibuffer UI: prefer Vertico, fall back to Icomplete/Fido.
(unless (emacs-config-load-module
         "completions/minibuffer-vertico"
         "Could not load completions/minibuffer-vertico.el; Vertico is disabled.")
  (emacs-config-load-module
   "completions/minibuffer-icomplete"
   "Could not load completions/minibuffer-icomplete.el; minibuffer completion UI is degraded."))

;; In-buffer completion
(emacs-config-load-module
 "completions/corfu"
 "Could not load completions/corfu.el; Corfu is disabled.")

(emacs-config-load-module
 "completions/cape"
 "Could not load completions/cape.el; Cape is disabled.")

(provide 'completion)

;;; completion.el ends here
