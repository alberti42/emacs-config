(setq backup-inhibited t) ; disable backup
(setq make-backup-files nil) ; stop creating ~ files
(menu-bar-mode -1) ; turn off menu ba
(setq vc-follow-symlinks t) ; do not ask confirmation before following symbolic links

;; Emacs packages
(require 'package)
;; Any add to list for package-archives (to add marmalade or melpa) goes here
;; MELPA is a popular emacs package loader
(add-to-list 'package-archives 
    '("MELPA" .
      "http://melpa.org/packages/"))
(package-initialize)

;; Catppuccin for Emacs https://github.com/catppuccin/emacs
; (setq catppuccin-flavor 'latte) ; or 'latte, 'macchiato, or 'mocha
; (load-theme 'catppuccin t)




