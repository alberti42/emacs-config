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

;;; Miscellaneous commands
;;
;; Command to obtain the number of characters in the selected region; obtained
;; from https://www.emacswiki.org/emacs/misc-cmds.el
;;;###autoload
(defun region-length ()
  "Display the number of characters in the region in a message."
  (interactive)
  (let ((len  (abs (- (mark) (point)))))
    (message "Region contains %s characters" len)
    len))

(defun check-long-lines (max-col)
  "Check lines in the region (or buffer) for lines exceeding MAX-COL characters.
Displays a report buffer listing each offending line number and content."
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

;;; Help system enhancements: Schema-aware documentation.
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

(provide 'utils)
;;; utils.el ends here
