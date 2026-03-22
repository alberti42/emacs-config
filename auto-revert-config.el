;;; auto-revert-config.el -*- lexical-binding: t; tab-width: 2; -*-

;; Smart file watching: silently revert unmodified buffers when the file changes
;; on disk; prompt before reverting buffers that have unsaved local edits.
;;
;; The watcher is placed on the parent directory rather than the file itself so
;; that atomic writes — which replace the file via rename(2) and would not fire
;; a `changed' event on the original path — are also detected.

(require 'filenotify)

(defvar-local emacs-config--file-watcher nil
  "File notification watcher descriptor for the current buffer.")

(defun emacs-config--file-changed (event)
  "Handle a file change EVENT."
  (let ((action (nth 1 event)))
    (when (memq action '(changed created renamed))
      (let* ((old-file (nth 2 event))
             (new-file (if (eq action 'renamed) (nth 3 event) (nth 2 event)))
             ;; For a rename: check slot-3 first (atomic overwrite of an open
             ;; file), then slot-2 (the open file itself was renamed).
             (buf (or (find-buffer-visiting new-file)
                      (and (eq action 'renamed)
                           (find-buffer-visiting old-file)))))
        (when (buffer-live-p buf) ; if the buffer is alive (not killed)
          (with-current-buffer buf
            (if (and (eq action 'renamed)
                     (equal buffer-file-name (file-truename old-file)))
                ;; The file this buffer was visiting got renamed — update the
                ;; buffer's path to track it.
                (set-visited-file-name new-file t t)
              ;; Content change or atomic overwrite — revert if the mtime is
              ;; new.  `verify-visited-file-modtime' returns t when Emacs
              ;; already knows about this mtime. This avoids reverting the
              ;; buffer when the change to the file is caused by Emacs
              ;; itself through a save operation. Only act when the file
              ;; genuinely changed externally.
              (unless (verify-visited-file-modtime buf)
                ;; `buffer-modified-p' is an internal flag that Emacs sets
                ;; when the buffer is changed and clears when the buffer
                ;; is saved.
                (if (buffer-modified-p)
                    ;; Unsaved local edits — ask before discarding them.
                    (when (yes-or-no-p
                           (format "File '%s' modified externally. Revert and lose your changes? "
                                   (buffer-name)))
                      (revert-buffer t t t))
                  ;; The buffer did not contain any changes in Emacs, but
                  ;; it has been changed externally. In this case, we
                  ;; silently revert to the changed version on disk.
                  (revert-buffer t t t))))))))))

(defun emacs-config--setup-file-watcher ()
  "Attach a file-system watcher to the current buffer's file's directory.
Watching the directory (rather than the file itself) ensures that atomic
writes — which replace the file via rename(2) — are also detected."
  (when (and buffer-file-name (file-exists-p buffer-file-name))
    (let ((dir (file-name-directory (file-truename buffer-file-name))))
      (condition-case err
          (setq-local emacs-config--file-watcher
                      (file-notify-add-watch dir
                                             '(change)
                                             #'emacs-config--file-changed))
        (error
         (message "auto-revert-config: could not watch %s: %s"
                  buffer-file-name err))))))

(defun emacs-config--teardown-file-watcher ()
  "Remove the file-system watcher when the buffer is killed."
  (when emacs-config--file-watcher
    (file-notify-rm-watch emacs-config--file-watcher)
    (setq emacs-config--file-watcher nil)))

(add-hook 'find-file-hook  #'emacs-config--setup-file-watcher)
(add-hook 'kill-buffer-hook #'emacs-config--teardown-file-watcher)

(provide 'auto-revert-config)
