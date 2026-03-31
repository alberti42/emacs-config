;;; lsp-swift.el --- Swift LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Swift LSP via lsp-sourcekit (SourceKit-LSP).
;; Requires SourceKit-LSP, which ships with the Swift toolchain.
;; On macOS it can also be located via `xcrun -f sourcekit-lsp`.
;;

;;; Code:

(defun lsp-swift--find-sourcekit-lsp ()
  "Return the path to the sourcekit-lsp executable."
  (or (executable-find "sourcekit-lsp")
      (and (eq system-type 'darwin)
           (let ((path (string-trim
                        (shell-command-to-string "xcrun -f sourcekit-lsp 2>/dev/null"))))
             (when (file-executable-p path) path)))))

(use-package swift-mode
  :straight t)

(use-package lsp-sourcekit
  :straight t
  :after lsp-mode
  :init
  (setq lsp-sourcekit-executable (lsp-swift--find-sourcekit-lsp))
  :hook
  (swift-mode . lsp-deferred))

(provide 'lsp-swift)

;;; lsp-swift.el ends here
