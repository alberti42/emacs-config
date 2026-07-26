;;; compile-config.el --- Build workflow on top of compile-command -*- lexical-binding: t; -*-

;; `compile' is the Emacs build entry point: it runs a shell command in
;; `default-directory' and turns the output into a navigable buffer
;; (`next-error' / `C-x `', `g' to re-run).  A project describes its build by
;; setting `compile-command' from a `.dir-locals.el' next to its sources, so no
;; per-project Elisp is needed here.
;;
;; `compile-command' is a risky local variable: its `safe-local-variable'
;; predicate accepts a directory-local string only while
;; `compilation-read-command' is non-nil, i.e. only when the command would still
;; be shown in the minibuffer before running.  The global default is therefore
;; left at t and the prompt is skipped per invocation instead.

(require 'compile)

(setq compilation-scroll-output 'first-error)
(setq compilation-ask-about-save nil)

;;; Makefile projects: choose a target with completion

;; For a project whose build is a set of make rules, the useful prompt is not
;; the shell command but the target list — the AUCTeX `C-c C-c' model, where
;; one key offers the alternatives with a sensible default on RET.

(defvar compile-config-make-command "make"
  "Program, with any flags, used to run a Makefile target.
A project may override it from `.dir-locals.el', e.g. \"make -j8\" or
\"make -k\".")
(put 'compile-config-make-command 'safe-local-variable #'stringp)

(defvar compile-config-makefile-names '("GNUmakefile" "makefile" "Makefile")
  "Makefile names, in the order GNU make itself looks for them.")

(defvar compile-config--last-target (make-hash-table :test #'equal)
  "Last target run, keyed by the directory holding the makefile.
Makes a repeat build `C-c c RET'.")

(defun compile-config--makefile (dir)
  "Return the makefile governing DIR, or nil if it has none."
  (let (found)
    (dolist (name compile-config-makefile-names found)
      (let ((file (expand-file-name name dir)))
        (when (and (not found) (file-readable-p file))
          (setq found file))))))

(defun compile-config--make-dir ()
  "Return the closest directory at or above `default-directory' holding a makefile."
  (locate-dominating-file default-directory #'compile-config--makefile))

(defun compile-config--make-targets (makefile)
  "Return an alist of (TARGET . DOC) for the rules declared in MAKEFILE.
Recipe lines, variable assignments, pattern rules, special dot targets
and targets named by a variable are skipped.  DOC comes from the
`target: ## description' convention of self-documenting Makefiles, and is
nil when absent.  `include'd makefiles are not followed."
  (let ((targets ()))
    (with-temp-buffer
      (insert-file-contents makefile)
      (goto-char (point-min))
      ;; A rule line starts in column 0 — a leading tab means a recipe.
      (while (re-search-forward "^\\([^ \t#:=%$\n][^#:=%$\n]*\\):" nil t)
        ;; Tell a rule from an assignment.  `:=', `::=' and `:::=' assign;
        ;; `target::' is a legitimate double-colon rule.  A single regexp
        ;; cannot express this, because backtracking over a `:+' run would
        ;; happily re-read `::=' as a double-colon rule.
        (unless (looking-at ":*=")
          (let ((names (match-string 1))
                (doc (save-excursion
                       (and (re-search-forward "##[ \t]*\\(.*?\\)[ \t]*$"
                                               (line-end-position) t)
                            (match-string 1)))))
            (dolist (name (split-string names nil t))
              ;; `.PHONY' & co. declare rather than build.
              (unless (or (string-prefix-p "." name)
                          (assoc name targets))
                (push (cons name doc) targets)))))))
    (nreverse targets)))

(defun my/compile-make (dir)
  "Run a Makefile target in DIR, chosen with completion.
Interactively, DIR is the closest directory at or above
`default-directory' that holds a makefile.  The default target is the one
last built there, else the makefile's own default goal (its first rule)."
  (interactive
   (list (or (compile-config--make-dir)
             (user-error "No makefile in %s or above" default-directory))))
  (let* ((targets (compile-config--make-targets (compile-config--makefile dir)))
         (default (or (gethash dir compile-config--last-target)
                      (caar targets)))
         (completion-extra-properties
          (list :annotation-function
                (lambda (candidate)
                  (when-let* ((doc (cdr (assoc candidate targets))))
                    (concat "  " doc)))))
         (target (completing-read (format-prompt "Make target" default)
                                  targets nil nil nil nil default))
         (command compile-config-make-command))  ; may be dir-local: read here
    (puthash dir target compile-config--last-target)
    (let ((default-directory dir))
      (compile (string-trim (concat command " " target))))))

(defun my/compile-dwim (&optional edit)
  "Build the current buffer's project, without a minibuffer prompt.
Runs `compile-command' in `default-directory'.  When that is only the
global default and a makefile governs the directory, prompt for a target
instead (see `my/compile-make') — a project states \"just run this\" by
setting `compile-command' from its `.dir-locals.el', which is a
buffer-local binding and therefore wins.

With prefix argument EDIT, prompt for the shell command itself, which is
the way to append one-off flags."
  (interactive "P")
  (if edit
      (call-interactively #'compile)
    ;; Only walk the tree when no project has claimed `compile-command'.
    (let ((make-dir (and (not (local-variable-p 'compile-command))
                         (compile-config--make-dir))))
      (if make-dir
          (my/compile-make make-dir)
        (compile compile-command)))))

(keymap-global-set "C-c c" #'my/compile-dwim)

;;; Quiet builds: no window unless the command fails

;; `compilation-handle-exit' already echoes the status line ("Compilation
;; finished", "Compilation exited abnormally with code 1"), so a successful
;; build needs no window at all.

(defvar compile-config-quiet t
  "Non-nil means keep a running compilation out of sight.
The buffer is popped up only when the command exits non-zero, and a
window left over from a failed build is closed again once a build
succeeds.")

(defun compile-config--quiet-buffer-p (buffer)
  "Non-nil when BUFFER is a compilation buffer covered by `compile-config-quiet'.
Matches `compilation-mode' exactly rather than derived modes, so
`grep-mode' and friends keep their normal window."
  (and compile-config-quiet
       (buffer-live-p (get-buffer buffer))
       (eq (buffer-local-value 'major-mode (get-buffer buffer))
           'compilation-mode)))

(defun compile-config--no-window-p (buffer _alist)
  "`display-buffer-alist' condition matching quiet compilations of BUFFER."
  (compile-config--quiet-buffer-p buffer))

;; `compilation-start' displays with `(allow-no-window . t)', which is what
;; makes `display-buffer-no-window' effective.  An explicit `display-buffer'
;; (below) passes no such flag, so it falls through to the normal actions and
;; still pops the buffer up.
(add-to-list 'display-buffer-alist
             '(compile-config--no-window-p (display-buffer-no-window)))

(defun compile-config--display-on-error (buffer msg)
  "Show BUFFER when the build described by MSG failed, hide it when it passed."
  (when (compile-config--quiet-buffer-p buffer)
    (if (string-prefix-p "finished" msg)
        (dolist (win (get-buffer-window-list buffer nil t))
          (quit-window nil win))
      (display-buffer buffer))))

(add-hook 'compilation-finish-functions #'compile-config--display-on-error)

(provide 'compile-config)
;;; compile-config.el ends here
