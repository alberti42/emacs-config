;;; env-config.el --- Shell environment import for non-daemon GUI Emacs -*- lexical-binding: t; -*-

;; Only sourced from early-init.el when (not (daemonp)).  When Emacs is
;; launched directly (not via the daemon
;; launcher), it inherits a barren launchd/Dock environment: no PATH
;; additions, no XDG variables, no COLORTERM.  This module reproduces what
;; emacs_daemon_launcher does by reading the same shell env files and
;; importing their variables into Emacs.

(defun env-config--load-export-file (file)
  "Parse export KEY='VALUE' lines from FILE and set them in Emacs environment.
Also updates `exec-path' when PATH is found."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^export \\([A-Za-z_][A-Za-z0-9_]*\\)='\\([^']*\\)'" nil t)
        (let ((var (match-string 1))
              (val (match-string 2)))
          (setenv var val)
          (when (string= var "PATH")
            (setq exec-path (append (parse-colon-path val)
                                    (list exec-directory)))))))))

(let* ((cache-home  (or (getenv "XDG_CACHE_HOME")  (expand-file-name "~/.cache")))
       (config-home (or (getenv "XDG_CONFIG_HOME") (expand-file-name "~/.config"))))
  (env-config--load-export-file
   (expand-file-name "zsh/interactive-shell-env.sh" cache-home))
  (env-config--load-export-file
   (expand-file-name "envs/LanguageTools.sh" config-home)))

(provide 'env-config)
;;; env-config.el ends here
