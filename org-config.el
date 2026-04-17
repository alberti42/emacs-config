;;; org-config.el --- Org mode with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Install Org from tecosaur's fork to get karthink's org-latex-preview
;; (auto-preview, live updates, dvisvgm SVG rendering).  We follow the
;; instructiosn from: https://abode.karthinks.com/org-latex-preview/. The
;; feature has not yet been merged into mainline Org.  This recipe must appear
;; before any package that depends on Org.
(use-package org
  :straight `(org
              :fork (:host nil
                           :repo "https://git.tecosaur.net/tec/org-mode.git"
                           :branch "dev"
                           :remote "tecosaur")
              :files (:defaults "etc")
              :build t
              :pre-build
              (with-temp-file "org-version.el"
                (require 'lisp-mnt)
                (let ((version
                       (with-temp-buffer
                         (insert-file-contents "lisp/org.el")
                         (lm-header "version")))
                      (git-version
                       (string-trim
                        (with-temp-buffer
                          (call-process "git" nil t nil
                                        "rev-parse" "--short" "HEAD")
                          (buffer-string)))))
                  (insert
                   (format "(defun org-release () \"The release version of Org.\" %S)\n" version)
                   (format "(defun org-git-version () \"The truncate git commit hash of Org mode.\" %S)\n" git-version)
                   "(provide 'org-version)\n")))
              :pin nil)
  :defer t
  :hook
  (org-mode . org-latex-preview-mode)
  :custom
  ;; Render all LaTeX previews when opening a file.  Fragments whose hash
  ;; matches a `org-persist' entry load instantly; new or edited fragments
  ;; (cache misses) are sent to LaTeX + dvisvgm for fresh rendering.
  (org-startup-with-latex-preview t)
  ;; Display inline images (e.g. babel plot output) when opening a file.
  ;; `org-startup-with-inline-images' is now a defvaralias for
  ;; `org-startup-with-link-previews' in the new Org; set the canonical name.
  (org-startup-with-link-previews t)
  ;; Cap inline image display width at 600px, preserving aspect ratio.
  ;; The underlying file is untouched; this only affects on-screen size.
  (org-image-actual-width '(600))
  ;; Live-render LaTeX fragments as you type.  Default `(block edit-special)'
  ;; excludes inline `$...$' fragments; `t' covers inline, blocks, and the
  ;; `org-edit-special' buffer.
  (org-latex-preview-mode-display-live t)
  :config
  ;; Show inline images after evaluating babel blocks.
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images)

  ;; Suppress the `*Org-Babel Error Output*' popup when the subprocess
  ;; exited cleanly.  ob-eval.el always pops the buffer whenever stderr is
  ;; non-empty (even on exit 0), which is noisy for tools like matplotlib
  ;; that print benign warnings to stderr.  The buffer is still written to,
  ;; so real errors (non-zero exit) still pop and past stderr remains
  ;; inspectable via `M-x switch-to-buffer'.
  (define-advice org-babel-eval-error-notify
      (:around (oldfun exit-code stderr) suppress-on-success)
    (let ((display-buffer-alist
           (if (and exit-code (not (zerop exit-code)))
               display-buffer-alist
             (cons (cons (regexp-quote org-babel-error-buffer-name)
                         '(display-buffer-no-window
                           (allow-no-window . t)))
                   display-buffer-alist))))
      (funcall oldfun exit-code stderr)))

  ;; Python babel support.
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)))

  ;; Don't ask for confirmation on every C-c C-c in trusted files.
  ;; Set to a function if you want selective confirmation.
  (setq org-confirm-babel-evaluate nil)

  ;; Default header args for Python: produce graphics files for matplotlib.
  ;; The prologue:
  ;;   - Forces the non-interactive `Agg` backend so plotting does not load
  ;;     AppKit on macOS (which prints `ApplePersistence=NO` to stderr and
  ;;     causes babel to pop `*org-babel error output*`).  `setdefault' lets
  ;;     individual blocks override via `os.environ'.
  ;;   - Sets `savefig.format' to SVG so `plt.savefig("name")' (no extension)
  ;;     writes vector SVG — crisper than PNG and scales cleanly in org
  ;;     inline images.  Matplotlib dispatches to its SVG writer by format,
  ;;     independent of the `Agg' interactive backend.
  (setq org-babel-default-header-args:python
        '((:results . "output file graphics")
          (:exports . "both")
          (:prologue . "import os; os.environ.setdefault('MPLBACKEND', 'Agg')
import matplotlib; matplotlib.rcParams['savefig.format'] = 'svg'"))))

(provide 'org-config)
;;; org-config.el ends here
