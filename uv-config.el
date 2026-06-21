;;; uv-config.el --- Per-buffer uv virtualenv selection -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; uv manages Python through ordinary virtual environments rather than
;; pyenv-style shims.  The named/global environments (the pyenv-virtualenv
;; replacement) live under `uv-virtualenvs-dir' -- by default
;; `$XDG_DATA_HOME/virtualenvs/<name>'.
;;
;; Unlike pyenv there is NO shim that walks up from the subprocess CWD
;; honoring `.python-version', so a bare `python' spawned from a buffer does
;; not pick up a named environment on its own.  Activation is therefore
;; always explicit, mirroring a shell `source <venv>/bin/activate'.  This
;; module offers two ways to do it buffer-locally:
;;
;; * The dir-local variable `uv-venv', picked up when local variables are
;;   applied -- point several project repos at one shared named env without a
;;   per-project `.venv'.
;;
;; * `uv-activate-buffer' for interactive, ad-hoc selection.
;;
;; Both make `process-environment' buffer-local and set VIRTUAL_ENV plus the
;; environment's bin/ on PATH there, so subprocesses spawned from the buffer
;; -- including long-running ones like coding agents -- see the activated
;; environment.
;;

;;; Code:

(require 'seq)

(defgroup uv-config nil
  "Per-buffer activation of uv-managed virtual environments."
  :group 'python)

(defcustom uv-virtualenvs-dir
  (expand-file-name "virtualenvs"
                    (or (getenv "XDG_DATA_HOME")
                        (expand-file-name "~/.local/share")))
  "Directory holding named uv virtual environments.
Each immediate subdirectory with a `bin/python' is treated as a
selectable environment.  XDG-consistent default mirrors where the uv
migration places named envs (the pyenv-virtualenv replacement)."
  :type 'directory)

(defvar-local uv-active-venv nil
  "uv virtualenv activated in the current buffer, or nil.")

(defvar uv-venv nil
  "uv virtualenv to activate via dir-locals.
Set in `.dir-locals.el' to auto-activate a named environment on a
per-project basis.  Either a bare name under `uv-virtualenvs-dir' or an
absolute path to a virtualenv root.  Becomes buffer-local when applied.")

;;;###autoload (put 'uv-venv 'safe-local-variable #'stringp)
(put 'uv-venv 'safe-local-variable #'stringp)

(defun uv--virtualenvs ()
  "Return the names of virtualenvs under `uv-virtualenvs-dir'.
Only subdirectories that actually contain a `bin/python' are listed."
  (when (file-directory-p uv-virtualenvs-dir)
    (seq-filter
     (lambda (name)
       (file-exists-p
        (expand-file-name (concat name "/bin/python") uv-virtualenvs-dir)))
     (directory-files uv-virtualenvs-dir nil "\\`[^.]"))))

(defun uv--prefix (venv)
  "Return the filesystem prefix of VENV.
VENV is either a bare name resolved against `uv-virtualenvs-dir' or an
absolute path to a virtualenv root."
  (if (file-name-absolute-p venv)
      (expand-file-name venv)
    (expand-file-name venv uv-virtualenvs-dir)))

(defun uv--set (venv)
  "Activate uv VENV buffer-locally.
Mirrors `source <venv>/bin/activate' in a shell: sets VIRTUAL_ENV,
prepends the environment's bin/ to both PATH (in a buffer-local
`process-environment') and `exec-path', and clears PYTHONHOME.
Subprocesses spawned from the buffer -- including long-running ones like
coding agents -- inherit the full activated environment."
  (let* ((prefix (uv--prefix venv))
         (bin (expand-file-name "bin" prefix)))
    (unless (file-directory-p bin)
      (error "No uv virtualenv at %s" prefix))
    (make-local-variable 'process-environment)
    (make-local-variable 'exec-path)
    (setenv "VIRTUAL_ENV" prefix)
    (setenv "PYTHONHOME" nil)
    (setenv "PATH" (concat bin path-separator (getenv "PATH")))
    (setq exec-path (cons bin exec-path))
    (setq uv-active-venv venv)))

;;;###autoload
(defun uv-activate-buffer (venv)
  "Activate uv VENV for the current buffer only.
Subprocesses started from this buffer see VIRTUAL_ENV and the env's bin/
on PATH via a buffer-local `process-environment'."
  (interactive
   (list (completing-read "uv virtualenv: " (uv--virtualenvs) nil t)))
  (uv--set venv)
  (message "uv %s activated in %s" venv (buffer-name)))

;;;###autoload
(defun uv-deactivate-buffer ()
  "Deactivate the buffer-local uv environment.
Reverts VIRTUAL_ENV, PYTHONHOME, PATH, and `exec-path' in one go by
dropping the buffer-local copies set up by `uv--set'."
  (interactive)
  (when (local-variable-p 'process-environment)
    (kill-local-variable 'process-environment))
  (when (local-variable-p 'exec-path)
    (kill-local-variable 'exec-path))
  (setq uv-active-venv nil)
  (message "uv deactivated in %s" (buffer-name)))

(defun uv--apply-dir-local ()
  "Activate `uv-venv' if set via dir-locals."
  (when (and uv-venv (stringp uv-venv))
    (uv--set uv-venv)))

(add-hook 'hack-local-variables-hook #'uv--apply-dir-local)

(provide 'uv-config)
;;; uv-config.el ends here
