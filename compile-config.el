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

(defun my/compile-dwim (&optional edit)
  "Run `compile-command' in `default-directory' without prompting.
With prefix argument EDIT, prompt for the command first (useful to
append one-off flags)."
  (interactive "P")
  (if edit
      (call-interactively #'compile)
    (compile compile-command)))

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
