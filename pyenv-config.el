;;; pyenv-config.el --- Per-buffer pyenv version selection -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Pyenv's shims already honor `.python-version' by walking up from the
;; subprocess CWD, and Emacs subprocesses inherit `default-directory' as CWD.
;; So for most projects no Emacs-side logic is needed -- opening a file inside
;; the project is enough for `python', `pip', etc. to resolve correctly.
;;
;; This module adds two override paths on top of that default:
;;
;; * The dir-local variable `pyenv-version', picked up when local variables are
;;   applied -- useful for project-level overrides you do not want to commit as
;;   a `.python-version' file.
;;
;; * `pyenv-activate-buffer' for interactive, ad-hoc selection.
;;
;; Both paths make `process-environment' buffer-local and set PYENV_VERSION
;; inside that local copy, so subprocesses spawned from the buffer see the
;; chosen version.
;;

;;; Code:

(defvar-local pyenv-active-version nil
  "Pyenv version activated in the current buffer, or nil.")

(defvar pyenv-version nil
  "Pyenv version to activate via dir-locals.
Set in `.dir-locals.el' to override `.python-version' (or the global pyenv
version) on a per-project basis.  Becomes buffer-local when applied.")

;;;###autoload (put 'pyenv-version 'safe-local-variable #'stringp)
(put 'pyenv-version 'safe-local-variable #'stringp)

(defun pyenv--virtualenvs ()
  "Return the list of installed pyenv virtualenvs (canonical names and aliases).
This matches the list that `pyenv activate <TAB>' offers."
  (process-lines "pyenv" "virtualenvs" "--bare"))

(defun pyenv--prefix (version)
  "Return the filesystem prefix of pyenv VERSION (install or virtualenv root)."
  (car (process-lines "pyenv" "prefix" version)))

(defun pyenv--set (version)
  "Activate pyenv VERSION buffer-locally.
Mirrors `pyenv activate' in a shell: sets PYENV_VERSION and VIRTUAL_ENV,
and prepends the environment's bin/ to both PATH (in a buffer-local
`process-environment') and `exec-path'.  Subprocesses spawned from the
buffer -- including long-running ones like coding agents -- inherit the
full activated environment."
  (let* ((prefix (pyenv--prefix version))
         (bin (expand-file-name "bin" prefix)))
    (make-local-variable 'process-environment)
    (make-local-variable 'exec-path)
    (setenv "PYENV_VERSION" version)
    (setenv "VIRTUAL_ENV" prefix)
    (setenv "PATH" (concat bin path-separator (getenv "PATH")))
    (setq exec-path (cons bin exec-path))
    (setq pyenv-active-version version)))

;;;###autoload
(defun pyenv-activate-buffer (version)
  "Activate pyenv VERSION for the current buffer only.
Subprocesses started from this buffer see PYENV_VERSION=VERSION via a
buffer-local `process-environment'."
  (interactive
   (list (completing-read "Pyenv virtualenv: " (pyenv--virtualenvs) nil t)))
  (pyenv--set version)
  (message "Pyenv %s activated in %s" version (buffer-name)))

;;;###autoload
(defun pyenv-deactivate-buffer ()
  "Deactivate the buffer-local pyenv environment.
Reverts PYENV_VERSION, VIRTUAL_ENV, PATH, and `exec-path' in one go by
dropping the buffer-local copies set up by `pyenv--set'."
  (interactive)
  (when (local-variable-p 'process-environment)
    (kill-local-variable 'process-environment))
  (when (local-variable-p 'exec-path)
    (kill-local-variable 'exec-path))
  (setq pyenv-active-version nil)
  (message "Pyenv deactivated in %s" (buffer-name)))

(defun pyenv--apply-dir-local ()
  "Activate `pyenv-version' if set via dir-locals."
  (when (and pyenv-version (stringp pyenv-version))
    (pyenv--set pyenv-version)))

(add-hook 'hack-local-variables-hook #'pyenv--apply-dir-local)

(provide 'pyenv-config)
;;; pyenv-config.el ends here
