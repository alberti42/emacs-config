;;; scroll-config.el --- Scrolling behaviour and smooth-scroll setup -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Tuned scroll parameters for both GUI and TTY, plus ultra-scroll for
;; pixel-precise glitch-free scrolling in GUI frames.
;;

;;; Code:

;; ultra-scroll requires scroll-margin 0 and works best with a low
;; scroll-conservatively value; it handles pixel-precise scrolling itself.
(setq scroll-margin 0)
(setq scroll-conservatively 101)
(setq scroll-step 1)
(setq scroll-preserve-screen-position t)

;; Smoother horizontal scrolling too
(setq hscroll-margin 2)
(setq hscroll-step 1)

;; Pixel-precise, glitch-free smooth scrolling.
;; Replaces pixel-scroll-precision-mode (ultra-scroll activates it internally).
(use-package ultra-scroll
  :config
  ;; Whether to hide the cursor while scrolling and restore it afterwards (default: t).
  (setq ultra-scroll-hide-cursor t)
  (setq ultra-scroll-preserve-column nil)
  (ultra-scroll-mode 1))

;; Scroll by 5 lines at a time.
(global-set-key (kbd "C-v") (lambda () (interactive) (scroll-up 5)))
(global-set-key (kbd "M-v") (lambda () (interactive) (scroll-down 5)))

;; Disable ctrl+scroll zoom (too fast; use keyboard to change font size instead).
(global-set-key (kbd "<C-wheel-up>") 'ignore)
(global-set-key (kbd "<C-wheel-down>") 'ignore)
(global-set-key (kbd "<C-mouse-4>") 'ignore)
(global-set-key (kbd "<C-mouse-5>") 'ignore)

(provide 'scroll-config)

;;; scroll-config.el ends here
