;;; tramp-config.el --- Remote file editing via TRAMP -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; TRAMP is built in; a remote file is opened with a path such as
;; `/ssh:host:/path/to/file' (or `/sudo::/etc/hosts' locally).
;;

;;; Code:

(use-package tramp
  :straight nil
  :defer t
  :custom
  ;; The connection cache defaults to `user-emacs-directory'.  It is derived
  ;; data: TRAMP probes each host again when the file is gone.
  (tramp-persistency-file-name (emacs-config-cache-file "tramp"))
  :config
  ;; Search the PATH the remote login shell sets, so programs installed under
  ;; ~/.local/bin or similar (git, rg, uv) are found on the remote host.
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

(provide 'tramp-config)
;;; tramp-config.el ends here
