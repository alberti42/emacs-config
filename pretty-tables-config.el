;;; pretty-tables-config.el --- Configuration for pretty-tables -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Registers `pretty-tables', the drawing shared by its two adaptors:
;; `pretty-tables-for-markdown' (configured in markdown-config.el) and
;; `pretty-tables-for-org' (configured in org-config.el).  The three
;; packages live in one local checkout, one straight recipe each, and this
;; one must be registered before the adaptors that require it.
;;

;;; Code:

(use-package pretty-tables
  :straight (pretty-tables
             :type git
             :local-repo "/Users/andrea/Documents/Programming/Emacs/pretty-tables"
             :files ("pretty-tables.el"))
  :defer t)

(provide 'pretty-tables-config)
;;; pretty-tables-config.el ends here
