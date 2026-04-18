;;; emacs-config-core.el --- Bootstrap helpers, Customize, and packages -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This file contains the "core" wiring for this Emacs configuration:
;; - Find the real config directory even when init.el is symlinked.
;; - Provide a small module loader helper used by init.el.
;; - Redirect Emacs Customize UI writes into custom.el (but do not auto-load it).
;; - Bootstrap straight.el and install/configure use-package.
;;
;; init.el is intentionally kept small and readable; it loads this file early.
;;

;;; Code:

;; Local modules loader
;;
;; This config is symlinked into ~/.config/emacs. To make local modules work
;; without extra symlinks, resolve the real location of this init file.
(defconst emacs-config-dir
  (file-name-directory (file-truename (or load-file-name user-init-file user-emacs-directory)))
  "Directory containing this Emacs configuration.")

(defun emacs-config-load-module (module warning)
  "Load local MODULE from `emacs-config-dir`.

MODULE is a symbol or string (e.g. 'zac-theme-autodetection).
If loading fails, emit WARNING via `display-warning` and return nil.
On success, return non-nil." 
  (let* ((name (if (symbolp module) (symbol-name module) module))
         (path (expand-file-name name emacs-config-dir)))
    (if (load path t 'nomessage)
        t
      (display-warning 'init warning :warning)
      nil)))

;; Keep Emacs Customize UI writes out of init.el.
;;
;; "Customize" (a built-in Emacs feature) lets you change options/faces via
;; interactive buffers like M-x customize-variable / M-x customize-face.
;; If you press "Save", Emacs persists those settings by writing Elisp forms.
;; We redirect those writes into `custom-file` to keep init.el readable.
;;
;; This config intentionally does NOT auto-load custom.el. Treat it as
;; optional, machine-written state:
;; - Prefer editing init.el / modules directly for permanent configuration.
;; - If you did save something via Customize and want it enabled, load it
;;   explicitly: M-x load-file RET custom.el, or evaluate (load custom-file).
(setq custom-file (expand-file-name "custom.el" emacs-config-dir))

;; Packages: straight.el + use-package
;; straight is not on ELPA/MELPA; it bootstraps itself from GitHub.
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Pin these GNU ELPA "core" packages to Emacs's built-in copies.
;;
;; `project', `flymake', `xref', `jsonrpc', and `eldoc' are unusual: they
;; ship BOTH in the Emacs tree AND on GNU ELPA as standalone packages.
;; The ELPA release exists so users on older Emacs can pick up newer
;; features without upgrading Emacs itself.  Many third-party packages
;; declare a minimum version in their `Package-Requires' header (e.g.
;; `(project "0.10.0")'); straight honours that by fetching the ELPA
;; copy and adding it to `load-path' alongside the built-in.  Two copies
;; of the same feature name then coexist.
;;
;; Up to Emacs 29 this was silently tolerated — Emacs loaded whichever
;; copy came first.  Emacs 30+ added the stricter `require-with-check'
;; loader, which errors out when a feature was first `provide'd from one
;; path and is later requested from a different one, e.g.:
;;
;;   Feature `project' loaded from /.../emacs-31/.../project.elc is now
;;   provided by ~/.config/emacs/straight/build/project/project.elc
;;
;; Eglot (built-in since Emacs 29) calls `require-with-check' at load
;; time on `(project flymake xref jsonrpc external-completion)', so it
;; is usually the first consumer to surface the mismatch.  lsp-mode,
;; consult, magit, etc. all use plain `require' and silently pick
;; whichever copy comes first — which is why this config "always worked"
;; until Eglot was added.
;;
;; Adding these names to `straight-built-in-pseudo-packages' tells
;; straight to treat them as already-installed and never build a
;; shadowing copy, regardless of what a transitive dep requests.  On
;; Emacs 30+ the in-tree versions are already at or ahead of ELPA, so
;; pinning costs nothing.  If this config is ever run on an older Emacs
;; where an ELPA core package is genuinely newer, revisit this list.
(dolist (pkg '(project flymake xref jsonrpc eldoc))
  (add-to-list 'straight-built-in-pseudo-packages pkg))

;; Install and configure use-package via straight.
;;
;; straight.el is our package manager: it can install packages from ELPA/MELPA
;; and also directly from Git repos (e.g. GitHub) via recipes.
;; use-package provides a declarative way to configure those packages.
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; Guard against stale .elc files in straight-managed packages.
;; This config uses native compilation (Emacs 29+), so personal .el modules are
;; compiled to .eln files in eln-cache — no .elc files are produced for them.
;; However, straight packages do have .elc files which can go stale after updates.
;; auto-compile-on-load-mode recompiles a stale .elc before loading it;
;; auto-compile-on-save-mode recompiles when a .el file is saved.
;; Both complement load-prefer-newer set in early-init.el.
(straight-use-package 'auto-compile)
(require 'auto-compile)
(auto-compile-on-load-mode)
(auto-compile-on-save-mode)

(provide 'emacs-config-core)

;;; emacs-config-core.el ends here
