;;; syntaxes.el --- Load per-syntax configuration files -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Loads every .el file found in the syntaxes/ subdirectory next to this file.
;; To add settings for a new language, drop a file in syntaxes/.
;;

;;; Code:

;; Global indentation defaults
(setq-default indent-tabs-mode nil)
(setq-default tab-width 2)
(setq-default standard-indent 2)

;; Load all syntax files in the syntaxes/ subdirectory 
(let ((dir (expand-file-name "syntaxes" emacs-config-dir)))
  (when (file-directory-p dir)
    (dolist (file (directory-files dir t "\\.el\\'"))
      (load file nil 'nomessage))))

(provide 'syntaxes)

;;; syntaxes.el ends here
