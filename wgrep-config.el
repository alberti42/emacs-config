;;; wgrep-config.el --- Editable grep buffers -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Makes grep-mode buffers editable so changes can be applied back to source
;; files.  Pairs with embark-export from consult-ripgrep for project-wide
;; find-and-replace.
;;

;;; Code:

(use-package wgrep
  :custom
  ;; `wgrep-finish-edit' (C-c C-c / C-x C-s) only applies the edits to the
  ;; visiting buffers; without this they stay unsaved until `save-some-buffers'.
  (wgrep-auto-save-buffer nil))

(provide 'wgrep-config)
;;; wgrep-config.el ends here
