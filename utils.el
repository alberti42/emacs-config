;;; utils.el --- General-purpose interactive utilities -*- lexical-binding: t; -*-

;; Generate and insert a UUID v4 at point.
(defun insert-uuid ()
  "Generate a random UUID v4 and insert it at point."
  (interactive)
  (insert
   (format "%08x-%04x-4%03x-%04x-%012x"
           (random (expt 16 8))
           (random (expt 16 4))
           (random (expt 16 3))
           (logior #x8000 (logand #xbfff (random (expt 16 4))))
           (random (expt 16 12)))))

;; Copy the current buffer's file path to the kill ring.
(defun copy-buffer-file-name ()
  "Copy the absolute path of the current buffer's file to the kill ring.
When called from the minibuffer, resolves the buffer that was active
before entering it.  Does nothing if the buffer does not visit a file."
  (interactive)
  (if-let* ((name (buffer-file-name (window-buffer (minibuffer-selected-window)))))
      (progn (kill-new name) (message "%s" name))
    (message "Buffer has no file name")))

(provide 'utils)
;;; utils.el ends here
