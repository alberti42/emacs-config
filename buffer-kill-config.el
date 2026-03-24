;;; buffer-kill-config.el --- Smart kill-buffer behaviour -*- lexical-binding: t; -*-

;; Suppress the "Buffer modified; kill anyway?" prompt when the buffer content
;; is identical to the saved file — i.e. the user made edits and then undid
;; them all.  We compare decoded buffer text against the file on disk; the read
;; only happens when the buffer is already flagged as modified, so the cost is
;; paid only in the rare case where it actually matters.

(defun emacs-config--maybe-unmark-modified ()
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

(add-hook 'kill-buffer-query-functions #'emacs-config--maybe-unmark-modified)

(provide 'buffer-kill-config)
;;; buffer-kill-config.el ends here
