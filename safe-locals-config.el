;;; safe-locals-config.el --- Trusted directory-local variables -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `safe-local-variable-directories' lists the directories whose
;; `.dir-locals.el' is trusted wholesale, risky variables included.  Which
;; projects those are is a per-machine fact accumulated one approval at a
;; time, so the list lives in a file under `emacs-config-state-dir' rather
;; than in this repo: nothing can reconstruct it, but losing it only means
;; re-approving a few projects.
;;
;; The file exists because Emacs's own way of growing that list does not work
;; here.  Answering `+' at the "unsafe local variables" prompt calls
;; `customize-push-and-save', which writes to `custom-file' -- and
;; `emacs-config-core.el' deliberately never loads that file, so every `+'
;; would be forgotten at the next restart.  `safe-locals-add-directory' is the
;; replacement: same effect, persisted somewhere this config reads.
;;
;; Paths in the file may use `~' and are expanded and given a trailing slash
;; on load.  Emacs currently compares with `file-equal-p', which would accept
;; an abbreviated name anyway, but the documented contract of
;; `safe-local-variable-directories' is absolute names ending in a slash, so
;; that is what it is handed.
;;

;;; Code:

(require 'seq)

(defvar safe-locals-file
  (emacs-config-state-file "safe-directories.eld")
  "File holding the directories whose dir-locals are trusted.
One Lisp list of strings, read by `safe-locals-apply' and rewritten by
`safe-locals-add-directory'.")

(defun safe-locals--read ()
  "Return the list of directories in `safe-locals-file', or nil.
A missing file is normal (nothing trusted yet); an unreadable or
malformed one is reported and treated as empty, since refusing to start
over a list of conveniences would be the worse failure."
  (when (file-readable-p safe-locals-file)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents safe-locals-file)
          (goto-char (point-min))
          (seq-filter #'stringp (read (current-buffer))))
      (error
       (display-warning 'safe-locals
                        (format "Cannot read %s: %s"
                                safe-locals-file (error-message-string err))
                        :warning)
       nil))))

(defun safe-locals-apply ()
  "Add every directory in `safe-locals-file' to `safe-local-variable-directories'."
  (interactive)
  (dolist (dir (safe-locals--read))
    (add-to-list 'safe-local-variable-directories
                 (file-name-as-directory (expand-file-name dir)))))

(defun safe-locals-add-directory (dir)
  "Trust the directory-local variables in DIR, remembering it across restarts.
Persists to `safe-locals-file' and applies the change now.  Use this
instead of the `+' answer at the unsafe-local-variables prompt, which
would write to the unloaded `custom-file'."
  (interactive "DTrust dir-locals in directory: ")
  (let* ((dir (abbreviate-file-name
               (file-name-as-directory (expand-file-name dir))))
         (dirs (delete-dups (append (safe-locals--read) (list dir)))))
    (with-temp-file safe-locals-file
      (insert ";;; Directories whose dir-locals are trusted  -*- lisp-data -*-\n"
              ";;; Written by `safe-locals-add-directory'; hand-editing is fine.\n")
      (pp dirs (current-buffer)))
    (safe-locals-apply)
    (message "Trusting dir-locals in %s" dir)))

(safe-locals-apply)

(provide 'safe-locals-config)
;;; safe-locals-config.el ends here
