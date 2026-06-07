;;; utils.el --- General-purpose interactive utilities -*- lexical-binding: t; -*-

;;; -- Utilities to produce UUID -----------------------------------------------

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

;;; -- Utilities to interact with current buffer -------------------------------

(defun reveal-file (path)
  "Reveal PATH in the system file manager, selecting it.
On macOS uses `open -R'; on Linux sends a D-Bus ShowItems request
to org.freedesktop.FileManager1."
  (cond
   ((eq system-type 'darwin)
    (call-process "open" nil 0 nil "-R" (expand-file-name path)))
   ((eq system-type 'gnu/linux)
    (call-process "dbus-send" nil 0 nil
                  "--session"
                  "--dest=org.freedesktop.FileManager1"
                  "--type=method_call"
                  "/org/freedesktop/FileManager1"
                  "org.freedesktop.FileManager1.ShowItems"
                  (concat "array:string:file://" (expand-file-name path))
                  "string:"))
   (t (user-error "reveal-file: unsupported system type `%s'" system-type))))

(defun open-file-with-os-default (path)
  "Open PATH with the OS default application.
On macOS uses `open'; on Linux uses `xdg-open'."
  (cond
   ((eq system-type 'darwin)
    (call-process "open" nil 0 nil (expand-file-name path)))
   ((eq system-type 'gnu/linux)
    (call-process "xdg-open" nil 0 nil (expand-file-name path)))
   (t (user-error "open-file-with-os-default: unsupported system type `%s'" system-type))))

(defun reveal-buffer-file ()
  "Reveal the file visited by the current buffer in the system file manager.
Does nothing if the buffer does not visit a file."
  (interactive)
  (if-let* ((path (buffer-file-name (window-buffer (minibuffer-selected-window)))))
      (reveal-file path)
    (message "Buffer has no file name")))

;; Copy the current buffer's file path to the kill ring.
(defun copy-buffer-file-name (&optional name-only)
  "Copy the current buffer's file path to the kill ring.
With a prefix argument (\\[universal-argument]), copy only the file name
without the directory.  When called from the minibuffer, resolves the
buffer that was active before entering it.  Does nothing if the buffer
does not visit a file."
  (interactive "P")
  (if-let* ((path (buffer-file-name (window-buffer (minibuffer-selected-window)))))
      (let ((name (if name-only (file-name-nondirectory path) path)))
        (kill-new name) (message "%s" name))
    (message "Buffer has no file name")))

(defun emacs-uri-for-buffer (&optional buffer)
  "Return an emacs:// URL for BUFFER (default current) at point.
Signal a `user-error' if the buffer is not visiting a file."
  (with-current-buffer (or buffer (current-buffer))
    (let ((file (buffer-file-name)))
      (unless file
        (user-error "Buffer %s is not visiting a file" (buffer-name)))
      (let* ((path (expand-file-name file))
             ;; Hexify each path segment but keep "/" as separators.
             (encoded (mapconcat #'url-hexify-string (split-string path "/") "/")))
        (format "emacs://file%s+%d:%d"
                encoded
                (line-number-at-pos)
                (1+ (current-column)))))))

;;;###autoload
(defun emacs-uri-copy ()
  "Copy an emacs:// URL for the current buffer at point to the kill ring."
  (interactive)
  (let ((uri (emacs-uri-for-buffer)))
    (kill-new uri)
    (message "Copied: %s" uri)))

;;; -- Filesystem utilities ----------------------------------------------------

;;;###autoload
(defun my/unique-file-path (candidate)
  "Return CANDIDATE if no file exists at that path, else append `_N'
before the extension (N = 1, 2, 3, ...) until a free slot is found.
Example: `foo.py' -> `foo_1.py' -> `foo_2.py' -> ...
The directory part of CANDIDATE is preserved; only the filename is
incremented."
  (if (not (file-exists-p candidate))
      candidate
    (let* ((dir  (file-name-directory candidate))
           (base (file-name-base candidate))
           (ext  (file-name-extension candidate t)) ; includes leading dot
           (n    1)
           next)
      (while (file-exists-p
              (setq next (expand-file-name
                          (format "%s_%d%s" base n ext)
                          dir)))
        (setq n (1+ n)))
      next)))

;;; -- Mode-specific scratch buffers -------------------------------------------

(defvar my/scratch-mode-alist
  '((sql-interactive-mode     . sql-mode)
    (shell-mode               . sh-mode)
    (eshell-mode              . sh-mode)
    (inferior-python-mode     . python-mode)
    (inferior-emacs-lisp-mode . emacs-lisp-mode))
  "Alist mapping interactive major modes to their source-mode counterparts.
Consulted when `C-u \\[scratch-buffer]' derives the mode of a new scratch.")

(defun my/scratch-buffer-advice (orig-fun &rest args)
  "Route prefix-arg invocations of `scratch-buffer' to mode-specific scratches.
No prefix: original behaviour (pop to the shared `*scratch*' buffer).
`C-u': new scratch buffer whose major mode matches the current buffer.
`C-u C-u': new scratch buffer, prompting for the major mode.
With an active region, its contents seed a newly-created scratch."
  (pcase current-prefix-arg
    ('nil (apply orig-fun args))
    (arg
     (let* ((prompt (not (equal arg '(4))))
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
                   ((cdr (assq major-mode my/scratch-mode-alist)))
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
              (current-buffer))))))))

(advice-add 'scratch-buffer :around #'my/scratch-buffer-advice)

;;; -- Set of opinionated utilities --------------------------------------------
;;
;; This package was not tested yet, therefore it is commented out for now.

(when nil
  (use-package crux
    :bind
    (
     ;; ("C-c o"           . crux-open-with)                                    ; Open the visited file with an external program (prompts for one if not associated).
     ;; ("C-k"             . crux-smart-kill-line)                              ; Kill to end of line; if already at end, kill the whole line including newline.
     ;; ("s-k"             . crux-smart-kill-line)                              ; Same as above, macOS Super key variant.
     ;; ("C-S-<return>"    . crux-smart-open-line-above)                        ; Insert a new indented line above the current one, like pressing Return at the start of the line.
     ;; ("s-o"             . crux-smart-open-line-above)                        ; Same as above, macOS Super key variant.
     ;; ("S-<return>"      . crux-smart-open-line)                              ; Insert a new indented line below the current one without moving to it first, like most IDEs.
     ;; ("M-o"             . crux-smart-open-line)                              ; Same as above, Alt key variant. NOTE: conflicts with crux-other-window-or-switch-buffer.
     ;; ("C-c n"           . crux-cleanup-buffer-or-region)                     ; Re-indent the buffer (or region) and strip trailing whitespace throughout.
     ;; ("C-c f"           . crux-recentf-find-file)                            ; Pick a recently visited file from a completing-read list. NOTE: may conflict with recentf-config.el.
     ;; ("s-r"             . crux-recentf-find-file)                            ; Same as above, macOS Super key variant.
     ;; ("C-c F"           . crux-recentf-find-directory)                       ; Pick a recently visited directory and open it in Dired.
     ;; ("C-c u"           . crux-view-url)                                     ; Prompt for a URL and open its contents in a read-only Emacs buffer.
     ;; ("C-c e"           . crux-eval-and-replace)                             ; Evaluate the Elisp expression before point and replace it in-buffer with its printed result.
     ;; ("C-x 4 t"         . crux-transpose-windows)                            ; Swap the buffers displayed in the two most recently used windows.
     ;; ("C-c D"           . crux-delete-file-and-buffer)                       ; Delete the file visited by the current buffer from disk and kill the buffer.
     ;; ("C-c c"           . crux-copy-file-preserve-attributes)                ; Copy the current file to a new path, preserving permissions and timestamps.
     ;; ("C-c d"           . crux-duplicate-current-line-or-region)             ; Duplicate the current line, or the active region, inserting the copy immediately below.
     ;; ("C-c M-d"         . crux-duplicate-and-comment-current-line-or-region) ; Duplicate the current line (or region) and comment out the original, leaving the copy live.
     ;; ("C-c r"           . crux-rename-file-and-buffer)                       ; Rename the file on disk and update the buffer name and path in one step.
     ;; ("C-c t"           . crux-visit-term-buffer)                            ; Switch to (or create) an ansi-term buffer. NOTE: may conflict with terminal-config.el.
     ;; ("C-c z"           . crux-visit-shell-buffer)                           ; Switch to (or create) an eshell buffer. NOTE: may conflict with terminal-config.el.
     ;; ("C-c k"           . crux-kill-other-buffers)                           ; Kill every buffer except the current one (prompts for confirmation).
     ;; ("C-M-z"           . crux-indent-defun)                                 ; Re-indent the top-level definition (defun, defvar, etc.) surrounding point.
     ;; ("C-c TAB"         . crux-indent-rigidly-and-copy-to-clipboard)         ; Rigidly indent the region by one tab stop and copy the result to the clipboard.
     ;; ("C-c s"           . crux-sudo-edit)                                    ; Reopen the current file as root via TRAMP sudo, preserving the cursor position.
     ;; ("C-c I"           . crux-find-user-init-file)                          ; Open init.el (or the file pointed to by user-init-file).
     ;; ("C-c ,"           . crux-find-user-custom-file)                        ; Open custom.el (or the file pointed to by custom-file).
     ;; ("C-c S"           . crux-find-shell-init-file)                         ; Open the shell's init file (.bashrc, .zshrc, etc.) inferred from SHELL.
     ;; ("C-c l"           . crux-find-current-directory-dir-locals-file)       ; Open (or create) the .dir-locals.el file for the current buffer's directory.
     ;; ("s-j"             . crux-top-join-line)                                ; Pull the following line up and join it to the end of the current line, removing the newline.
     ;; ("C-^"             . crux-top-join-line)                                ; Same as above, Ctrl key variant.
     ;; ("s-k"             . crux-kill-whole-line)                              ; Kill the entire current line including its newline, regardless of point position. NOTE: conflicts with crux-smart-kill-line Super binding above.
     ;; ("C-<backspace>"   . crux-kill-line-backwards)                          ; Kill from point back to the first non-whitespace character on the line (or to the previous line if at column 0).
     ;; ("C-S-<backspace>" . crux-kill-and-join-forward)                        ; If at end of line, delete the newline and join with the next line; otherwise kill the rest of the line.
     ;; ("C-c P"           . crux-kill-buffer-truename)                         ; Copy the real (symlink-resolved) absolute path of the current file to the kill ring.
     ;; ("C-c i"           . crux-ispell-word-then-abbrev)                      ; Correct the word at point with ispell, then define an abbrev so the typo auto-corrects in the future.
     ;; ("C-x C-u"         . crux-upcase-region)                                ; Upcase the region (safe version: only acts when the region is active).
     ;; ("C-x C-l"         . crux-downcase-region)                              ; Downcase the region (safe version: only acts when the region is active).
     ;; ("C-x M-c"         . crux-capitalize-region)                            ; Capitalize the region (safe version: only acts when the region is active).
     ;; ("C-c b"           . crux-switch-to-previous-buffer)                    ; Switch to the most recently visited buffer; repeated presses toggle between the two most recent.
     ;; ("M-o"             . crux-other-window-or-switch-buffer)                ; Focus the other window if one exists, otherwise switch to the previous buffer. NOTE: conflicts with crux-smart-open-line above.
     ;; ("C-a"             . crux-move-beginning-of-line)                       ; First press moves to the first non-whitespace character; second press moves to column 0. Replaces built-in C-a.
     ;; ("C-c d t"         . crux-insert-date)                                  ; Insert the current date and time formatted according to the locale at point.
     ;; ("C-g"             . crux-keyboard-quit-dwim)                           ; Smarter C-g: dismisses the minibuffer or *Completions* buffer even when focus is elsewhere. Replaces built-in C-g.
     )))

;;; -- Miscellaneous commands to extract and check line length -----------------

;;;###autoload
(defun region-length ()
  "Display the number of characters in the region in a message."
  (interactive)
  (let ((len  (abs (- (mark) (point)))))
    (message "Region contains %s characters" len)
    len))

(defun check-long-lines (max-col)
  "Check lines in the region (or buffer) for lines exceeding MAX-COL characters.
Displays a report buffer listing each offending line number and content.

This function is especially useful when coding for Emacs C functions
where a maximum length of 79 characters must be enforced.
"
  (interactive (list (read-number "Max columns: " 79)))
  (let* ((start (if (use-region-p) (region-beginning) (point-min)))
         (end   (if (use-region-p) (region-end)       (point-max)))
         (source-buf (current-buffer))
         offenders)
    (save-excursion
      (goto-char start)
      (while (< (point) end)
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))
               (trimmed (progn (string-match "^[ \t]*\\(.*\\)" line)
                               (match-string 1 line)))
               (len (length trimmed)))
          (when (> len max-col)
            (push (cons (line-number-at-pos) trimmed) offenders)))
        (forward-line 1)))
    (if (null offenders)
        (message "No lines exceed %d characters." max-col)
      (let ((report (get-buffer-create "*long-lines*")))
        (with-current-buffer report
          (read-only-mode -1)
          (erase-buffer)
          (insert (format "Lines exceeding %d columns in %s:\n\n"
                          max-col (buffer-name source-buf)))
          (dolist (entry (nreverse offenders))
            (insert (format "L%d (%d chars): %s\n"
                            (car entry)
                            (length (cdr entry))
                            (cdr entry))))
          (read-only-mode 1)
          (goto-char (point-min)))
        (pop-to-buffer report)))))


;;; -- Help system enhancements: Schema-aware documentation. -------------------
;;
;; This feature enhances `describe-variable' (C-h v) by automatically extracting
;; and rendering the machine-readable schema (custom-type) of customizable
;; variables. This provides "JSON Schema"-style discoverability directly in
;; the Help buffer, showing allowed values without needing to open the
;; full Customize UI.

(defun my/help-fns-describe-custom-type (variable)
  "Extract and render the `custom-type' (schema) for VARIABLE.
This function is intended for `help-fns-describe-variable-functions'.

It provides specialized formatting for:
- `choice`: Lists all possible options.
- `const`: Extracts both the internal value and the human-readable :tag.
- others: Falls back to a clean printed representation of the type."
  (when-let* ((type (get variable 'custom-type)))
    (if (and (listp type) (eq (car type) 'choice))
        ;; Format choice types as a comma-separated list of "value (Tag)"
        (let ((opts (mapcar (lambda (o)
                              (if (and (listp o) (eq (car o) 'const))
                                  (let ((v (car (last o)))
                                        (tag (plist-get (cdr o) :tag)))
                                    (if tag (format "%s (%s)" v tag) (format "%s" v)))
                                (format "%s" o)))
                            (cdr type))))
          (princ (format "  Choice: %s\n" (mapconcat #'identity opts ", "))))
      ;; Fallback for non-choice types (e.g. boolean, integer, string)
      (princ (format "  Type: %S\n" type)))))

;; Register the schema viewer. We append it (t) so it appears after the
;; standard "You can customize this variable" line.
(add-hook 'help-fns-describe-variable-functions #'my/help-fns-describe-custom-type t)

;;; -- Paragraph utilities -----------------------------------------------------

(defun my/fill-or-unfill (&optional arg)
  "Fill paragraph; with prefix ARG, unfill onto a single line."
  (interactive "P")
  (let ((fill-column (if arg most-positive-fixnum fill-column)))
    (fill-paragraph nil t)))

(global-set-key (kbd "M-q") #'my/fill-or-unfill)

;;; -- Smarter dwim comment ----------------------------------------------------

(defun my/comment-dwim-section-header (orig-fun &rest args)
  "Around advice for `comment-dwim' that converts `;;;+' section-header lines.
When point is on a line whose leading run of semicolons is three or longer:

  ;;;+ ---- LABEL ----

replace it with a filled banner line, preserving the semicolon count:

  ;;;+ -- LABEL --------

where trailing dashes extend the line to `fill-column'. The cursor is
repositioned at the same offset within LABEL as before.

Falls through to the original command in all other cases."
  (let* ((line       (buffer-substring-no-properties
                      (line-beginning-position) (line-end-position)))
         (line-start (line-beginning-position))
         (pt-offset  (- (point) line-start)))
    (if (and (not (use-region-p))
             (string-match "\\`\\(;\\{3,\\}\\)" line))
        (let* ((semis         (match-string 1 line))
               (n             (length semis))
               (rest          (substring line n))
               (rest-no-lead  (replace-regexp-in-string "\\`[ \t-]+" "" rest))
               (inner         (replace-regexp-in-string "[ \t-]+\\'" "" rest-no-lead))
               (text          (string-trim inner)))
          (if (string-empty-p text)
              (apply orig-fun args)
            (let* ((prefix     (concat semis " -- "))
                   ;; Column where LABEL begins in the original line
                   (text-start (+ n (- (length rest) (length rest-no-lead))))
                   ;; Cursor offset relative to LABEL, clamped to [0 .. (length text)]
                   (rel-offset (max 0 (min (length text) (- pt-offset text-start))))
                   ;; Build the replacement line
                   (base       (concat prefix text " "))
                   (new-line   (concat base (make-string
                                             (max 0 (- fill-column (length base)))
                                             ?-))))
              (delete-region line-start (line-end-position))
              (insert new-line)
              ;; LABEL starts at column (length prefix) in the new line
              (goto-char (+ line-start (length prefix) rel-offset)))))
      (apply orig-fun args))))

(advice-add 'comment-dwim :around #'my/comment-dwim-section-header)

(provide 'utils)
;;; utils.el ends here
