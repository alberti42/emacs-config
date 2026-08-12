;;; syntaxes/org-semantic.el --- org-semantic results display settings -*- lexical-binding: t; -*-

;; `org-semantic-results-mode' (org-semantic) lists search hits as note
;; passages — a generated, read-only listing, so the line-number gutter is
;; noise (it is otherwise on via `global-display-line-numbers-mode').
;;
;; Results are also displayed the way `describe-function' displays help: reuse
;; the window already showing a results buffer, else take some *other* existing
;; window, and only when the frame has none split off a new one to the right.
;; So a search never takes over the note being read, and in a two-window frame
;; it simply lands in the neighbouring window.  The condition is matched on the
;; major mode rather than the buffer name, since the name carries the vault
;; (`*org-semantic: <vault>*').

(defvar emacs-config-syntaxes-enable-org-semantic t
  "Whether to enable org-semantic settings from syntaxes/org-semantic.el.")

(when emacs-config-syntaxes-enable-org-semantic
  (add-hook 'org-semantic-results-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)))

  (add-to-list 'display-buffer-alist
               '((derived-mode . org-semantic-results-mode)
                 (display-buffer-reuse-mode-window
                  display-buffer-use-some-window
                  display-buffer-in-direction)
                 (some-window . lru)
                 (direction . right)
                 (window-width . 0.5))))

(provide 'syntaxes-org-semantic)

;;; syntaxes/org-semantic.el ends here
