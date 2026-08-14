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

;; Where this config's machine-local state goes.
;;
;; `user-emacs-directory' is a symlink into a git worktree here, so anything a
;; package persists by default (recentf's list, `org-id-locations', treemacs's
;; workspaces, …) would land in the repository.  None of it is configuration:
;; it is per-machine state, regenerable, and never worth committing.  It goes
;; under `$XDG_CACHE_HOME/emacs/' instead.
;;
;; This lives in core, beside `emacs-config-dir', because it is the same kind
;; of fact — where this configuration keeps its files — and because core is
;; loaded before every module, so any of them may use it.
(defconst emacs-config-cache-dir
  (expand-file-name "emacs" (or (getenv "XDG_CACHE_HOME")
                                (expand-file-name "~/.cache")))
  "Directory for this configuration's machine-local state.
Never inside `emacs-config-dir', which is a git worktree.
Use `emacs-config-cache-file' rather than expanding against this
directly, so the directory is created before anything writes to it.")

(defun emacs-config-cache-file (name)
  "Return the path of NAME inside `emacs-config-cache-dir'.
Creates that directory, so the caller may hand the result straight to a
package that will write there without checking first.  Called at load
time by the modules that set such a path, so the cost is one `mkdir -p'
per setting."
  (make-directory emacs-config-cache-dir t)
  (expand-file-name name emacs-config-cache-dir))

(defun emacs-config-load-module (module warning)
  "Load local MODULE from `emacs-config-dir`.

MODULE is a symbol or string (e.g. 'zac-theme-autodetection).
If loading fails, emit WARNING via `display-warning` and return nil.
On success, return non-nil.

Always loads the `.el' source and never a `.elc'.  Passing the explicit
`.el' path plus NOSUFFIX makes `load' open exactly that file, so a stray
byte-compiled `.elc' left in `emacs-config-dir' can never shadow the
source (which it would otherwise do when their mtimes tie, defeating
`load-prefer-newer').

This config never byte-compiles its own modules, so a sibling `.elc' is
always a stray artifact (e.g. an accidental `byte-compile-file').  When
one is found it is warned about and deleted, since it can only cause the
shadowing bug above."
  (let* ((name (if (symbolp module) (symbol-name module) module))
         (path (concat (expand-file-name name emacs-config-dir) ".el"))
         (elc (concat path "c")))
    (when (file-exists-p elc)
      (display-warning 'init
                       (format "Deleting stray %s (this config never compiles modules)"
                               (file-name-nondirectory elc))
                       :warning)
      (ignore-errors (delete-file elc)))
    (if (load path t 'nomessage 'nosuffix)
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

(defconst emacs-config-patches-dir
  (expand-file-name "patches" emacs-config-dir)
  "Directory containing patch files for straight-managed packages.")

(defun emacs-config-patch-package (package &rest patches)
  "Register :pre-build commands to apply PATCHES to PACKAGE.
PATCHES are filenames relative to `emacs-config-patches-dir'.
Each patch is applied idempotently: already-applied patches are
skipped, failures emit a warning instead of aborting startup."
  (let ((cmds
         (mapcar
          (lambda (p)
            (let ((path (expand-file-name p emacs-config-patches-dir)))
              `(eval
                (let ((default-directory
                       (straight--repos-dir ,(symbol-name package))))
                  (unless (zerop (call-process
                                 "git" nil nil nil
                                 "apply" "--reverse" "--check" ,path))
                    (unless (zerop (call-process
                                   "git" nil nil nil "apply" ,path))
                      (warn ,(format "%s: patch %s failed to apply"
                                     package p))))))))
          patches)))
    (straight-register-package `(,package :pre-build ,cmds))))

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
