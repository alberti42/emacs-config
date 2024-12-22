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
(setq catppuccin-flavor 'macchiato) ; or 'latte, 'macchiato, or 'mocha
(load-theme 'catppuccin t)

;; Load snazzy theme
; (load-theme 'snazzy t)

(use-package all-the-icons
  :ensure t)

(use-package smart-mode-line
  :ensure t
  :config
  (setq sml/no-confirm-load-theme t
        sml/theme 'respectful) ; Or pick 'light', 'dark', etc.
  (sml/setup))

;; Set default font for Emacs
(set-face-attribute 'default nil :font "MesloLGS NF" :height 120)

;; Customize the mode line font
(set-face-attribute 'mode-line nil :font "MesloLGS NF" :height 120 :weight 'bold)
(set-face-attribute 'mode-line-inactive nil :font "MesloLGS NF" :height 120)


(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages '(smart-mode-line all-the-icons ## snazzy-theme)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
