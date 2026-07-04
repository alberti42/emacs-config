;;; utils.el --- General-purpose interactive utilities -*- lexical-binding: t; -*-

;;; -- Utilities to produce UUID -----------------------------------------------

;; Stock `uuid.el' (Emacs 31+) ships without autoload cookies, so its symbols
;; are unknown until something requires it.  Register autoloads for the public
;; API here so any `uuid-*' call lazily pulls in the library.
(use-package uuid
  :straight nil
  :commands (uuid-v4 uuid-v5 uuid-v7
             uuid-to-string uuid-from-string
             uuid-to-bytes uuid-from-bytes
             uuid-to-number uuid-p))

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

;;; -- Markdown fenced-code language identifiers -------------------------------
;;
;; Map an Emacs major mode to the language identifier used in a Markdown fenced
;; code block -- the leading token of the fence "info string" (e.g. the
;; `python' in "```python").  Generally useful wherever code is emitted as
;; Markdown, not just by the agent-snippet command below.

(defvar my/markdown-language-alist
  '(;; Lisps
    (emacs-lisp-mode        . "elisp")
    (lisp-interaction-mode  . "elisp")
    (lisp-mode              . "commonlisp")
    (clojure-mode           . "clojure")
    (scheme-mode            . "scheme")
    ;; C family
    (c-mode                 . "c")
    (c-ts-mode              . "c")
    (c++-mode               . "cpp")
    (c++-ts-mode            . "cpp")
    (objc-mode              . "objc")
    (csharp-mode            . "csharp")
    (csharp-ts-mode         . "csharp")
    ;; Systems / compiled
    (rust-mode              . "rust")
    (rustic-mode            . "rust")
    (rust-ts-mode           . "rust")
    ;; Web / scripting
    (js2-mode               . "js")
    (rjsx-mode              . "jsx")
    (js-json-mode           . "json")
    (cperl-mode             . "perl")
    (perl-mode              . "perl")
    ;; Shell
    (sh-mode                . "bash")
    (bash-ts-mode           . "bash")
    ;; Markup / config
    (nxml-mode              . "xml")
    (mhtml-mode             . "html")
    (html-mode              . "html")
    (conf-toml-mode         . "toml")
    (makefile-gmake-mode    . "makefile")
    (makefile-bsdmake-mode  . "makefile")
    ;; Docs / markup / prose
    (markdown-mode          . "markdown")
    (markdown-ts-mode       . "markdown")
    (org-mode               . "org")
    (latex-mode             . "latex")
    (LaTeX-mode             . "latex")
    (text-mode              . "text"))
  "Major-mode -> Markdown fenced-code language identifier overrides.
An entry takes precedence over the strip heuristic in
`my/markdown-language-for-mode'.  List a mode when its conventional
identifier differs from the stripped name (e.g. `c++-mode' -> \"cpp\"), or
simply to make a commonly used mode explicit; modes absent here fall through
to the heuristic (e.g. `python-ts-mode' -> \"python\").")

(defun my/markdown-language-for-mode (&optional mode)
  "Return the Markdown fenced-code language identifier for MODE.
MODE defaults to the current `major-mode'.  The identifier is the leading
token of a fence info string (e.g. \"python\" in a \"```python\" block).
Consults `my/markdown-language-alist' first; otherwise strips the
`-ts-mode'/`-mode' suffix (so `python-ts-mode' -> \"python\")."
  (let ((mode (or mode major-mode)))
    (or (cdr (assq mode my/markdown-language-alist))
        (replace-regexp-in-string "\\(-ts\\)?-mode\\'" "" (symbol-name mode)))))

;;; -- Copy buffer/region as an agent-ready snippet ----------------------------
;;
;; Two shapes for pasting to a coding agent, chosen by prefix arg on `M-w'
;; (see `my/kill-ring-save-dwim'):
;;
;;   `C-u M-w'      a bare "path:range" locator.  The agent reads the file
;;                  itself, so this is the token-lean pointer for edit tasks --
;;                  a cautious agent re-reads for an exact-match string
;;                  regardless of what we paste, so the body would be redundant.
;;   `C-u C-u M-w'  a real fenced, language-tagged code block with the verbatim
;;                  lines (no line-number gutter, so a Markdown renderer can
;;                  syntax-highlight it).  For content the agent cannot fetch
;;                  and trust -- unsaved edits, non-file buffers -- or when you
;;                  simply want the code inline.

(defun my/agent-snippet--path (&optional base-dir)
  "Return the path for the snippet header.
Relative to BASE-DIR when given and the file lives under it; otherwise
project-relative when inside a project; otherwise the abbreviated absolute
path.  The buffer name for non-file buffers."
  (let ((file (buffer-file-name)))
    (cond
     ((null file) (buffer-name))
     ((and base-dir (file-in-directory-p file base-dir))
      (file-relative-name file base-dir))
     ((when-let* ((proj (project-current))
                  (root (project-root proj))
                  ((file-in-directory-p file root)))
        (file-relative-name file root)))
     (t (abbreviate-file-name file)))))

(defun my/agent-snippet--max-backtick-run (s)
  "Return the length of the longest run of backticks in string S."
  (let ((max 0) (start 0))
    (while (string-match "`+" s start)
      (setq max   (max max (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    max))

(defun my/agent-snippet-format (start end &optional path)
  "Return a plist describing an agent-ready snippet of the current buffer.
The snippet covers the whole lines spanning START..END and is offered in two
shapes (the caller picks one):

 - a bare \"path:range\" locator, e.g. \"utils.el:462-522\", pointing a coding
   agent at the file so it reads the exact lines itself; and
 - a real fenced, language-tagged code block a Markdown renderer can
   syntax-highlight:

       ```<lang> <path>:<range>
       line content
       ...
       ```

LANG comes from `my/markdown-language-for-mode'; PATH (the locator path)
defaults to `my/agent-snippet--path' but may be supplied by the caller (e.g.
relative to an agent's working directory); the fence grows past any run of
backticks in the content.  The body is the verbatim lines -- no line-number
gutter, so highlighting is not disrupted.

The returned plist has keys:
 :pointer  the bare \"path:range\" locator
 :fenced   the full fenced code block (opening fence + info string, body,
           closing fence)
 :body     the verbatim lines joined by newlines (no fence, no numbers)
 :fence    the fence delimiter string
 :path :range :lang :lines  as above (range is a \"N\" or \"N-M\" string)
Pure: it neither moves point nor touches the kill ring."
  (save-excursion
    ;; Snap to whole lines; drop a trailing line the region only touches at col 0.
    (goto-char start) (setq start (line-beginning-position))
    (goto-char end)
    (when (and (bolp) (> end start)) (forward-line -1))
    (setq end (line-end-position)))
  (let* ((first   (line-number-at-pos start))
         (last    (line-number-at-pos end))
         (path    (or path (my/agent-snippet--path)))
         (lang    (my/markdown-language-for-mode))
         (body    (buffer-substring-no-properties start end))
         (range   (if (= first last)
                      (number-to-string first)
                    (format "%d-%d" first last)))
         (pointer (format "%s:%s" path range))
         (fence   (make-string (max 3 (1+ (my/agent-snippet--max-backtick-run body))) ?`))
         ;; A fenced info string is "<lang> <rest>": renderers highlight by the
         ;; first token (LANG) and ignore the trailing POINTER, so we keep both.
         (info    (concat (if (string-empty-p lang) "" (concat lang " ")) pointer)))
    (list :pointer pointer
          :fenced  (concat fence info "\n" body "\n" fence)
          :body    body
          :fence   fence
          :path    path
          :range   range
          :lang    lang
          :lines   (1+ (- last first)))))

;;;###autoload
(defun my/copy-as-agent-snippet (start end &optional fenced)
  "Copy the region (or current line) as an agent-ready snippet.
Without a prefix argument, copy a bare \"path:range\" locator -- the agent
reads the file itself, so this is the token-lean pointer for edit tasks.
With a double prefix argument (`C-u C-u'), copy a real fenced,
language-tagged code block with the verbatim lines (no line-number gutter,
so Markdown syntax highlighting works); use it for content the agent cannot
fetch and trust -- unsaved edits, non-file buffers -- or to show code inline.
See `my/agent-snippet-format' for the exact shapes.  The result is pushed to
the kill ring (and thus the system clipboard)."
  (interactive
   (append
    (if (use-region-p)
        (list (region-beginning) (region-end))
      (list (line-beginning-position) (line-end-position)))
    (list (equal current-prefix-arg '(16)))))
  (let* ((snip (my/agent-snippet-format start end))
         (text (plist-get snip (if fenced :fenced :pointer))))
    (kill-new text)
    ;; Clear the selection like `kill-ring-save' does.
    (deactivate-mark)
    (message "Copied %s%s (%d line%s)"
             (if fenced "fenced " "")
             (plist-get snip :pointer)
             (plist-get snip :lines)
             (if (= 1 (plist-get snip :lines)) "" "s"))))

;; `M-w' stays `kill-ring-save'; a prefix copies an agent snippet instead.
;; `C-u M-w' copies the bare "path:range" locator, `C-u C-u M-w' the fenced
;; block.  `C-u' is the `universal-argument' prefix, so the dispatch must live
;; in the command bound to `M-w', not in a separate key binding.
(defun my/kill-ring-save-dwim (&optional arg)
  "Save the region to the kill ring, or copy an agent snippet with a prefix.
Plain `M-w' runs `kill-ring-save'.  `C-u M-w' copies a bare \"path:range\"
locator; `C-u C-u M-w' copies a real fenced code block.  See
`my/copy-as-agent-snippet' for the snippet shapes."
  (interactive "P")
  (if arg
      (let ((bounds (if (use-region-p)
                        (cons (region-beginning) (region-end))
                      (cons (line-beginning-position) (line-end-position)))))
        (my/copy-as-agent-snippet (car bounds) (cdr bounds) (equal arg '(16))))
    (call-interactively #'kill-ring-save)))

(global-set-key (kbd "M-w") #'my/kill-ring-save-dwim)

(provide 'utils)
;;; utils.el ends here
