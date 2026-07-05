;;; syntaxes/markdown.el --- Markdown syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-markdown t
  "Whether to enable Markdown settings from syntaxes/markdown.el.")

(when emacs-config-syntaxes-enable-markdown
  ;; Region-wrap for the inline delimiters electric-pair-mode does not
  ;; treat as pairs.  `my/wrap-region-or-self-insert' lives in
  ;; electric-config.el; a bare keypress self-inserts, a selection is
  ;; surrounded (`code`, *emphasis*).  The cycling cap is passed at the
  ;; binding site (a fresh command runs on each repeat, so it cannot come
  ;; from a let/lexical binding): * cycles *x* -> **x** -> ***x***
  ;; (emphasis / strong / both), while ` wraps once (no meaningful cycle
  ;; for inline code).
  (with-eval-after-load 'markdown-ts-mode
    (define-key markdown-ts-mode-map (kbd "`")
                #'my/wrap-region-or-self-insert)
    (define-key markdown-ts-mode-map (kbd "*")
                (lambda (n) (interactive "p")
                  (my/wrap-region-or-self-insert n 3))))
  (add-hook 'markdown-ts-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (setq-local soft-wrap-default-centered t)
              ;; Drop `#' from the default `adaptive-fill-regexp' for
              ;; markdown-ts-mode.  ATX headings are one-shot opening markers,
              ;; not paragraph continuation prefixes; they should not be
              ;; repeated on continuation lines or reserve column space.  This
              ;; also sidesteps a visual-wrap.el bug where invisible prefix
              ;; characters still reserve column space, but the override is
              ;; useful on its own merits.
              (setq-local adaptive-fill-regexp
                          "[|%;>·•‣⁃◦ \t]*")
              (soft-wrap-mode 1)
              ;; (olivetti-mode 1)

              ;; Prose word-completion: merged dabbrev + in-memory
              ;; dictionary super-CAPF (defined in completions/cape.el).
              ;; Surfaces buffer-recent words alongside dictionary words
              ;; in one popup, both gated to ≥3 chars.
              (add-hook 'completion-at-point-functions
                        #'emacs-config-cape-prose nil t))))

(provide 'syntaxes-markdown)
;;; syntaxes/markdown.el ends here
