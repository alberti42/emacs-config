;;; init.el -*- lexical-binding: t; tab-width: 2; -*-

;;; -- Font settings -----------------------------------------------------------

(defvar emacs-config-font-height-by-monitor
  '(("Kuycon G32P" . 180)
    ("LS27A80" . 150)
    ("Unknown"     . 150))
  "Alist mapping a monitor name to the `default' face :height (in 1/10 pt).
The \"Unknown\" entry is the fallback used for any monitor not listed.")

(defun emacs-config-font-height-for-frame (frame)
  "Return the configured `default' :height for FRAME's monitor.
Looks up the monitor name in the alist `emacs-config-font-height-by-monitor',
falling back to the \"Unknown\" entry."
  (let* ((name (alist-get 'name (frame-monitor-attributes frame)))
         (entry (or (assoc name emacs-config-font-height-by-monitor)
                    (assoc "Unknown" emacs-config-font-height-by-monitor))))
    (cdr entry)))

(defun emacs-config-emoji-size-for-height (height)
  "Return the Apple Color Emoji :size that fits a `default' face of HEIGHT.
HEIGHT is the `default' face `:height' (1/10 pt).  Without this, a line
containing an emoji (e.g. 💡) jumps to the emoji font's taller line
height and causes vertical jitter when typing; the size must fit the
default face height, which is itself chosen from the monitor.  A few
coarse buckets track the face height closely enough in practice."
  (cond ((>= height 170) 14)
        ((>= height 150) 12)
        (t 11)))

