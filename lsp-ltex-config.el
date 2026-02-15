;;; lsp-ltex-config.el --- LTEX+ LS via stdio (per Emacs session) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configure lsp-ltex to run LTEX+ LS (ltex-ls-plus) as a normal LSP server
;; process (stdio) managed by Emacs/lsp-mode.
;;
;; This avoids the instability seen when attaching to a long-lived TCP daemon.
;;

;;; Code:

;; This module uses cl-lib (e.g. `cl-pushnew`).
;; cl-lib is loaded early from init.el.

(defconst my-ltex-ls-plus-command "ltex-ls-plus"
  "Command used to start LTEX+ LS.")

(defun my--lsp-ltex--session-root ()
  "Return a suitable root directory for the current buffer." 
  (let ((proj (when (fboundp 'project-current)
                (project-current nil))))
    (cond
     (proj (project-root proj))
     ((buffer-file-name) (file-name-directory (buffer-file-name)))
     (t default-directory))))

(defun my--lsp-ltex--ensure-session-folder ()
  "Add a workspace folder to the lsp session without prompting.

This prevents the `lsp-mode` project import prompt for LTEX buffers." 
  (when (fboundp 'lsp-session)
    (let* ((session (lsp-session))
           (root (my--lsp-ltex--session-root))
           (root (if (fboundp 'lsp-f-canonical) (lsp-f-canonical root) (expand-file-name root))))
      (cl-pushnew root (lsp-session-folders session) :test #'equal))))

(defun my--lsp-ltex-enable ()
  "Enable LTEX in the current buffer." 
  (setq-local lsp-idle-delay 0.8)
  (my--lsp-ltex--ensure-session-folder)
  (lsp-deferred))

(use-package lsp-ltex
  :after lsp-mode
  :demand t
  :init
  ;; Opt-in comment checking for selected programming languages.
  (setq lsp-ltex-enabled
        ["bibtex" "latex" "markdown" "typst" "asciidoc" "neorg" "org"
         "git-commit" "python" "javascript" "typescript"])

  (setq lsp-ltex-language "en-US")
  (setq lsp-ltex-check-frequency "edit")

  :config
  ;; Enable lsp-ltex in additional programming modes.
  (dolist (mode '(python-mode python-ts-mode
                  js-mode js-ts-mode
                  typescript-mode typescript-ts-mode tsx-ts-mode))
    (add-to-list 'lsp-ltex-active-modes mode))

  ;; Use ltex-ls-plus (installed externally, e.g. via zinit) instead of the
  ;; default ltex-ls downloader.
  (add-to-list 'lsp-disabled-clients 'ltex-ls)
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda () (list my-ltex-ls-plus-command)))
    :major-modes lsp-ltex-active-modes
    :action-handlers
    (lsp-ht
     ("_ltex.addToDictionary" #'lsp-ltex--code-action-add-to-dictionary)
     ("_ltex.disableRules" #'lsp-ltex--code-action-disable-rules)
     ("_ltex.hideFalsePositives" #'lsp-ltex--code-action-hide-false-positives))
    :priority -2
    :add-on? t
    :server-id 'ltex-ls-plus))

  :hook
  ((org-mode markdown-mode gfm-mode latex-mode text-mode
             python-mode python-ts-mode
             js-mode js-ts-mode
             typescript-mode typescript-ts-mode tsx-ts-mode) . my--lsp-ltex-enable))

(provide 'lsp-ltex-config)

;;; lsp-ltex-config.el ends here
