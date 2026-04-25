;;; jupyter-config.el --- emacs-jupyter for remote Jupyter kernels -*- lexical-binding: t; -*-

;; emacs-jupyter talks to Jupyter kernels via the kernel protocol (ZMQ for
;; local kernels, WebSockets when going through a Jupyter Server).  The
;; on-disk format stays plain `.org' — no `.ipynb' involved; this is purely
;; the kernel-attach mechanism.

;;; -- Prebuilt emacs-zmq workaround -------------------------------------------
;;
;; The `zmq' Emacs C dynamic module is required by emacs-jupyter even for
;; server-mode (HTTP/WebSocket) workflows, where ZMQ itself isn't on the
;; wire.  Building it from source has two issues on this setup:
;;
;; 1. The bundled `Makefile' fails to link `emacs-zmq.dylib' on recent
;;    macOS toolchains: libtool rejects the `-Wl,libzmq/src/.libs/libzmq.a'
;;    syntax used to pull in the static archive.
;;
;; 2. emacs-zmq's own auto-download (`zmq--download-module' in `zmq.el')
;;    misses the release asset on Apple Silicon: Emacs reports
;;    `aarch64-apple-darwinN.N' for `system-configuration', while upstream
;;    names the asset `arm64-apple-darwinN.N.tar.gz'.  The `string-prefix-p'
;;    match fails, so it falls through to the broken make path.
;;
;; 3. straight rebuilds the package on every Emacs start, wiping any
;;    manually-placed dylib in the build dir.
;;
;; Workaround: download the matching prebuilt dylib from upstream releases
;; into straight's build dir on every Emacs start, before `zmq' is loaded.
;; Idempotent — no-op if the dylib is already in place.

(defconst jupyter-config--zmq-version "v1.0.2"
  "emacs-zmq release tag whose prebuilt module to fetch.
Bump in lockstep with the `zmq-emacs-version' constant in zmq.el.")

(defun jupyter-config--zmq-asset-name ()
  "Filename of the prebuilt emacs-zmq tarball for the current platform."
  (pcase system-type
    ('darwin
     (if (string-match-p "aarch64\\|arm64" system-configuration)
         "emacs-zmq-arm64-apple-darwin23.6.0.tar.gz"
       (user-error "No prebuilt emacs-zmq for Intel macOS; check upstream releases")))
    ('gnu/linux  "emacs-zmq-x86_64-linux-gnu.tar.gz")
    ('windows-nt "emacs-zmq-x86_64-w64-mingw32.tar.gz")
    (_ (user-error "No prebuilt emacs-zmq for system-type %s" system-type))))

(defun jupyter-config-ensure-zmq-dylib ()
  "Ensure the prebuilt emacs-zmq dynamic module is present in straight's build dir.
Downloads from upstream releases if missing.  Safe to call repeatedly:
returns immediately when the module is already in place."
  (let* ((build-dir (expand-file-name "straight/build/zmq/" user-emacs-directory))
         (suffix (cond ((eq system-type 'darwin) ".dylib")
                       ((eq system-type 'windows-nt) ".dll")
                       (t ".so")))
         (target (expand-file-name (concat "emacs-zmq" suffix) build-dir)))
    (when (and (file-directory-p build-dir)
               (not (file-exists-p target)))
      (let* ((asset (jupyter-config--zmq-asset-name))
             (url (format "https://github.com/nnicandro/emacs-zmq/releases/download/%s/%s"
                          jupyter-config--zmq-version asset))
             (tarball (make-temp-file "emacs-zmq-" nil ".tar.gz"))
             (extract (file-name-as-directory
                       (make-temp-file "emacs-zmq-extract-" t))))
        (unwind-protect
            (progn
              (message "jupyter-config: downloading prebuilt emacs-zmq %s..."
                       jupyter-config--zmq-version)
              (url-copy-file url tarball t)
              (let ((default-directory extract))
                (unless (zerop (call-process "tar" nil nil nil "xzf" tarball))
                  (error "Failed to extract %s" tarball)))
              (let* ((subdir (car (directory-files extract t "\\`emacs-zmq" t)))
                     (lib (and subdir
                               (car (directory-files
                                     subdir t
                                     (rx "emacs-zmq" (or ".dylib" ".so" ".dll") eos))))))
                (unless lib
                  (error "Prebuilt module missing in extracted tarball"))
                (copy-file lib target t)
                (message "jupyter-config: installed %s" target)))
          (when (file-exists-p tarball) (delete-file tarball))
          (when (file-directory-p extract) (delete-directory extract t)))))))

;;; -- Setup jupyter package ---------------------------------------------------

(use-package jupyter
  :straight (jupyter :host github :repo "alberti42/fork-emacs-jupyter"
                     :branch "fix-monads-macro-ordering")
  :config
  (setq jupyter-eval-use-overlays t)

  ;; Customize face of input prompt inheriting from success
  (set-face-attribute 'jupyter-repl-input-prompt nil
                      :foreground 'unspecified
                      :inherit 'success)
  
  ;; When `jupyter-repl-associate-buffer' starts a fresh REPL via the no-client
  ;; branch, it calls `jupyter-run-repl' interactively, which passes `display=t'
  ;; and pops the new REPL into a window.  Keep the REPL buried.
  (define-advice jupyter-repl-associate-buffer
      (:around (orig client) jupyter-config/bury-new-repl)
    (if client
        (funcall orig client)
      (save-window-excursion (funcall orig nil))))

  ;; Pin `*jupyter-output*' / `*jupyter-error*' to a few-line window at the bottom
  ;; instead of `display-buffer's default split-in-half behavior.
  (add-to-list 'display-buffer-alist
               '("\\*jupyter-\\(output\\|error\\)\\*"
                 (display-buffer-reuse-window
                  display-buffer-below-selected)
                 (window-height . 10)
                 (dedicated . t)))

  ;; Install the prebuilt emacs-zmq dylib just before zmq-core is first
  ;; looked up.  Hooking on `zmq' (the elisp wrapper) rather than `zmq-core'
  ;; (the dynamic module) is the right join point: zmq.el's body finishes
  ;; with `(provide 'zmq)' and the autoloads for zmq-core have only just
  ;; been registered — the dylib hasn't been touched yet.  Our callback
  ;; runs synchronously inside `provide', so the dylib is in place by the
  ;; time the first zmq function call triggers `zmq-load'.  This also moves
  ;; any network/disk work out of Emacs startup and into first-jupyter-use.
  (with-eval-after-load 'zmq
    (jupyter-config-ensure-zmq-dylib)))

;;; -- jupyter integration with org-babel --------------------------------------

;; Org-babel `jupyter-LANG' integration.  Decoupled from the `use-package'
;; form so jupyter remains autoload-driven (no spurious `:after org'
;; deferral).  Runs only when both org and jupyter happen to be loaded.
(with-eval-after-load 'org
  (with-eval-after-load 'jupyter
    (add-to-list 'org-babel-load-languages '(jupyter . t))
    (org-babel-do-load-languages
     'org-babel-load-languages
     org-babel-load-languages)
    ;; Match the `python' babel default — capture stdout, export both.
    (setq org-babel-default-header-args:jupyter-python
          '((:async . "yes")
            (:kernel . "python3")
            (:exports . "both")
            (:results . "output")))))

(provide 'jupyter-config)
;;; jupyter-config.el ends here
