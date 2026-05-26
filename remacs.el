;;; remacs.el --- rmate-protocol server for remote file editing -*- lexical-binding: t; -*-

(require 'cl-lib)

(defgroup remacs nil
  "Server implementing the rmate protocol for editing remote files locally."
  :group 'tools
  :prefix "remacs-")

(defcustom remacs-port 52698
  "TCP port the remacs server listens on."
  :type 'integer
  :group 'remacs)

(defcustom remacs-host "127.0.0.1"
  "Host address the remacs server binds to.
Use \"127.0.0.1\" to accept only local connections (including SSH
tunnels).  Use \"0.0.0.0\" to accept connections from any interface
\(dangerous without additional firewall rules)."
  :type 'string
  :group 'remacs)

(defvar remacs--server nil
  "The active network server process, or nil.")

(defvar remacs--files (make-hash-table :test 'eq)
  "Map from buffer to its `remacs--file'.")


;;; ---- File (one per `open' command) ----

(cl-defstruct remacs--file
  "State for a single file opened via the rmate protocol."
  session
  env
  (data nil)
  (current-data-length 0)
  (file-size nil)
  (ready nil)
  host
  base-name
  temp-dir
  temp-path)

(defun remacs--file-append (file chunk)
  "Append CHUNK (a unibyte string) to FILE, trimming at file-size."
  (let* ((remaining (- (remacs--file-file-size file)
                       (remacs--file-current-data-length file)))
         (to-take (min remaining (length chunk)))
         (piece (if (< to-take (length chunk))
                    (substring chunk 0 to-take)
                  chunk)))
    (setf (remacs--file-data file)
          (nconc (remacs--file-data file) (list piece)))
    (cl-incf (remacs--file-current-data-length file) (length piece))
    (when (= (remacs--file-current-data-length file)
             (remacs--file-file-size file))
      (setf (remacs--file-ready file) t))))

(defun remacs--file-get-text (file)
  "Return the accumulated content of FILE as a single unibyte string."
  (apply #'concat (remacs--file-data file)))

(defun remacs--file-send-save (file)
  "Send save response for FILE back to the rmate client."
  (let* ((session (remacs--file-session file))
         (process (remacs--connection-process session))
         (temp-path (remacs--file-temp-path file))
         (content (with-temp-buffer
                    (set-buffer-multibyte nil)
                    (insert-file-contents-literally temp-path)
                    (buffer-string)))
         (token (cdr (assoc "token" (remacs--file-env file)))))
    (process-send-string process
                         (concat "save\n"
                                 "token: " token "\n"
                                 "data: " (number-to-string (length content)) "\n"))
    (process-send-string process content)
    (process-send-string process "\n")))

(defun remacs--file-send-close (file)
  "Send close response for FILE and decrement the connection count."
  (let* ((session (remacs--file-session file))
         (process (remacs--connection-process session))
         (token (cdr (assoc "token" (remacs--file-env file)))))
    (when (process-live-p process)
      (process-send-string process
                           (concat "close\n"
                                   "token: " token "\n"
                                   "\n")))
    (remacs--connection-dec session)))

(defun remacs--file-open (file)
  "Write FILE data to a temp file and open it in Emacs."
  (let* ((env (remacs--file-env file))
         (display-name (or (cdr (assoc "display-name" env)) "untitled"))
         (host-and-name (if (string-match ":" display-name)
                            (cons (substring display-name 0 (match-beginning 0))
                                  (file-name-nondirectory
                                   (substring display-name (match-end 0))))
                          (cons nil (file-name-nondirectory display-name))))
         (token (cdr (assoc "token" env))))
    (setf (remacs--file-host file) (car host-and-name))
    (setf (remacs--file-base-name file)
          (if (string= token "-") "untitled" (cdr host-and-name)))
    (let* ((temp-dir (make-temp-file
                      (concat (or (remacs--file-host file) "remacs") "-") t))
           (temp-path (expand-file-name (remacs--file-base-name file) temp-dir)))
      (setf (remacs--file-temp-dir file) temp-dir)
      (setf (remacs--file-temp-path file) temp-path)
      (let ((coding-system-for-write 'no-conversion))
        (with-temp-file temp-path
          (set-buffer-multibyte nil)
          (insert (remacs--file-get-text file))))
      (setf (remacs--file-data file) nil)
      (let ((buf (find-file-noselect temp-path)))
        (with-current-buffer buf
          (rename-buffer (format "%s [remote]" display-name) t)
          (let ((selection (cdr (assoc "selection" env))))
            (when selection
              (let ((line (string-to-number (car (split-string selection ":")))))
                (when (> line 0)
                  (goto-char (point-min))
                  (forward-line (1- line)))))))
        (puthash buf file remacs--files)
        (pop-to-buffer buf)
        (select-frame-set-input-focus (selected-frame))
        (message "[remacs] opened %s" display-name)))))

(defun remacs--file-cleanup (file)
  "Remove temp files for FILE."
  (ignore-errors
    (when (remacs--file-temp-path file)
      (delete-file (remacs--file-temp-path file)))
    (when (remacs--file-temp-dir file)
      (delete-directory (remacs--file-temp-dir file)))))


;;; ---- Connection (one per TCP client) ----

(cl-defstruct remacs--connection
  "State for one TCP connection from an rmate client."
  process
  (parsing-data nil)
  (nconn 0)
  (file nil))

(defun remacs--connection-dec (conn)
  "Decrement CONN's open-file count; close socket when it reaches zero."
  (cl-decf (remacs--connection-nconn conn))
  (when (<= (remacs--connection-nconn conn) 0)
    (let ((process (remacs--connection-process conn)))
      (when (process-live-p process)
        (delete-process process)))))


;;; ---- Per-connection buffer-local state ----

(defvar-local remacs--conn nil
  "The `remacs--connection' for this process buffer.")

(defvar-local remacs--buf ""
  "Unprocessed bytes carried across filter calls.")


;;; ---- Network plumbing ----

(defun remacs--filter (process output)
  "Accumulate OUTPUT from PROCESS and dispatch lines."
  (let ((pbuf (process-buffer process)))
    (when (buffer-live-p pbuf)
      (with-current-buffer pbuf
        (setq remacs--buf (concat remacs--buf output))
        (remacs--dispatch)))))

(defun remacs--dispatch ()
  "Consume complete lines (or data chunks) from `remacs--buf'."
  (catch 'need-more
    (while (> (length remacs--buf) 0)
      (if (and (remacs--connection-parsing-data remacs--conn)
               (remacs--connection-file remacs--conn))
          ;; Data mode: feed bytes to the current file.
          (let* ((file (remacs--connection-file remacs--conn))
                 (remaining (- (remacs--file-file-size file)
                               (remacs--file-current-data-length file))))
            (if (= remaining 0)
                (setf (remacs--connection-parsing-data remacs--conn) nil)
              (let* ((to-take (min remaining (length remacs--buf)))
                     (chunk (substring remacs--buf 0 to-take)))
                (setq remacs--buf (substring remacs--buf to-take))
                (remacs--file-append file chunk)
                (when (remacs--file-ready file)
                  (setf (remacs--connection-parsing-data remacs--conn) nil)
                  (remacs--file-open file)
                  (setf (remacs--connection-file remacs--conn) nil)))))
        ;; Line mode: wait for a complete line.
        (let ((nl (cl-position ?\n remacs--buf)))
          (unless nl (throw 'need-more nil))
          (let ((line (substring remacs--buf 0 nl)))
            (setq remacs--buf (substring remacs--buf (1+ nl)))
            (remacs--parse-line (string-trim line))))))))

(defun remacs--parse-line (line)
  "Handle one protocol LINE in header/command mode."
  (let ((conn remacs--conn))
    (cond
     ;; "open" command: start a new file.
     ((string= line "open")
      (let ((file (make-remacs--file :session conn :env nil)))
        (setf (remacs--connection-file conn) file)
        (cl-incf (remacs--connection-nconn conn))))

     ;; "." means end of commands.
     ((string= line "."))

     ;; Empty line after headers: ignored (separator between data and
     ;; next command, or trailing blank).
     ((string= line ""))

     ;; No current file — nothing to attach headers to.
     ((null (remacs--connection-file conn)))

     ;; Header line: "key: value".
     ((string-match "\\`\\([^:]+\\):\\(.*\\)" line)
      (let* ((key (match-string 1 line))
             (val (string-trim (match-string 2 line)))
             (file (remacs--connection-file conn)))
        (push (cons key val) (remacs--file-env file))
        (when (string= key "data")
          (setf (remacs--file-file-size file) (string-to-number val))
          (setf (remacs--connection-parsing-data conn) t))))

     (t
      (message "[remacs] ignoring unknown line: %s" line)))))

(defun remacs--sentinel (process event)
  "Handle PROCESS lifecycle EVENT."
  (when (string-match-p "\\(deleted\\|connection broken\\|finished\\)" event)
    (let ((buf (process-buffer process)))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(defun remacs--accept (_server client _message)
  "Initialize a new CLIENT connection."
  (let ((buf (generate-new-buffer " *remacs-conn*")))
    (set-process-buffer client buf)
    (with-current-buffer buf
      (setq remacs--conn (make-remacs--connection :process client))
      (setq remacs--buf ""))
    (set-process-filter client #'remacs--filter)
    (set-process-sentinel client #'remacs--sentinel)
    (set-process-coding-system client 'binary 'binary)
    (process-send-string client "remacs\n")))


;;; ---- Hooks ----

(defun remacs--on-save ()
  "After-save hook: send buffer contents back to the rmate client."
  (let ((file (gethash (current-buffer) remacs--files)))
    (when file
      (condition-case err
          (progn
            (remacs--file-send-save file)
            (message "[remacs] saved %s"
                     (or (cdr (assoc "display-name" (remacs--file-env file)))
                         "?")))
        (error (message "[remacs] save error: %s" err))))))

(defun remacs--on-kill ()
  "Kill-buffer hook: send close to the rmate client and clean up."
  (let ((file (gethash (current-buffer) remacs--files)))
    (when file
      (ignore-errors (remacs--file-send-close file))
      (remacs--file-cleanup file)
      (remhash (current-buffer) remacs--files))))


;;; ---- Public API ----

;;;###autoload
(defun remacs-start ()
  "Start the remacs server."
  (interactive)
  (when remacs--server
    (user-error "remacs server already running on port %d" remacs-port))
  (setq remacs--server
        (make-network-process
         :name "remacs"
         :server t
         :host remacs-host
         :service remacs-port
         :family 'ipv4
         :coding 'binary
         :log #'remacs--accept))
  (add-hook 'after-save-hook #'remacs--on-save)
  (add-hook 'kill-buffer-hook #'remacs--on-kill)
  (message "[remacs] server listening on %s:%d" remacs-host remacs-port))

;;;###autoload
(defun remacs-stop ()
  "Stop the remacs server and close all sessions."
  (interactive)
  (unless remacs--server
    (user-error "remacs server is not running"))
  (delete-process remacs--server)
  (setq remacs--server nil)
  (remove-hook 'after-save-hook #'remacs--on-save)
  (remove-hook 'kill-buffer-hook #'remacs--on-kill)
  (maphash (lambda (_buf file)
             (ignore-errors
               (let* ((session (remacs--file-session file))
                      (process (remacs--connection-process session)))
                 (when (process-live-p process)
                   (delete-process process))))
             (remacs--file-cleanup file))
           remacs--files)
  (clrhash remacs--files)
  (message "[remacs] server stopped"))

(provide 'remacs)
;;; remacs.el ends here
