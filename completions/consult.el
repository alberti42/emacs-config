;;; consult.el --- Consult commands and integrations -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Consult provides a set of high-quality narrowing commands that work well
;; with Vertico (or other completing-read UIs).
;;

;;; Code:

;;; -- Buffer-with-mode-filter collection --------------------------------------

(defun consult--buffer-mode-collection (string pred action)
  "Completion table for live buffers supporting /MODE/QUERY syntax.

When STRING begins with /MODE/, candidates are restricted to buffers whose
`major-mode' name contains MODE (case-insensitive substring).  QUERY — the
text after the second slash — is matched by the active completion styles
\(typically orderless).  Without the prefix all live buffers are offered."
  (if (eq action 'metadata)
      '(metadata (category . buffer))
    (let* ((mode-filter nil)
           (query string))
      (when (string-match "\\`/\\([^/]*\\)/\\(.*\\)\\'" string)
        (setq mode-filter (downcase (match-string 1 string))
              query       (match-string 2 string)))
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
        (pcase action
          ('t                           ; all-completions
           (if (string-empty-p query)
               (if pred (seq-filter pred names) names)
             (all-completions query names pred)))
          ('nil                         ; try-completion
           (let ((result (try-completion query names pred)))
             (cond
              ((null result) nil)
              ((eq result t) t)
              (mode-filter (concat "/" (match-string 1 string) "/" result))
              (t result))))
          (_                            ; test-completion
           (test-completion query names pred)))))))

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
