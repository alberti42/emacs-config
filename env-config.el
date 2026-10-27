;;; env-config.el --- Shell environment import -*- lexical-binding: t; -*-

;; Loaded from early-init.el, so PATH is correct before straight.el and any
;; package lookups run.
;;
;; When EMACS_IMPORT_SHELL_ENV is set, Emacs runs the user's login shell as an
;; interactive login shell and copies its environment into this Emacs.  The
;; LaunchAgent `io.alberti42.emacs-daemon' sets that variable, because launchd
;; starts Emacs with a barren environment: no PATH additions, no XDG variables.
;; An Emacs started from a shell already has that shell's environment, so it
;; leaves the variable unset and nothing is imported.
;;
;; $XDG_CONFIG_HOME/envs/LanguageTools.sh is read in both cases, because no
;; shell sources it.

(defvar env-config-shell-session-variables
  '("PWD" "OLDPWD" "SHLVL" "_" "STARSHIP_SESSION_KEY")
  "Variables that describe the shell process itself and are not imported.")

(defun env-config--setenv (var val)
  "Set VAR to VAL in `process-environment'.
Also updates `exec-path' when VAR is PATH."
  (setenv var val)
  (when (string= var "PATH")
    (setq exec-path (append (parse-colon-path val)
                            (list exec-directory)))))

(defun env-config--shell-environment ()
  "Return the environment of an interactive login shell as (VAR . VAL) pairs.
The shell is $SHELL.  Return nil when the shell fails."
  (with-temp-buffer
    ;; Shell start-up files may print to stdout before `env' runs; the marker
    ;; separates that output from the environment.
    (when (and (eq 0 (call-process (or (getenv "SHELL") shell-file-name)
                                   nil '(t nil) nil
                                   "-lic" "print -rn -- $'\\0EMACS-ENV\\0'; command env -0"))
               (progn (goto-char (point-min))
                      (search-forward "\0EMACS-ENV\0" nil t)))
      (let (env)
        (dolist (entry (split-string (buffer-substring (point) (point-max)) "\0" t))
          (when (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\)=" entry)
            (push (cons (match-string 1 entry) (substring entry (match-end 0)))
                  env)))
        (nreverse env)))))

(defun env-config--import-shell-environment ()
  "Copy the environment of an interactive login shell into this Emacs."
  (let ((env (env-config--shell-environment)))
    (if (null env)
        (message "env-config: could not read the environment of %s"
                 (or (getenv "SHELL") shell-file-name))
      (pcase-dolist (`(,var . ,val) env)
        (unless (member var env-config-shell-session-variables)
          (env-config--setenv var val))))))

(defun env-config--load-export-file (file)
  "Parse export KEY='VALUE' lines from FILE and set them in Emacs environment."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^export \\([A-Za-z_][A-Za-z0-9_]*\\)='\\([^']*\\)'" nil t)
        (env-config--setenv (match-string 1) (match-string 2))))))

(when (getenv "EMACS_IMPORT_SHELL_ENV")
  (env-config--import-shell-environment)
  ;; Child processes must not import again.
  (setenv "EMACS_IMPORT_SHELL_ENV" nil))

(env-config--load-export-file
 (expand-file-name "envs/LanguageTools.sh"
                   (or (getenv "XDG_CONFIG_HOME") (expand-file-name "~/.config"))))

(provide 'env-config)
;;; env-config.el ends here
