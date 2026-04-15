;;; consult.el --- Consult commands and integrations -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Consult provides a set of high-quality narrowing commands that work well
;; with Vertico (or other completing-read UIs).
;;

;;; Code:

;;; -- Debug logger ------------------------------------------------------------

(defvar consult-bm--debug nil
  "When non-nil, log calls to `consult--buffer-mode-collection'.")

(defun consult-bm--log (&rest args)
  "Append a formatted log line to *consult-bm-debug* buffer."
  (when consult-bm--debug
    (let ((buf (get-buffer-create "*consult-bm-debug*")))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert (apply #'format args) "\n")))))

(defun consult-bm-debug-toggle ()
  "Toggle debug logging for `consult-buffer-by-mode' and show the log buffer."
  (interactive)
  (setq consult-bm--debug (not consult-bm--debug))
  (if consult-bm--debug
      (progn
        (with-current-buffer (get-buffer-create "*consult-bm-debug*")
          (erase-buffer)
          (insert (format "=== consult-buffer-by-mode debug started %s ===\n"
                          (format-time-string "%H:%M:%S"))))
        (display-buffer "*consult-bm-debug*")
        (message "consult-bm debug ON"))
    (message "consult-bm debug OFF")))

;;; -- Buffer-with-mode-filter collection --------------------------------------

(defun consult--buffer-mode-collection (string pred action)
  "Completion table for live buffers supporting /MODE/QUERY syntax.

When STRING begins with /MODE/, candidates are restricted to buffers whose
`major-mode' name contains MODE (case-insensitive substring).  QUERY — the
text after the second slash — is matched by the active completion styles
\(typically orderless).  Without the prefix all live buffers are offered."
  (consult-bm--log "CALL  action=%S  string=%S  pred=%S" action string pred)
  (if (eq action 'metadata)
      (progn
        (consult-bm--log "  => metadata")
        '(metadata (category . buffer)))
    (let* ((mode-filter nil)
           (query string))
      (when (string-match "\\`/\\([^/]*\\)/\\(.*\\)\\'" string)
        (setq mode-filter (downcase (match-string 1 string))
              query       (match-string 2 string)))
      (consult-bm--log "  mode-filter=%S  query=%S" mode-filter query)
      (let* ((buffers (if mode-filter
                          (seq-filter
                           (lambda (buf)
                             (string-match-p
                              mode-filter
                              (downcase (symbol-name
                                         (buffer-local-value 'major-mode buf)))))
                           (buffer-list))
                        (buffer-list)))
             (names (mapcar #'buffer-name buffers)))
        (consult-bm--log "  candidate-count=%d  names=%S"
                         (length names) (seq-take names 5))
        (let ((result
               (pcase action
                 ('t                           ; all-completions
                  (if (string-empty-p query)
                      (if pred (seq-filter pred names) names)
                    (all-completions query names pred)))
                 ('nil                         ; try-completion
                  (let ((r (try-completion query names pred)))
                    (cond
                     ((null r) nil)
                     ((eq r t) t)
                     (mode-filter (concat "/" (match-string 1 string) "/" r))
                     (t r))))
                 (_                            ; test-completion
                  (test-completion query names pred)))))
          (consult-bm--log "  => result=%S"
                           (if (listp result)
                               (format "(list of %d)" (length result))
                             result))
          result)))))

(defun consult-buffer-by-mode ()
  "Switch to a buffer, with optional major-mode pre-filtering.

Type /MODE/QUERY to restrict candidates to buffers whose `major-mode'
name contains MODE (case-insensitive substring match), then narrow
further with QUERY using the active completion style (usually orderless).

Examples:
  /dired/src     — dired buffers whose name contains \"src\"
  /d/src         — same, MODE is a substring so \"d\" matches \"dired\"
  /py/           — all Python buffers
  myfile         — all buffers matching \"myfile\" (no mode filter)

Without the /MODE/ prefix the command behaves like a plain live-buffer
switcher.  For multi-source search (recent files, bookmarks) use
\\[consult-buffer]."
  (interactive)
  (let ((buf (consult--read
              #'consult--buffer-mode-collection
              :prompt "Buffer: "
              :category 'buffer
              :state (consult--buffer-state)
              :history 'buffer-name-history
              :require-match t
              :sort nil)))
    (when buf (switch-to-buffer (get-buffer buf)))))

;;; -- Package configuration ---------------------------------------------------

(use-package consult
  :bind (
         ;; Mode-filtered buffer switcher (supports /mode/query syntax).
         ("C-x b" . consult-buffer-by-mode)
         ;; Full multi-source switcher (buffers + recent files + bookmarks).
         ("C-x B" . consult-buffer)
         ;; A small, mnemonic prefix for search/navigation.
         ("C-c s b" . consult-buffer-by-mode)
         ("C-c s l" . consult-line)
         ("C-c s r" . consult-ripgrep)
         ("C-c s R" . consult-ripgrep-here)
         ("C-c s i" . consult-imenu)
         ("C-c s m" . consult-mark)
         ("C-c s M" . consult-global-mark)
         ("C-c s k" . consult-keep-lines)
         ("C-c s y" . consult-yank-pop)
         ("C-c s c" . consult-flycheck)
         ("C-c s e" . consult-compile-error)
         ;; Replace project-find-file with fd-backed consult-fd.
         ("C-c s f" . consult-fd)
         ("C-c s F" . consult-fd-here))
  :init
  ;; Use Consult for xref UI when available.
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Navigate minibuffer history with M-up/M-down (mirrors M-p/M-n).
  (define-key minibuffer-local-map (kbd "M-<up>") #'previous-history-element)
  (define-key minibuffer-local-map (kbd "M-<down>") #'next-history-element)

  ;; Persist search histories across sessions using built-in savehist.
  (dolist (var '(consult--grep-history
                 consult--find-history
                 consult--line-history))
    (add-to-list 'savehist-additional-variables var))

  ;; Include hidden directories in fd search, but exclude .git.
  (setq consult-fd-args '("fd" "--hidden" "--exclude" ".git" "--color=never" "--full-path"))
  :config
  ;; Preserve recentf-list order (most-recently-opened first).
  (setq consult-source-recent-file
        (plist-put consult-source-recent-file :sort nil)))

(provide 'completions-consult)
;;; consult.el ends here
