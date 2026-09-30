;;; buffers-config.el --- Module to manage interaction with buffers -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; General hub for buffer interaction — anything that shapes how the user lists,
;; navigates, or manages the lifecycle of buffers.

;;; Code:

;;; -- ibuffer-mode setup ------------------------------------------------------

;; Replaces `list-buffers' with `ibuffer': a dired-like buffer list with
;; marking, filtering (`/'), sorting (`s'), and grouping.  Buffers are grouped
;; by `project.el' root via `ibuffer-project', and decorated with nerd-icons.


(use-package ibuffer
  :straight nil
  :bind ([remap list-buffers] . ibuffer)
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil)
  (ibuffer-default-sorting-mode 'recency))

;; Group buffers by project.el root.  `ibuffer-hook' (not `ibuffer-mode-hook')
;; fires on every invocation so the groups refresh as projects come and go.
(use-package ibuffer-project
  :after ibuffer
  :custom
  (ibuffer-project-use-cache t)
  :hook (ibuffer . buffers-config--apply-project-groups)
  ;; `ibuffer-project' defines the `project-root' filter but binds no key.
  ;; Put it on `/ p' (mnemonic: project).  This shadows `ibuffer-pop-filter',
  ;; which stays reachable on `/ <up>'.
  :bind (:map ibuffer--filter-map
              ("p" . ibuffer-filter-by-project-root))
  :preface
  (defun buffers-config--apply-project-groups ()
    (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups))
    (unless (eq ibuffer-sorting-mode 'project-file-relative)
      (ibuffer-do-sort-by-project-file-relative))))

;; Nerd-font icons in the ibuffer columns (same icon font as dired/treemacs).
(use-package nerd-icons-ibuffer
  :after (ibuffer nerd-icons)
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

;;; -- Suppress kill buffer prompt for unmodified buffers ----------------------

;; Suppress the "Buffer modified; kill anyway?" prompt when the buffer content
;; is identical to the saved file — i.e. the user made edits and then undid
;; them all.  We compare decoded buffer text against the file on disk; the read
;; only happens when the buffer is already flagged as modified, so the cost is
;; paid only in the rare case where it actually matters.

(defun my/maybe-unmark-modified ()
  "Clear the modified flag if buffer content matches the saved file.
Runs in `kill-buffer-query-functions' before the kill prompt fires.
`buffer-file-name' can carry a spurious trailing slash (e.g. through a
symlink chain that used to end in a directory); `directory-file-name'
strips it so `insert-file-contents' doesn't fail with \"Not a directory\".
Any remaining `file-error' (permissions, a race with deletion) is caught
so it can't abort the kill outright — it just skips the optimization."
  (when (and buffer-file-name
             (buffer-modified-p)
             (file-readable-p buffer-file-name))
    (condition-case nil
        (let* ((file (directory-file-name buffer-file-name))
               (buf-text (buffer-substring-no-properties (point-min) (point-max)))
               (file-text (with-temp-buffer
                            (insert-file-contents file)
                            (buffer-substring-no-properties (point-min) (point-max)))))
          (when (string= buf-text file-text)
            (set-buffer-modified-p nil)))
      (file-error nil)))
  t)

(add-hook 'kill-buffer-query-functions #'my/maybe-unmark-modified)

;;; -- Quick jump to *scratch* -------------------------------------------------

;; Override the global `set-goal-column' binding: reaching a scratch buffer is
;; far more useful day to day.  `set-goal-column' is still reachable via M-x.
;;
;;   C-x C-n         -> the shared *scratch* buffer (built-in `scratch-buffer')
;;   C-u C-x C-n     -> a *<mode>-scratch* buffer, prompting for the major mode
;;   C-u C-u C-x C-n -> ditto, in the current buffer's mode

(defvar buffers-config-scratch-mode-alist
  '((sql-interactive-mode     . sql-mode)
    (shell-mode               . sh-mode)
    (eshell-mode              . sh-mode)
    (inferior-python-mode     . python-mode)
    (inferior-emacs-lisp-mode . emacs-lisp-mode))
  "Alist mapping interactive major modes to their source-mode counterparts.
Consulted when `C-u C-u \\[buffers-config-scratch]' derives the mode of a
new scratch.")

(defun buffers-config-scratch (arg)
  "Switch to a scratch buffer.
No prefix ARG: pop to the shared `*scratch*' buffer (`scratch-buffer').
`C-u': pop to a scratch buffer, prompting for the major mode.
`C-u C-u': pop to a scratch buffer whose major mode matches the current buffer.
Each mode has one scratch buffer, `*<mode>-scratch*', reused on later calls.
With an active region, its contents seed a newly-created scratch."
  (interactive "P")
  (if (not arg)
      (scratch-buffer)
    (let* ((prompt (not (equal arg '(16))))
           (mode (cond
                  (prompt
                   (let (modes)
                     (mapatoms
                      (lambda (sym)
                        (let ((name (symbol-name sym)))
                          (when (and (commandp sym)
                                     (string-suffix-p "-mode" name)
                                     (not (string-match-p "--" name)))
                            (push name modes)))))
                     (intern (completing-read "Major mode: " modes nil t))))
                  ((cdr (assq major-mode buffers-config-scratch-mode-alist)))
                  (t major-mode)))
           (name (format "*%s-scratch*"
                         (replace-regexp-in-string
                          "-mode\\'" "" (symbol-name mode))))
           (existing (get-buffer name))
           (region (and (use-region-p)
                        (buffer-substring-no-properties
                         (region-beginning) (region-end)))))
      (pop-to-buffer
       (or existing
           (with-current-buffer (get-buffer-create name)
             (funcall mode)
             (when region (insert region))
             (current-buffer)))))))

(keymap-global-set "C-x C-n" #'buffers-config-scratch)

;;; -- Project buffer list via ibuffer -----------------------------------------

;; `C-x p C-b' (`project-list-buffers') defaults to the
;; `project-list-buffers-buffer-menu' viewer (a `Buffer-menu-mode' listing).
;; Switch the viewer to `project-list-buffers-ibuffer' so the project buffer
;; list gets the same grouping, filtering, and nerd-icons decoration as the
;; global buffer list.  No rebinding needed: `C-x p C-b' already runs
;; `project-list-buffers', which dispatches through `project-buffers-viewer'.
(with-eval-after-load 'project
  (setopt project-buffers-viewer 'project-list-buffers-ibuffer))

(provide 'buffers-config)
;;; buffers-config.el ends here
