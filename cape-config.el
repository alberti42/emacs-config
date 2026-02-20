;;; cape-config.el --- Extra CAPF sources (Cape) -*- lexical-binding: t; -*-

;; Cape extends Emacs' completion-at-point (CAPF) with extra sources.
;; Keep these as fallbacks by appending them.
(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file t)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev t))

(provide 'cape-config)
;;; cape-config.el ends here
