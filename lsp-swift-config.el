;;; lsp-swift-config.el --- Swift LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Swift LSP via lsp-sourcekit (SourceKit-LSP).
;;
;; Locates the server via PATH or `xcrun -f sourcekit-lsp` on macOS.

;;; Code:

(defun lsp-swift--find-sourcekit-lsp ()
  "Find the SourceKit-LSP executable."
  (or (executable-find "sourcekit-lsp")
      (and (eq system-type 'darwin)
           (let ((xcrun-path (executable-find "xcrun")))
             (when xcrun-path
               (let ((path (string-trim (shell-command-to-string "xcrun -f sourcekit-lsp"))))
                 (when (file-executable-p path)
                   path)))))))

(use-package lsp-sourcekit
  :after lsp-mode
  :init
  (setq lsp-sourcekit-executable (lsp-swift--find-sourcekit-lsp))
  :hook
  (swift-mode . lsp-deferred))

(provide 'lsp-swift-config)

;;; lsp-swift-config.el ends here
