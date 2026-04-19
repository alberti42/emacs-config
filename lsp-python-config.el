;;; lsp-python-config.el --- Python LSP configuration -*- lexical-binding: t; -*-

;;; Code:

(use-package lsp-pyright
  :straight t
  :init
  ;; basedpyright-langserver lives in the pyenv version bin, which is not
  ;; in the PATH that env-config.el imports from the shell env cache file.
  (add-to-list 'exec-path (expand-file-name "~/.pyenv/versions/py313/bin"))
  (setq lsp-pyright-langserver-command "basedpyright")
  :config
  (add-to-list 'lsp-disabled-clients 'ruff-lsp)
  (add-to-list 'lsp-disabled-clients 'ruff)

  ;; Python Interpreter and Analysis Settings
  (setq lsp-pyright-python-executable-cmd (expand-file-name "~/.pyenv/versions/py313/bin/python"))
  (setq lsp-pyright-type-checking-mode "basic")
  ;; (setq lsp-pyright-diagnostic-severity-overrides
  ;;       '(("reportOptionalSubscript" . "error")))

  ;; Settings can affect performance and stability
  (setq lsp-pyright-use-library-code-for-types nil)
  (setq lsp-pyright-diagnostic-mode "openFilesOnly")
  (setq lsp-pyright-auto-import-completions nil)
  
  ;; Disable multi-root if it's causing project detection issues
  (setq lsp-pyright-multi-root nil))

(defun my/basedpyright-enable ()
  "Activate basedpyright in the current buffer via `lsp-deferred'.
Low-level helper; no skip logic — the caller is responsible for not
calling this in situations where LSP shouldn't start."
  (require 'lsp-pyright)
  (lsp-deferred))

(defun my/basedpyright-enable-skip-org-src ()
  "`python-mode-hook'-safe wrapper around `my/basedpyright-enable'.
Skips org-src edit buffers because `org-src-mode-hook' (installed below)
is their authoritative activation path; otherwise both hooks would fire
`lsp-deferred' in the same buffer and cause two `didOpen' events for the
same URI, which pyright logs as \"Received redundant open text document
command\".  The buffer name for an edit-special buffer always starts
with `*Org Src '."
  (unless (string-prefix-p "*Org Src " (buffer-name))
    (my/basedpyright-enable)))

(add-hook 'python-mode-hook    #'my/basedpyright-enable-skip-org-src)
(add-hook 'python-ts-mode-hook #'my/basedpyright-enable-skip-org-src)

;; Also enable LSP when editing a Python org-babel src block via `C-c ''.
;; `org-src-mode-hook' fires inside the edit-special buffer after its major
;; mode (python-mode / python-ts-mode) is set.
;;
;; The edit buffer is not file-backed by default, and lsp-mode silently
;; refuses to start without a `buffer-file-name'.  We associate the buffer
;; with a stable temp path derived from the source org buffer's name, so
;; basedpyright sees a real .py file.  The file is never actually written;
;; lsp-mode relies on the in-memory document sync protocol.  On `C-c '' exit,
;; the edit buffer is killed and the stale association disappears.

;; Forward declaration: silences the byte-compiler warning when org-src
;; hasn't been loaded yet at byte-compile time.  The real value is set by
;; org-src.el inside the edit buffer (buffer-local marker pointing into
;; the source org buffer).
(defvar org-src--beg-marker)

;; Monotonic counter for phantom .py filenames.  Each `C-c '' increments
;; it, so each edit session gets a distinct URI (e.g. `org-src-foo-1.py',
;; `org-src-foo-2.py').  Without this, reusing the same path could trigger
;; basedpyright's "Received redundant open text document command" warning
;; on reopen.  Resets at Emacs restart; `my/unique-file-path' handles
;; leftover files from a crashed session.
(defvar my/org-src-lsp-counter 0)

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
           ;; in the breadcrumb: `org-src-<orgbase>-<N>.py'.  The counter
           ;; keeps successive `C-c '' on the same block from landing on
           ;; the same path.  `my/unique-file-path' guards against
           ;; leftover files from a crashed prior session.
           (org-name (or (and (buffer-file-name org-buf)
                              (file-name-base (buffer-file-name org-buf)))
                         "scratch"))
           (counter  (setq my/org-src-lsp-counter
                           (1+ my/org-src-lsp-counter)))
           (tmp-path (my/unique-file-path
                      (expand-file-name
                       (format "org-src-%s-%d.py" org-name counter)
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
      (setq-local lsp-enable-file-watchers nil))
    ;; Start basedpyright.  Use the low-level helper directly, not the
    ;; `-skip-org-src' wrapper — we ARE the authoritative path for
    ;; org-src edit buffers.
    (my/basedpyright-enable)))

(add-hook 'org-src-mode-hook #'my/org-src-python-lsp-enable)

(provide 'lsp-python-config)
;;; lsp-python-config.el ends here
