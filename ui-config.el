;;; ui-config.el --- UI chrome, fonts, and visual settings -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Visual presentation layer: UI chrome, window dividers, frame chrome,
;; per-frame font/centering setup, and the TTY mode-line separator.
;; Loaded early, right after bootstrap, so frames look right from the start.
;;

;;; Code:

;; UI chrome
;; Keep window UI minimal and consistent across GUI/TTY.
(setq inhibit-startup-screen t)   ; inhibit splash screen at startup
(setq ring-bell-function 'ignore) ; disable all bells
(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))             ; turn off menu bar
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))             ; turn off tool bar icons
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))           ; turn off scroll bars
(when (fboundp 'tooltip-mode)
  (tooltip-mode -1))              ; turn off tooltips

;; Always use minibuffer prompts (no GUI dialog boxes).
(setq use-dialog-box nil)
;; Also avoid GUI file-picker dialogs
(setq use-file-dialog nil)

;; Window dividers (GUI)
;; The vertical divider between treemacs and the buffer is drawn by Emacs's
;; window-divider-mode (right side).  Enable bottom-only dividers to get a
;; matching 2px bar between the mode-line and the minibuffer.
(setq window-divider-default-places 'bottom-only)
(setq window-divider-default-bottom-width 2)
(window-divider-mode 1)

;; Truncation and continuation glyphs.
;; In GUI, Emacs uses fringe bitmaps for these; the display-table slots are
;; only visible in TTY frames.  Setting them here is harmless in GUI.
(defface special-glyphs
  '((t :inherit (shadow default)))
  "Face for truncation and continuation glyphs."
  :group 'basic-faces)

;; If it's nil, create a fresh display table and assign it
(or standard-display-table
    (setq standard-display-table (make-display-table)))

;; Vertical border character between side-by-side windows.
;; The default `|` leaves gaps with most monospace fonts; `█` (FULL BLOCK)
;; renders as a solid continuous bar.
(set-display-table-slot standard-display-table 'vertical-border (make-glyph-code ?█))               ; vertical border
(set-display-table-slot standard-display-table 'truncation (make-glyph-code ?… 'special-glyphs))    ; truncation sign
(set-display-table-slot standard-display-table 'wrap (make-glyph-code ?↲ 'special-glyphs))          ; continuation sign

;; TTY mode-line separator Emacs fills the trailing space of the TTY mode-line
;; via mode-line-end-spaces, which defaults to "%-" (fill with dashes).  We
;; override it after all themes load.  The :eval guard keeps GUI frames
;; unaffected.  Use (make-string 500 ?─) instead of "" to fill with ─ (U+2500),
;; drawing a continuous horizontal line across the mode-line (500 chars gets
;; truncated to window width).
(defun emacs-config--tty-mode-line-separator ()
  (setq-default mode-line-end-spaces
                '(:eval (unless (display-graphic-p) ""))))
(add-hook 'after-init-hook #'emacs-config--tty-mode-line-separator)

;; Frame chrome
(cond
 ((eq system-type 'darwin)
  ;; emacs-plus: frameless window with native macOS rounded corners.
  (add-to-list 'default-frame-alist '(undecorated-round . t)))
 (t
  ;; On other GUI builds, fall back to a frameless (undecorated) window.
  (add-to-list 'default-frame-alist '(undecorated . t))
  (add-to-list 'default-frame-alist '(internal-border-width . 10))))

;; macOS: free the right Option for system character composition
;; (e.g. ⌥u u → ü, ⌥s → ß). Left Option stays as Meta for Emacs.
;; Only affects the Nextstep GUI build; TTY composition is handled
;; by the terminal emulator.
(when (eq system-type 'darwin)
  (setq ns-alternate-modifier 'meta
        ns-right-alternate-modifier 'none))

;; macOS: avoid using native full screen in separate macOS space
(when (eq system-type 'darwin)
  (setq ns-use-native-fullscreen nil))

;; Default frame size; TTY frames ignore these.
;; (add-to-list 'default-frame-alist '(width . 200))
;; (add-to-list 'default-frame-alist '(fullscreen . fullheight))
(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Ensure GUI Emacs creates/raises a frame.
;; - Some macOS setups can start Emacs without presenting a visible window.
;; - `emacsclient -c` can create a frame without activating the app.
(defun emacs-config--activate-gui-frame (&optional frame)
  "Raise FRAME and give it focus (best-effort)."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (with-selected-frame frame
        (run-at-time
         0 nil
         (lambda (f)
           (when (frame-live-p f)
             (select-frame-set-input-focus f)
             (raise-frame f)))
         frame)))))

;; Per-frame GUI setup: fonts and centering.
;; Hooked to both emacs-startup-hook (direct GUI launch) and
;; after-make-frame-functions (daemon/emacsclient GUI frame).
(defun emacs-config-center-frame (&optional frame)
  "Center FRAME on its current monitor (GUI only).
Skip frames whose `fullscreen' state already fixes both dimensions
\(maximized or fullboth): repositioning them only shifts them off the
screen corner."
  (when (display-graphic-p)
    (let* ((frame (or frame (selected-frame)))
           (fs (frame-parameter frame 'fullscreen))
           (wa (and (fboundp 'frame-monitor-workarea)
                    (frame-monitor-workarea frame))))
      (when (and wa
                 (not (memq fs '(maximized fullboth)))
                 (fboundp 'frame-outer-width) (fboundp 'frame-outer-height))
        (let* ((mx (nth 0 wa))
               (my (nth 1 wa))
               (mw (nth 2 wa))
               (mh (nth 3 wa))
               (fw (frame-outer-width frame))
               (fh (frame-outer-height frame))
               (y (if (eq fs 'fullheight)
                      my
                    (+ my (/ (- mh fh) 2)))))
          (set-frame-position frame
                              (+ mx (/ (- mw fw) 2))
                              y))))))

(defun emacs-config-setup-frame (&optional frame)
  "Apply per-frame settings to FRAME.
Enforces no menu bar (emacsclient GUI frames re-enable it by default),
and applies GUI-only settings: cursor shape and frame centering.

For more infos about frame parameters, visit https://www.gnu.org/software/emacs/manual/html_node/elisp/Frame-Parameters.html#Frame-Parameters"
  (with-selected-frame (or frame (selected-frame))
    ;; Enforce no menu bar on every frame (emacsclient GUI frames re-enable it
    ;; by default; menu-bar-mode -1 at startup is not enough).
    (set-frame-parameter nil 'menu-bar-lines 0)
    (when (display-graphic-p)
      (blink-cursor-mode 1)
      (set-frame-parameter nil 'cursor-type 'box)
      (run-at-time 0 nil #'emacs-config-center-frame (selected-frame)))))

(add-hook 'emacs-startup-hook #'emacs-config-setup-frame)
(add-hook 'after-make-frame-functions #'emacs-config-setup-frame)

;; When running as a server, prefer focusing frames created by emacsclient.
;; This is important to ensure that 'emacsclient -a= -n -c' brings emacs in focus.
(with-eval-after-load 'server
  (when (boundp 'server-after-make-frame-hook)
    (add-hook 'server-after-make-frame-hook #'emacs-config--activate-gui-frame)))

;; Opt in to emoji icons in TTY — terminal renders them natively from the
;; Unicode codepoint.  Requires local/icons.el patch (see CLAUDE.md).
(setq icons-tty-emoji t)

(provide 'ui-config)

;;; ui-config.el ends here
