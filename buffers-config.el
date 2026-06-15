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
Runs in `kill-buffer-query-functions' before the kill prompt fires."
  (when (and buffer-file-name
             (buffer-modified-p)
             (file-readable-p buffer-file-name))
    (let* ((file buffer-file-name)
           (buf-text (buffer-substring-no-properties (point-min) (point-max)))
           (file-text (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-substring-no-properties (point-min) (point-max)))))
      (when (string= buf-text file-text)
        (set-buffer-modified-p nil))))
  t)

(add-hook 'kill-buffer-query-functions #'my/maybe-unmark-modified)

;;; -- Quick jump to *scratch* -------------------------------------------------

;; Override the global `set-goal-column' binding: reaching a scratch buffer is
;; far more useful day to day.  `set-goal-column' is still reachable via M-x.
;;
;;   C-x C-n         -> the shared *scratch* buffer (built-in `scratch-buffer')
;;   C-u C-x C-n     -> a fresh, uniquely-named empty `markdown-ts-mode' scratch buffer
;;   C-u C-u C-x C-n -> ditto, but in `lisp-interaction-mode'

(defun buffers-config-scratch (&optional arg)
  "Switch to the shared *scratch* buffer.
With a single prefix ARG, create and switch to a fresh, uniquely-named
empty scratch buffer in `markdown-ts-mode'.  With a double prefix ARG,
use `lisp-interaction-mode' instead."
  (interactive "P")
  (if (not arg)
      (scratch-buffer)
    (let* ((lisp (equal arg '(16)))
           (buf (generate-new-buffer "*scratch*")))
      (with-current-buffer buf
        (if (not lisp)
            (markdown-ts-mode)
          (lisp-interaction-mode)
          (when (stringp initial-scratch-message)
            (insert (substitute-command-keys initial-scratch-message))
            (set-buffer-modified-p nil))))
      (switch-to-buffer buf))))

(keymap-global-set "C-x C-n" #'buffers-config-scratch)

(provide 'buffers-config)
;;; buffers-config.el ends here
