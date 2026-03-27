;;; auto-revert-config.el -*- lexical-binding: t; tab-width: 2; -*-

;; Smart file watching: silently revert unmodified buffers when the file changes
;; on disk; prompt before reverting buffers that have unsaved local edits.
;;
;; The watcher is placed on the parent directory rather than the file itself so
;; that atomic writes — which replace the file via rename(2) and would not fire
;; a `changed' event on the original path — are also detected.

(require 'filenotify)

;; File locking (`.#filename' symlinks) is redundant: this module already
;; detects external changes and prompts before overwriting them.  Lock files
;; are also meaningless for `emacsclient' where all frames share the same
;; buffer.
(setq create-lockfiles nil)

(defvar-local emacs-config--file-watcher nil
  "File notification watcher descriptor for the current buffer.")

(defvar-local emacs-config--revert-prompt-active nil
  "Non-nil while the external-change revert prompt is displayed.
Prevents a second prompt from appearing if further filesystem events arrive
before the user has answered the first one.")

(defun emacs-config--file-changed (event)
  "Handle a file change EVENT."
  (let ((action (nth 1 event)))
    (when (eq action 'deleted)
      (let ((buf (find-buffer-visiting (nth 2 event))))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (emacs-config--teardown-file-watcher)
            (message "Warning: file '%s' was deleted or moved to a different directory."
                     (buffer-name))))))
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
                ;; buffer's path to track it, then re-attach the watcher to
                ;; the new directory (the file may have moved out of the old one).
                (progn
                  (set-visited-file-name new-file t t)
                  (emacs-config--teardown-file-watcher)
                  (emacs-config--setup-file-watcher))
              ;; Content change or atomic overwrite — revert if the mtime is
              ;; new.  `verify-visited-file-modtime' returns t when Emacs
              ;; already knows about this mtime. This avoids reverting the
              ;; buffer when the change to the file is caused by Emacs
              ;; itself through a save operation. Only act when the file
              ;; genuinely changed externally.
              (unless (verify-visited-file-modtime buf)
                (emacs-config--maybe-revert buf)))))))))

(defun emacs-config--maybe-revert (buf)
  "Revert BUF after an external change, prompting if it has unsaved edits.
If a prompt is already visible for BUF (from an earlier event in the same
burst), silently skip so the user is never asked twice."
  (with-current-buffer buf
    (if (buffer-modified-p)
        ;; Unsaved local edits — ask before discarding them.  The flag
        ;; prevents re-entry: further filesystem events while the
        ;; yes-or-no-p dialogue is open are ignored.
        (unless emacs-config--revert-prompt-active
          (setq emacs-config--revert-prompt-active t)
          (unwind-protect
              (when (yes-or-no-p
                     (format "File '%s' modified externally. Revert and lose your changes? "
                             (buffer-name)))
                (revert-buffer t t t))
            (setq emacs-config--revert-prompt-active nil)))
      ;; No unsaved edits — silently revert to the new on-disk content.
      (revert-buffer t t t))))

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

;;; Dired directory watching

(defvar-local emacs-config--dired-watcher nil
  "File notification watcher descriptor for the current Dired buffer.")

(defun emacs-config--dired-setup-watcher ()
  "Attach a file-system watcher to the current Dired buffer's directory.
Uses a closure to capture the buffer so no global lookup is needed.
Fires on created/deleted/renamed events and reverts the Dired listing."
  (let ((dir (file-truename default-directory))
        (buf (current-buffer)))
    (condition-case err
        (setq-local emacs-config--dired-watcher
                    (file-notify-add-watch
                     dir '(change)
                     (lambda (event)
                       (when (buffer-live-p buf)
                         (when (memq (nth 1 event) '(created deleted renamed))
                           (with-current-buffer buf
                             (revert-buffer)))))))
      (error
       (message "auto-revert-config: could not watch directory %s: %s" dir err)))))

(defun emacs-config--dired-teardown-watcher ()
  "Remove the file-system watcher for the current Dired buffer."
  (when emacs-config--dired-watcher
    (file-notify-rm-watch emacs-config--dired-watcher)
    (setq emacs-config--dired-watcher nil)))

(add-hook 'dired-mode-hook  #'emacs-config--dired-setup-watcher)
(add-hook 'kill-buffer-hook #'emacs-config--dired-teardown-watcher)

(provide 'auto-revert-config)
