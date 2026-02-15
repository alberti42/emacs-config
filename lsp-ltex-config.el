;;; lsp-ltex-config.el --- LTEX+ LS via TCP daemon -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configure lsp-ltex to connect to an already-running LTEX+ LS daemon over TCP.
;;
;; Proof-of-principle: connect to 127.0.0.1:38080. No bootstrap logic and no
;; runtime checks.
;;

;;; Code:


(defconst my-ltex-plus-daemon-host "127.0.0.1"
  "Host running the LTEX+ LS daemon.")

(defconst my-ltex-plus-daemon-port 38080
  "Port of the LTEX+ LS daemon.")

(defun my--lsp-ltex-tcp-connect (filter sentinel name _environment-fn _workspace)
  "Connect lsp-mode to an already-running LTEX+ LS daemon." 
  (let ((proc (open-network-stream
               (format "%s::tcp" name)
               nil
               my-ltex-plus-daemon-host
               my-ltex-plus-daemon-port
               :type 'plain
               :coding 'no-conversion)))
    (set-process-query-on-exit-flag proc nil)
    (set-process-filter proc filter)
    (set-process-sentinel proc sentinel)
    ;; lsp-mode expects (COMM-PROC . CMD-PROC). For an external daemon there is
    ;; no command process; return PROC in both slots as a proof-of-principle.
    (cons proc proc)))

(defun my--lsp-ltex-enable ()
  "Enable LTEX in the current buffer." 
  (setq-local lsp-idle-delay 0.8)
  (lsp-deferred))

(with-eval-after-load 'lsp-mode
  (require 'lsp-ltex)
  ;; Disable the default stdio-based ltex-ls client; use the TCP daemon instead.
  (add-to-list 'lsp-disabled-clients 'ltex-ls)
  (lsp-register-client
   (make-lsp-client
    :new-connection (list
                     :connect #'my--lsp-ltex-tcp-connect
                     :test? (lambda () t))
    :major-modes lsp-ltex-active-modes
    :action-handlers
    (lsp-ht
     ("_ltex.addToDictionary" #'lsp-ltex--code-action-add-to-dictionary)
     ("_ltex.disableRules" #'lsp-ltex--code-action-disable-rules)
     ("_ltex.hideFalsePositives" #'lsp-ltex--code-action-hide-false-positives))
    :priority -2
    :add-on? t
    :server-id 'ltex-ls-tcp)))

(use-package lsp-ltex
  :init
  ;; Opt-in comment checking for selected programming languages.
  (setq lsp-ltex-enabled
        ["bibtex" "context" "context.tex" "html" "latex" "markdown" "mdx"
         "typst" "asciidoc" "neorg" "org" "quarto" "restructuredtext" "rsweave"
         "git-commit" "python" "javascript" "javascriptreact" "typescript" "typescriptreact"])

  (setq lsp-ltex-language "en-US")
  (setq lsp-ltex-check-frequency "edit")

  :config
  ;; Enable lsp-ltex in additional programming modes.
  (dolist (mode '(python-mode python-ts-mode
                  js-mode js-ts-mode
                  typescript-mode typescript-ts-mode tsx-ts-mode))
    (add-to-list 'lsp-ltex-active-modes mode))

  :hook
  ((org-mode markdown-mode latex-mode text-mode
             python-mode python-ts-mode
             js-mode js-ts-mode
             typescript-mode typescript-ts-mode tsx-ts-mode) . my--lsp-ltex-enable))

(provide 'lsp-ltex-config)

;;; lsp-ltex-config.el ends here
