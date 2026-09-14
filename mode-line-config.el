;;; mode-line-config.el --- Global mode-line content policy -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Keep useful state in the mode line while hiding minor-mode lighters that
;; merely advertise that a background feature is enabled.  Hiding a lighter
;; does not disable its mode.

;;; Code:

(defconst emacs-config-mode-line-hidden-minor-modes
  '(auto-revert-mode
    lsp-ltex-plus-mode
    git-gutter-mode
    which-key-mode
    eldoc-mode
    visual-line-mode)
  "Minor modes whose lighters are hidden globally.")

(defun emacs-config-mode-line-hide-uninformative-lighters (&optional _file)
  "Hide configured minor-mode lighters without disabling their modes.
FILE is ignored; it permits use from `after-load-functions' so modes loaded
later receive the same policy."
  (dolist (mode emacs-config-mode-line-hidden-minor-modes)
    (when-let* ((entry (assq mode minor-mode-alist)))
      ;; Keep a valid empty mode-line construct.  Removing the cdr entirely
      ;; leaves an invalid one-element entry that renders as "*invalid*".
      (setcdr entry '("")))))

;; Some entries already exist at startup; package-provided entries may be added
;; later, so reapply the small policy after libraries load.
(emacs-config-mode-line-hide-uninformative-lighters)
(add-hook 'after-load-functions
          #'emacs-config-mode-line-hide-uninformative-lighters)

(provide 'mode-line-config)
;;; mode-line-config.el ends here