(defun emacs-config-setup-emoji-fontset (height)
  "Render `emoji' glyphs using \"Apple Color Emoji\" for HEIGHT.
Modify the default fontset to map `emoji' script to Apple Color Emoji,
sized for HEIGHT."
  (set-fontset-font t 'emoji
                    (font-spec :family "Apple Color Emoji"
                               :size (emacs-config-emoji-size-for-height height))))

(defvar emacs-config-icon-scale 0.85
  "Scale of Nerd Font icon glyphs relative to the `default' text size.
  A dedicated icon font like \"Symbols Nerd Font Mono\" may have metrics
  for its glyphs that differ from the default text font, so its icons can
  look oversized at full scale; this factor brings them back into
  proportion.")

(defun emacs-config-icon-size-for-height (height)
  "Return the icon `:size' (points) for a `default' face of HEIGHT (1/10 pt)."
  (* (/ height 10.0) emacs-config-icon-scale))

(defun emacs-config-setup-pua-fontset (height)
  "Render Nerd Fonts codepoints using \"Symbols Nerd Font Mono\" for HEIGHT.
  Map the Private Use Area #xe000-#xffff, which is typically used by Nerd
  Fonts to display their icons, to \"Symbols Nerd Font Mono\".  It covers
  both the BMP PUA (#xe000–#xffff) and the Supplementary
  PUA-A (#xf0000–#xfffff), where Nerd Fonts v3 placed the Material Design
  Icons (nf-md-*); without the second range those glyphs fall back to the
  default font with wrong metrics.  Glyphs are sized to
  `emacs-config-icon-scale' of the text size via the font-spec `:size'."
  (let ((spec (font-spec :family "Symbols Nerd Font Mono"
                         :size (emacs-config-icon-size-for-height height))))
    (set-fontset-font t '(#xe000 . #xffff) spec)
    (set-fontset-font t '(#xf0000 . #xfffff) spec)))

(defun emacs-config-apply-frame-font (&optional frame)
  "Set FRAME's `default' :height and emoji size from its monitor.
  No-op on TTY frames, which ignore font face attributes."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (let ((height (emacs-config-font-height-for-frame frame)))
        (set-face-attribute 'default frame :height height)
        (emacs-config-setup-emoji-fontset height)
        (emacs-config-setup-pua-fontset height)))))

;; We specify the default font for GUI frames; TTY frames ignore font face
;; attributes.  We configure the family/weight plus a baseline height (the
;; "Unknown" fallback) so a frame looks right even before
;; `emacs-config-apply-frame-font' refines it.
(set-face-attribute 'default nil
                    :family "JetBrainsMonoNL Nerd Font Mono" :weight 'light
                    :height (cdr (assoc "Unknown" emacs-config-font-height-by-monitor)))

;; Apply `emacs-config-apply-frame-font' right now for the initial (non-daemon)
;; frame and configure a hook that covers daemon / emacsclient frames and any
;; later frame opened on a different screen.  This MUST run after the
;; `set-face-attribute' above: changing the `default' font re-derives the
;; frame's fontset and drops the customized emoji/PUA Unicode remapping.
(emacs-config-apply-frame-font)
(add-hook 'after-make-frame-functions #'emacs-config-apply-frame-font)

(defun emacs-config-reapply-frame-fonts (&rest _)
  "Re-apply per-frame font settings to all GUI frames after a theme change.
Enabling a theme recomputes the `default' face from the theme specs and
discards the per-frame :height that `emacs-config-apply-frame-font'
sets, so GUI frames would otherwise revert to the global baseline.  That
function is a no-op on TTY frames, so this only touches GUI frames.
Also bound to F12 for manual resync after moving frames to a different
monitor."
  (interactive)
  (dolist (frame (frame-list))
    (emacs-config-apply-frame-font frame)))
(add-hook 'enable-theme-functions #'emacs-config-reapply-frame-fonts)

;; Manual resync: re-derive each frame's font size for its current monitor.
;; Useful after connecting/moving to a different screen.
(global-set-key (kbd "<f12>") #'emacs-config-reapply-frame-fonts)

;; Make the `fixed-pitch' face follow `default' so packages that deliberately
;; route code/tables through `fixed-pitch' (mu4e bodies, `mixed-pitch-mode',
;; some themes' "mixed-fonts" modes) use the SAME mono font as the rest of the
;; editor, rather than the generic stock `fixed-pitch' family.
;;
;; CAUTION: If `default' is ever switched to a proportional font, this turns
;; into a trap — `fixed-pitch' would inherit that proportional font and org
;; tables, src blocks, and anything else relying on `fixed-pitch' would lose
;; fixed-width rendering.  In that case replace `:inherit default' with an
;; explicit monospace `:family' / `:height' / `:weight'.
(set-face-attribute 'fixed-pitch nil :inherit 'default)

;; Disable bidirectional text reordering for better performance.
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
;; Inhibit the Bidirectional Parentheses Algorithm.
(setq bidi-inhibit-bpa t)

;; Defer fontification while input is pending; highlighting catches up on idle.
;; In practice we rarely notice the brief delay, and it makes scrolling and
;; typing feel smoother.
(setq redisplay-skip-fontification-on-input t)

;;; -- General Emacs settings --------------------------------------------------

;; Increase subprocess read buffer from 64KB to 4MB.  LSP servers like
;; rust-analyzer or clangd routinely send multi-megabyte responses;
;; this reduces the number of read() calls Emacs has to make.
(setq read-process-output-max (* 4 1024 1024))

(setq backup-inhibited t)         ; disable backup
(setq make-backup-files nil)      ; stop creating ~ files
(setq auto-save-default nil)      ; disable auto-save completely (no #…# files)
(setq create-lockfiles nil)       ; stop lock files (.#filename)
(setq vc-follow-symlinks t)       ; do not ask confirmation before following symbolic links

;; Control where emacsclient shows a visited buffer: if it is already visible in
;; a window, select that window; otherwise switch to it in the current window.
;; This governs PLACEMENT, not frame creation.  It applies to requests that do
;; not create a frame (`emacsclient' / `emacsclient -n').  It does NOT suppress
;; `emacsclient -c': that frame is created in `server-process-filter' before
;; `server-window' is ever consulted, so a new frame still appears.
(defun my/server-switch-to-buffer (buffer)
  "Select the window already showing BUFFER, or switch in the current window."
  (let ((win (get-buffer-window buffer)))
    (if win
        (select-window win)
      (switch-to-buffer buffer))))
(setq server-window #'my/server-switch-to-buffer)

;; Finder/macOS "Open with Emacs" does NOT go through emacsclient, so
;; `server-window' above does not apply to it.  It arrives as a native NS
;; Apple Event handled by Emacs's own open-file path, governed by
;; `ns-pop-up-frames'.  Its default `fresh' reuses the first frame but opens a
;; NEW frame for every subsequent file; nil always reuses the selected frame,
;; matching the single-frame workflow above.
(when (eq system-type 'darwin)
  (setq ns-pop-up-frames nil))

;; Confirm before C-x C-c: too easy to hit by accident.  `confirm-kill-emacs'
;; only fires when Emacs actually exits; in emacsclient frames C-x C-c closes
;; the frame without killing the daemon, so wrap the command directly and mirror
;; the dispatch in `save-buffers-kill-terminal' to pick the right prompt.
;; (setq confirm-kill-emacs #'y-or-n-p)
(defun my/confirm-save-buffers-kill-terminal (&optional arg)
  "Confirm before running `save-buffers-kill-terminal'."
  (interactive "P")
  (let ((prompt (if (frame-parameter nil 'client)
                    "Really close this frame? "
                  "Really exit Emacs? ")))
    (if (not confirm-kill-emacs)
        (save-buffers-kill-terminal arg)       
      (when (y-or-n-p prompt)
        (let ((confirm-kill-emacs nil))
          (save-buffers-kill-terminal arg))))))
(global-set-key (kbd "C-x C-c") #'my/confirm-save-buffers-kill-terminal)

;; Unbind `transpose-chars': too easy to hit by mistake when reaching for C-y.
(global-unset-key (kbd "C-t"))

;; Add reference to Emacs C source files
(let ((src "~/Documents/Programming/Others/fork-emacs"))
  (when (file-directory-p src)
    (setq source-directory src)))

;; Emacs supports per-file settings embedded directly in source files,
;; either as a first-line header (e.g., -*- coding: utf-8-unix -*-) or
;; a footer block:
;;
;;   Local Variables:
;;   buffer-file-coding-system: utf-8-unix
;;   End:
;;
;; Emacs applies such settings silently if the variable declares
;; itself safe via a safe-local-variable property (e.g., a predicate
;; like #'stringp). Since buffer-file-coding-system lacks that
;; property, Emacs prompts for confirmation instead. This entry is a
;; workaround: it pre-approves this specific pair so Emacs skips the
;; prompt.
(setq safe-local-variable-values
      '((TeX-engine . pdflatex)
        (elisp-lint-indent-specs (git-gutter:awhen . 1))
        (buffer-file-coding-system . utf-8-unix)))

;; Accept any string filename for package-lint's main-file dir-local.
(put 'package-lint-main-file 'safe-local-variable #'stringp)

;; Bootstrap
;; Keep init.el compact; details live in emacs-config-core.el.
(let ((init-path (or load-file-name
                     user-init-file
                     (expand-file-name "init.el" user-emacs-directory))))
  (load (expand-file-name
         "emacs-config-core"
         (file-name-directory (file-truename init-path)))
        nil 'nomessage))

;; UI chrome, fonts, frame setup, and TTY mode-line separator.
(emacs-config-load-module
 'ui-config
 "Could not load ui-config.el; UI settings are disabled.")

;; Centered startup splash buffer (GUI only, no file args).
(emacs-config-load-module
 'welcome-config
 "Could not load welcome-config.el; startup splash is disabled.")

;; Transient corner toast (popon, TTY+GUI) for `display-warning' messages,
;; so warnings don't hide silently in the `*Warnings*' buffer.
(emacs-config-load-module
 'warning-toast
 "Could not load warning-toast.el; warnings use the default *Warnings* buffer.")

;; Built-ins
;; cl-lib: Common Lisp compatibility helpers used by many packages.
(use-package cl-lib
  :straight nil) ; use built-in cl-lib (Emacs 24+), don't fetch via straight

;; Smart auto-revert: silently revert clean buffers on external change,
;; prompt when the buffer has unsaved local edits.
(emacs-config-load-module
 'auto-revert-config
 "Could not load auto-revert-config.el; smart auto-revert is disabled.")

;; UI & Convenience
;; which-key: display available keybindings in popup.
(use-package which-key
  :straight nil  ; use built-in which-key (Emacs 30+), don't fetch via straight
  :config
  (setq which-key-idle-delay 1.0)
  (setq which-key-separator " → ")
  (which-key-mode 1))

;; vundo: visual undo tree, navigate undo history as a tree diagram.
(use-package vundo
  :straight t
  :bind ("C-x u" . vundo))

;; macOS pseudo-daemon
;; Keep Dock icon + menu functional after closing the last GUI frame when using
;; Emacs in server/daemon-style workflows.
;; (emacs-config-load-module
;;   'mac-pseudo-daemon-config
;;   "Could not load mac-pseudo-daemon-config.el; macOS pseudo-daemon behavior is disabled.")

;; electric-pair-mode policy + region wrapping.
(emacs-config-load-module
 'electric-config
 "Could not load electric-config.el; electric-pair customization is disabled.")

;; Accept y/n instead of typing yes/no in full.
(setq use-short-answers t)

;; Write the bookmark file on every set/delete, not just on a clean exit
;; (the `t' default only saves when Emacs is killed, losing bookmarks on crash).
(setq bookmark-save-flag 1)

;; Repeat C-u C-SPC (`set-mark-command') with a bare C-SPC to keep popping
;; the mark ring without re-typing the prefix.
(setq set-mark-command-repeat-pop t)

;; Per-context auxiliary bookmark files.  The library is mechanism-only; this
;; config module loads it, enables the mode, and resolves relative
;; `bookmark-aux-file' values (set per project via .dir-locals.el) against the
;; project root.
(emacs-config-load-module
 'bookmark-aux-config
 "Could not load bookmark-aux-config.el; auxiliary bookmark files are disabled.")

;; Save minibuffer history
(savehist-mode 1)

;; Typing with an active region replaces it (modern editor behavior).
(delete-selection-mode 1)

;; Focus the *Help* window when it pops up so `q` closes it without an extra C-x o.
(setq help-window-select t)

;; Recently visited files
(emacs-config-load-module
 'recentf-config
 "Could not load recentf-config.el; recent files list is disabled.")

;; Buffer list (ibuffer) with project grouping and nerd-icons.
(emacs-config-load-module
 'buffers-config
 "Could not load buffers-config.el; ibuffer customizations are disabled.")

;; Project management (submodule-aware root detection)
(emacs-config-load-module
 'project-config
 "Could not load project-config.el; project root detection uses default behavior.")

;; Fast project search (prefer ripgrep)
(emacs-config-load-module
 'search-config
 "Could not load search-config.el; using default project search backend.")

;; Editable grep buffers (pairs with embark-export for project-wide replace)
(emacs-config-load-module
 'wgrep-config
 "Could not load wgrep-config.el; editable grep buffers are disabled.")

;; Completion system (minibuffer + in-buffer)
(emacs-config-load-module
 'completion
 "Could not load completion.el; using default completion behavior.")

;; Nerd icons (Nerd Fonts)
(emacs-config-load-module
 'nerd-icons-config
 "Could not load nerd-icons-config.el; nerd icons are disabled.")

;; Line numbers
(setq display-line-numbers-type t) ; (t displays absolute line numbers; alternatives: 'relative or 'visual)
;; Non-nil keeps current line absolute while others are relative.
(setq display-line-numbers-current-absolute t)
;; Fix the gutter to a constant width so it never reflows mid-scroll.
;; display-line-numbers-width is buffer-local, so setq-default is required.
;; Without a fixed value, Emacs recomputes the width on every redisplay from the
;; last visible line number (not the total buffer size), causing the gutter to
;; jump whenever scrolling causes the last visible line to cross a power-of-10
;; boundary.  A fixed value of 4 is treated as a minimum: for buffers exceeding
;; 9999 lines Emacs still expands the width automatically.  This mimics neovim,
;; which also reserves a fixed 4 digits by default.
(setq-default display-line-numbers-width 4)
;; Reserve 1 column for the git-gutter indicator in all buffers so the layout
;; never shifts when switching between VC and non-VC buffers.
(setq-default left-margin-width 1)
;; display-line-numbers mode is enabled in all buffers where
(global-display-line-numbers-mode 1)
;; Disable line numbers and suppress horizontal wheel scroll in terminal/shell
;; buffers.  Hscroll is suppressed via a buffer-local flag rather than by
;; setting `truncate-lines' to nil: the latter would cause Emacs to reserve the
;; last column for the continuation glyph, making ghostel's prompt overflow by one
;; character because it reports the full window width to the child process.
(dolist (hook '(shell-mode-hook eshell-mode-hook term-mode-hook ghostel-mode-hook treemacs-mode-hook))
  (add-hook hook (lambda ()
                   (display-line-numbers-mode -1)
                   (setq-local scroll-config-suppress-hscroll t))))

;; Terminal emulators (term, eshell, ghostel)
(emacs-config-load-module
 'terminal-config
 "Could not load terminal-config.el; terminal settings are disabled.")

;; Wrapping helpers (soft wrap, visual only)
(use-package soft-wrap
  :straight nil
  :load-path emacs-config-dir
  :commands (soft-wrap-mode global-soft-wrap-mode)
  :custom
  (soft-wrap-load-diagnostics nil))

;; Olivetti: centred prose layout (alternative to soft-wrap for testing).
(emacs-config-load-module
 'olivetti-config
 "Could not load olivetti-config.el; olivetti is disabled.")

;; Tree-sitter grammars (auto-install missing ones)
(emacs-config-load-module
 'treesitter-config
 "Could not load treesitter-config.el; tree-sitter grammar bootstrap is disabled.")

;; Per-syntax indentation settings
(emacs-config-load-module
 'syntaxes
 "Could not load syntaxes.el; per-syntax settings are disabled.")

;; Terminal key decoding (CSI u).
(emacs-config-load-module
 'csi-u-keys
 "Could not load csi-u-keys.el; CSI-u key decoding is disabled.")

;; vim-file-locals: parse Vim modelines/file-local settings in files.
(use-package vim-file-locals
  :straight (vim-file-locals
             :type git
             :host github
             :repo "abougouffa/emacs-vim-file-locals")
  ;; Enable globally after startup; it adds `vim-file-locals-apply` to
  ;; `find-file-hook` for newly opened files.
  :hook (after-init . vim-file-locals-mode))

;; Clipboard
(setq select-enable-clipboard t)

;; Before overwriting the clipboard with a kill, save its current
;; content into the kill ring so M-y can still retrieve it.
(setq save-interprogram-paste-before-kill t)

;; macOS: sync kill ring → clipboard via pbcopy (TTY and GUI).
(when (eq system-type 'darwin)
  (emacs-config-load-module
   'mac-clipboard
   "Could not load mac-clipboard.el; macOS clipboard sync is disabled."))

;; Linux: sync clipboard via xclip; also enable X11 primary selection.
;; (declare-function xclip-mode "xclip")
;; (when (eq system-type 'gnu/linux)
;;   (use-package xclip
;;     :if (not window-system)
;;     :config
;;     (setq select-enable-primary t)
;;     (xclip-mode 1)))

;; General-purpose interactive utilities (copy-buffer-file-name, …)
(emacs-config-load-module
 'utils
 "Could not load utils.el; utility commands are disabled.")

;; Dired and file manager
(emacs-config-load-module
 'dired-config
 "Could not load dired-config.el; dired customizations are disabled.")

;; Window navigation (C-c <arrow>) and resizing (C-c C-<arrow>)
;; Match tmux's repeat-time default (500ms) for consistent feel.
(setq repeat-exit-timeout 0.5)
(emacs-config-load-module
 'windows-config
 "Could not load windows-config.el; windmove and window resizing are disabled.")

;;;; -- Development tools ------------------------------------------------------

;; multiple-cursors: Sublime Text-style multiple cursors.
(use-package multiple-cursors
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)))

;; auth-source-1password: serve the GitHub/Forge token from 1Password (`op')
;; instead of a plaintext ~/.authinfo.  Loaded before magit so the backend is
;; registered before Forge first resolves a token.
(emacs-config-load-module
 'auth-source-1password-config
 "Could not load auth-source-1password-config.el; 1Password auth-source is disabled.")

;; magit: Git porcelain, forge (GitHub/GitLab), and nerd-icons integration.
(emacs-config-load-module
 'magit-config
 "Could not load magit-config.el; Magit is disabled.")

;; ;; Project tree (TTY-friendly)
;; (emacs-config-load-module
;;  'treemacs-config
;;  "Could not load treemacs-config.el; Treemacs is disabled.")

;; Speedbar: built-in file/tag browser.
(emacs-config-load-module
 'speedbar-config
 "Could not load speedbar-config.el; Speedbar customizations are disabled.")

;; inheritenv: propagate buffer-local `process-environment' and `exec-path'
;; from the caller buffer into commands that internally pop to a fresh
;; buffer (and therefore lose the caller's buffer-locals) before spawning.
;; `inheritenv-add-advice' wraps a command so that, at spawn time, it copies
;; the caller buffer's env into the target buffer.
;;
;; Precedence note.  Some target buffers (notably agent-shell, which calls
;; `hack-dir-local-variables-non-file-buffer' on its own buffer right after
;; creation) re-apply dir-locals AFTER inheritenv has already snapshotted
;; the caller env.  Because the dir-local hook (`uv--apply-dir-local')
;; sets buffer-local `process-environment'/`exec-path' explicitly, its
;; values OVERRIDE whatever was inherited.  Net result: if the project has
;; a `.dir-locals.el' with `uv-venv', it wins over an interactive
;; `uv-activate-buffer' done in the caller buffer.  Everything else on
;; this list (shells, terminals, generic project.el spawners) does NOT
;; re-apply dir-locals, so the inherited env is what spawns see.
(use-package inheritenv
  :config
  (dolist (cmd '(shell
                 eshell
                 term
                 ghostel
                 async-shell-command
                 compile
                 project-shell
                 project-eshell
                 project-async-shell-command
                 project-compile
                 agent-shell
                 agent-shell-google-start-gemini
                 agent-shell-anthropic-start-claude-code
                 agent-shell-opencode-start-agent))
    (inheritenv-add-advice cmd)))

(emacs-config-load-module
 'apheleia-config
 "Could not load apheleia-config.el; formatters are disabled.")

;; Buffer-local uv virtualenv activation (VIRTUAL_ENV per buffer).
(emacs-config-load-module
 'uv-config
 "Could not load uv-config.el; per-buffer uv activation is disabled.")

;; (emacs-config-load-module
;;  'pyenv-config
;;  "Could not load pyenv-config.el; per-buffer pyenv activation is disabled.")

;;; Build / compile

(emacs-config-load-module
 'compile-config
 "Could not load compile-config.el; the compile keybinding is disabled.")

;;; VCS gutter

(emacs-config-load-module
 'git-gutter-config
 "Could not load git-gutter-tty.el; VCS gutter is disabled.")

;;;; -- LSP clients ------------------------------------------------------------

;; yasnippet: snippet engine.  Loaded before lsp-core because lsp-mode
;; expands LSP completion placeholders through it.
(emacs-config-load-module
 'yasnippet-config
 "Could not load yasnippet-config.el; snippet expansion is disabled.")

;; LSP modules
(emacs-config-load-module
 'lsp-core
 "Could not load lsp-core.el; LSP is disabled.")

(emacs-config-load-module
 'lsp-python-config
 "Could not load lsp-python-config.el; Python LSP is disabled.")

(emacs-config-load-module
 'lsp-elisp-config
 "Could not load lsp-elisp-config.el; Elisp LSP is disabled.")

(emacs-config-load-module
 'lsp-web-config
 "Could not load lsp-web-config.el; TypeScript/JavaScript LSP is disabled.")

(emacs-config-load-module
 'lsp-json-config
 "Could not load lsp-json-config.el; JSON LSP is disabled.")

(emacs-config-load-module
 'lsp-ltex-plus-config
 "Could not load lsp-ltex-plus-config.el; LTEX+ is disabled.")

;; (emacs-config-load-module
;;  'harper-config
;;  "Could not load harper-config.el; Harper is disabled.")

(emacs-config-load-module
 'lsp-swift-config
 "Could not load lsp-swift-config.el; Swift LSP is disabled.")

(emacs-config-load-module
 'lsp-rust-config
 "Could not load lsp-rust-config.el; Rust LSP is disabled.")

(emacs-config-load-module
 'lsp-kotlin-config
 "Could not load lsp-kotlin-config.el; Kotlin LSP is disabled.")

(emacs-config-load-module
 'lsp-c-config
 "Could not load lsp-c-config.el; C/C++ LSP is disabled.")

(emacs-config-load-module
 'lsp-tex-config
 "Could not load lsp-tex-config.el; TeX/LaTeX LSP is disabled.")

;;;; -------------------------------------------------------------------------

;; Editing

;; Shared PDF viewer selection (Skim / pdf-tools / OS default), consumed by
;; latex-config and typst-config.  Loaded first so both can require it.
(emacs-config-load-module
 'pdf-preview
 "Could not load pdf-preview.el; shared PDF viewer selection is disabled.")

(emacs-config-load-module
 'latex-config
 "Could not load latex-config.el; AUCTeX is disabled.")

;; Typst authoring (typst-ts-mode, tree-sitter backed)
(emacs-config-load-module
 'typst-config
 "Could not load typst-config.el; Typst editing is disabled.")

;; latex-to-svg rendering engine (LaTeX -> SVG).  Registers + configures the
;; shared library; must precede its front-ends (`markdown-config' /
;; `org-config' / `agent-shell-setup') so straight resolves their dependency on
;; it.
(emacs-config-load-module
 'latex-to-svg-config
 "Could not load latex-to-svg-config.el; SVG math rendering is disabled.")

;; Markdown reading/authoring (markdown-ts-mode, olivetti).  Loads after
;; `latex-to-svg-config' so straight can resolve `latex-to-svg-for-markdown''s
;; dependency on the engine (`latex-to-svg') from the local checkout.
(emacs-config-load-module
 'markdown-config
 "Could not load markdown-config.el; Markdown enhancements are disabled.")

;; Org mode (LaTeX preview, Python babel, literate notebooks)
(emacs-config-load-module
 'org-config
 "Could not load org-config.el; Org mode enhancements are disabled.")

;; Search a tree of org notes by meaning or by word (one Rust binary over a
;; pipe, no database).  Before vulpea-config, which loads the vulpea-vault/
;; module that ties a vault's org-semantic index to `vulpea-vault-switch'.
(emacs-config-load-module
 'org-semantic-config
 "Could not load org-semantic-config.el; semantic search over the notes is disabled.")

;; Note database over the org notes.  Indexes every org node carrying an `:ID:';
;; also owns the `org-id' / `org-attach' settings that share that property, and
;; extends `attachment:' to cross-note links.  After org-config so org is
;; configured first.
(emacs-config-load-module
 'vulpea-config
 "Could not load vulpea-config.el; the note database is disabled.")

;; PDF viewer (pdf-tools) with continuous scroll
(emacs-config-load-module
 'pdf-tools-config
 "Could not load pdf-tools-config.el; in-Emacs PDF viewing is disabled.")

;; emacs-jupyter (remote Jupyter kernels via kernel protocol; on-disk
;; format stays .org, no .ipynb).  Loads after org-config so the babel
;; jupyter backend registers cleanly on top of org-babel-load-languages.
(emacs-config-load-module
 'jupyter-config
 "Could not load jupyter-config.el; emacs-jupyter is disabled.")

;; Spyder-style `# %%' code cells in plain .py/.jl/.R files; cell-aware
;; navigation and eval.  Language-agnostic; integrates with emacs-jupyter
;; when present (cell eval dispatches to the bound kernel).
(emacs-config-load-module
 'code-cells-config
 "Could not load code-cells-config.el; cell-aware navigation is disabled.")

;; lua-mode: major mode for editing Lua.
(use-package lua-mode)

;; ssh-config-mode: major mode for ~/.ssh/config.
(use-package ssh-config-mode)

;; applescript-mode: major mode for AppleScript (font-locking, indentation).
;; The mode is old-style: it sets `font-lock-defaults' but ends with
;; `run-hooks' instead of `run-mode-hooks', so `after-change-major-mode-hook'
;; never fires and `global-font-lock-mode' never turns fontification on. Enable
;; `font-lock-mode' from its own hook (which it does run) to fix highlighting.
(use-package applescript-mode
  :hook (applescript-mode . font-lock-mode))

;; swift-mode: major mode for Swift.
(use-package swift-mode)

;; AI agent shell (Claude Code, Gemini CLI, etc. via ACP)
(emacs-config-load-module
 'agent-shell-setup
 "Could not load agent-shell-setup.el; agent-shell is disabled.")

;; Themes
;; Load order within themes-config: theme-harmonize → load-theme → zac-theme-autodetection.
;; See themes-config.el for the rationale.
(emacs-config-load-module
 'themes-config
 "Could not load themes-config.el; theme and appearance settings are disabled.")

;; Terminal UX
;; Mouse support in terminal Emacs.
;; `xterm-mouse-mode` enables mouse events in terminal emulators that support it.
(use-package mouse
  :straight nil
  :if (not window-system)
  :preface
  (defun emacs-config--scroll-down-1 ()
    (interactive)
    (scroll-down 1))

  (defun emacs-config--scroll-up-1 ()
    (interactive)
    (scroll-up 1))
  :config
  (xterm-mouse-mode 1)
  ;; Wheel events in terminals are usually mouse-4/mouse-5.
  ;; Keep wheel-up/wheel-down bindings too (some builds/terminals use them).
  (global-set-key [mouse-4] #'emacs-config--scroll-down-1)
  (global-set-key [mouse-5] #'emacs-config--scroll-up-1)
  (global-set-key [wheel-up] #'emacs-config--scroll-down-1)
  (global-set-key [wheel-down] #'emacs-config--scroll-up-1))

;; Cursor navigation (smart Home/End)
(emacs-config-load-module
 'navigation-config
 "Could not load navigation-config.el; smart Home/End keys are disabled.")

;; Scrolling
(emacs-config-load-module
 'scroll-config
 "Could not load scroll-config.el; scrolling settings are disabled.")

;; rmate-protocol server for editing remote files over SSH tunnels.
(use-package remacs
  :straight nil
  :load-path emacs-config-dir
  :commands (remacs-start remacs-stop))

;; tmux open-file bridge: open files in Emacs from tmux via IPC.
;; Requires Emacs 29+ for server-after-make-frame-hook.
(use-package tmux-tandem
  :if (>= emacs-major-version 29)
  :straight (tmux-tandem
             :type git
             :host github
             :repo "alberti42/emacs-tmux-tandem")
  :config
  (tmux-tandem-enable))

;; straight-overview: selective-upgrade UI for straight.el packages.
(emacs-config-load-module
 'straight-overview-config
 "Could not load straight-overview-config.el; the straight-overview UI is disabled.")

;; Tetris: built-in game with tunable fall speed.
(emacs-config-load-module
 'tetris-config
 "Could not load tetris-config.el; Tetris speed tuning is disabled.")

