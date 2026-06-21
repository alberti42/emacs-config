;;; lsp-python-config.el --- Python LSP configuration -*- lexical-binding: t; -*-

;;; Code:

(require 'uv-config)

(defvar lsp-python-basedpyright-venv
  (expand-file-name "py313" uv-virtualenvs-dir)
  "uv virtualenv whose bin/ provides basedpyright-langserver and python.")

(use-package lsp-pyright
  :straight t
  :init
  ;; basedpyright-langserver lives in the py313 uv virtualenv's bin, which is
  ;; not on the PATH that env-config.el imports from the shell env cache file.
  (add-to-list 'exec-path (expand-file-name "bin" lsp-python-basedpyright-venv))
  (setq lsp-pyright-langserver-command "basedpyright")
  :config
  (add-to-list 'lsp-disabled-clients 'ruff-lsp)
  (add-to-list 'lsp-disabled-clients 'ruff)

  ;; Python Interpreter and Analysis Settings
  (setq lsp-pyright-python-executable-cmd
        (expand-file-name "bin/python" lsp-python-basedpyright-venv))
  (setq lsp-pyright-type-checking-mode "basic")
  ;; (setq lsp-pyright-diagnostic-severity-overrides
  ;;       '(("reportOptionalSubscript" . "error")))

  ;; Settings can affect performance and stability
  (setq lsp-pyright-use-library-code-for-types nil)
  (setq lsp-pyright-diagnostic-mode "openFilesOnly")
  (setq lsp-pyright-auto-import-completions nil)
  
  ;; Disable multi-root if it's causing project detection issues
  (setq lsp-pyright-multi-root nil))

;; Activate basedpyright on every Python buffer.  The lambda is held in a
;; local `let' binding rather than a global `defun' to keep it out of the
;; `M-x' namespace — the function is a private hook handler with no
;; standalone call site.  Thanks to `lexical-binding: t' the same closure
;; object is passed to both `add-hook' calls, so the hook stores one
;; shared reference.
;;
;; Caveat on re-evaluation: each time this form is re-loaded (e.g.
;; `eval-buffer' or `load-file'), a NEW closure object is created and `add-hook'
;; dedupes by object identity, so the new closure is appended alongside the old
;; one — the hook accumulates duplicate entries until Emacs is restarted.  We
;; need to reload this file often, we need to switch to a top-level `defun', and
;; pay the price of polluting the function namespace.
(let ((basedpyright-enable
       (lambda ()
         (require 'lsp-pyright)
         (lsp-deferred))))
  (add-hook 'python-mode-hook    basedpyright-enable)
  (add-hook 'python-ts-mode-hook basedpyright-enable))

;; Also enable LSP when editing a Python org-babel src block via `C-c ''.
;; The edit buffer is not file-backed by default, and lsp-mode silently
;; refuses to start without a `buffer-file-name'.  We associate the buffer
;; with a stable temp path derived from the source org buffer's name, so
;; basedpyright sees a real .py file.
;;
;; Activation relies on hook ordering, not an explicit LSP call here:
;;
;;   1. `python-mode-hook' fires first → the lambda above runs
;;      → `lsp-deferred' schedules LSP on `window-configuration-change-hook'.
;;   2. `org-src-mode-hook' fires next → `my/org-src-python-lsp-enable'
;;      sets `buffer-file-name' to the phantom path and writes it to disk.
;;   3. Buffer becomes visible → the scheduled `lsp' runs, reads
;;      `buffer-file-name' (already set by step 2), sends ONE `didOpen'.
;;
;; If this function itself called `lsp-deferred', step 1's pending callback
;; would fire alongside ours — basedpyright would see two `didOpen' events
;; for the same URI and log "Received redundant open text document command".

;; Forward declaration: silences the byte-compiler warning when org-src
;; hasn't been loaded yet at byte-compile time.  The real value is set by
;; org-src.el inside the edit buffer (buffer-local marker pointing into
;; the source org buffer).
(defvar org-src--beg-marker)

(defun my/org-src-python-lsp-enable ()
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (let* (;; Find the ORIGINAL org buffer the edit buffer was spawned
           ;; from.  Three fallbacks, most-reliable first:
           ;;   1. `org-src--beg-marker' — buffer-local marker set by
           ;;      org-src.el; its `marker-buffer' is the org buffer.
           ;;      This is the authoritative link in modern Org, which
           ;;      uses plain (not indirect) edit buffers.
           ;;   2. `(buffer-base-buffer)' — covers the case where Org
           ;;      ever uses indirect buffers again, or where the user
           ;;      opened the edit buffer via `clone-indirect-buffer'.
           ;;   3. `(current-buffer)' — final fallback; will yield no
           ;;      useful filename, but keeps us from crashing.
           (org-buf (or (and (markerp org-src--beg-marker)
                             (marker-buffer org-src--beg-marker))
                        (buffer-base-buffer)
                        (current-buffer)))
           ;; Directory where we'll place the phantom .py file.  Prefer
           ;; the org file's directory so basedpyright can walk up and
           ;; discover `pyproject.toml' / `pyrightconfig.json' in the
           ;; project root.  Fall back to `temporary-file-directory' if
           ;; the org buffer isn't file-backed (scratch / capture).
           (org-dir (or (and (buffer-file-name org-buf)
                             (file-name-directory (buffer-file-name org-buf)))
                        temporary-file-directory))
           ;; Keep phantom .py files out of the top-level directory by
           ;; tucking them under `._aux/'.  The leading dot hides the
           ;; directory from `ls'; `make-directory' with RECURSIVE=t is
           ;; idempotent and creates missing parents.
           (aux-dir (expand-file-name "._aux" org-dir))
           (_mkdir  (make-directory aux-dir t))
           ;; Derive the phantom name from the org file's basename, which
           ;; is guaranteed filesystem-safe (it already exists on disk),
           ;; so we skip character sanitisation and get a readable path
           ;; in the breadcrumb: `org-src-<orgbase>.py'.  `my/unique-file-path'
           ;; appends `_1', `_2', ... when needed — covers simultaneous
           ;; edits of multiple blocks from the same org file and leftover
           ;; files from a crashed prior session.
           (org-name (or (and (buffer-file-name org-buf)
                              (file-name-base (buffer-file-name org-buf)))
                         "scratch"))
           (tmp-path (my/unique-file-path
                      (expand-file-name
                       (format "org-src-%s.py" org-name)
                       aux-dir))))
      ;; Associate the edit buffer with the phantom path.  lsp-mode
      ;; checks `buffer-file-name' when deciding whether to start.
      ;; `buffer-file-truename' must be kept in sync, since lsp-mode
      ;; uses the truename for workspace bookkeeping.
      (setq-local buffer-file-name tmp-path)
      (setq-local buffer-file-truename (file-truename tmp-path))
      ;; Pre-write the buffer to disk, silently.  Without this, lsp-mode
      ;; logs "Saving file ... because it is not present on the disk"
      ;; and apheleia's diff-based formatter fails (nothing to diff
      ;; against).  `write-region' with a nil MSG arg of `no-message'
      ;; suppresses the "Wrote ..." echo-area noise.
      (write-region (point-min) (point-max) tmp-path nil 'no-message)
      (set-buffer-modified-p nil)
      ;; Delete the phantom file when the edit buffer is killed
      ;; (usually on `C-c '' exit), so artefacts do not pile up in
      ;; `._aux/'.  `tmp-path' is captured in the closure so the path
      ;; is reliable even if lsp-mode's own teardown clears
      ;; `buffer-file-name' first.
      (let ((path tmp-path))
        (add-hook 'kill-buffer-hook
                  (lambda ()
                    (when (and path (file-exists-p path))
                      (delete-file path)))
                  nil t))
      ;; Skip file watchers for this transient buffer.  Without this,
      ;; lsp-mode would try to watch every directory under
      ;; `temporary-file-directory' (or the project root) and ask for
      ;; permission above `lsp-file-watch-threshold'.
      (setq-local lsp-enable-file-watchers nil))))

(add-hook 'org-src-mode-hook #'my/org-src-python-lsp-enable)

(provide 'lsp-python-config)
;;; lsp-python-config.el ends here
