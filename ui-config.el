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
  ;; (add-to-list 'default-frame-alist '(undecorated-round . t))
  nil)
 (t
  ;; On other GUI builds, fall back to a frameless (undecorated) window.
  ;; (add-to-list 'default-frame-alist '(undecorated . t))
  (add-to-list 'default-frame-alist '(internal-border-width . 10))))

;; macOS: free the right Option for system character composition
;; (e.g. ⌥u u → ü, ⌥s → ß). Left Option stays as Meta for Emacs.
;; Only affects the Nextstep GUI build; TTY composition is handled
;; by the terminal emulator.
(when (eq system-type 'darwin)
  (setq ns-alternate-modifier 'meta
        ns-right-alternate-modifier 'none))

;; macOS: disable the dangerous system-style shortcuts ⌘-w (delete-frame)
;; and ⌘-q (save-buffers-kill-emacs).  A single stray keypress otherwise
;; tears down a frame or the whole session.  Kill Emacs deliberately via
;; `C-x C-c' and close windows/frames via the usual `C-x' bindings.
(when (eq system-type 'darwin)
  (global-unset-key (kbd "s-w"))
  (global-unset-key (kbd "s-q")))

;; macOS: avoid using native full screen in separate macOS space
(when (eq system-type 'darwin)
  (setq ns-use-native-fullscreen nil))

;; macOS: determine activation policy a daemon adopts after losing
;; its last GUI frame.
(when (eq system-type 'darwin)
  (setq ns-frameless-activation-policy 'regular))

;; macOS: give the daemon a Dock tile at startup (no visible window) so a Dock
;; click reaches it and the reopen patch (applicationShouldHandleReopen:) turns
;; the click into a real frame.  `ns-show-daemon-in-dock' is provided by our
;; nsterm reopen patch.
(when (and (eq system-type 'darwin) (fboundp 'ns-show-daemon-in-dock))
  (ns-show-daemon-in-dock))

;; Default frame size + fullscreen toggle.
;; Frames are born fullscreen (fullboth).  F11 toggles to a windowed frame whose
;; size and position are whatever they were before going fullscreen, falling back
;; to the `emacs-config-frame-width'/`emacs-config-frame-height' size, centered,
;; the first time (since a frame created fullscreen never had a windowed
;; geometry).  TTY frames ignore frame sizing.
(defvar emacs-config-frame-width 160
  "Default windowed frame width in characters, used when leaving fullscreen.")

(defvar emacs-config-frame-height 50
  "Default windowed frame height in characters, used when leaving fullscreen.")

(add-to-list 'default-frame-alist '(fullscreen . fullboth))

;; CUSTOM TOGGLE REPLACING BUILT-IN TOGGLE-FRAME-FULLSCREEN
;;
;; Because frames are born fullscreen (see `default-frame-alist' above), so they
;; never had a windowed geometry.  The built-in toggle, when leaving fullscreen,
;; just clears the `fullscreen' parameter and relies on the toolkit/WM to
;; restore the previous windowed size — which here doesn't exist, so we land
;; in an arbitrary WM-default frame.  It also never recenters (our centering
;; only runs on frame-creation hooks, not on toggle).  This command fixes both:
;; it stashes the windowed size and position on the way into fullscreen and
;; restores them on the way out (falling back to the `emacs-config-frame-*' size,
;; centered, on the very first toggle).  Net effect: no windowed geometry has to
;; be preconfigured at startup: we start fullscreen and recover a properly
;; sized+placed window on F11.
(defun emacs-config-toggle-fullscreen (&optional frame)
  "Toggle FRAME between fullboth fullscreen and a windowed size+position.
On entering fullscreen, remember the current windowed size and position;
on leaving, restore them.  The first time out of fullscreen there is no
remembered geometry, so fall back to the `emacs-config-frame-width' /
`emacs-config-frame-height' size and center the frame."
  (interactive)
  (let* ((frame (or frame (selected-frame)))
         (fs (frame-parameter frame 'fullscreen)))
    (if (memq fs '(fullscreen fullboth))
        ;; Leaving fullscreen: drop fullscreen, restore size, then restore the
        ;; stored position (or center if we have none yet).
        (let ((size (or (frame-parameter frame 'emacs-config-windowed-size)
                        (cons emacs-config-frame-width
                              emacs-config-frame-height)))
              (pos (frame-parameter frame 'emacs-config-windowed-position)))
          (set-frame-parameter frame 'fullscreen nil)
          (set-frame-size frame (car size) (cdr size))
          ;; Defer positioning so the WM has applied the new outer size first.
          (if pos
              (run-at-time 0 nil
                           (lambda (f l tp)
                             (when (frame-live-p f)
                               (set-frame-position f l tp)))
                           frame (car pos) (cdr pos))
            (run-at-time 0 nil #'emacs-config-center-frame frame)))
      ;; Entering fullscreen: stash the current size and position, then go
      ;; fullboth.
      (set-frame-parameter frame 'emacs-config-windowed-size
                           (cons (frame-width frame) (frame-height frame)))
      (set-frame-parameter frame 'emacs-config-windowed-position
                           (frame-position frame))
      (set-frame-parameter frame 'fullscreen 'fullboth))))

(global-set-key [f11] #'emacs-config-toggle-fullscreen)

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
      ;; Fullscreen/maximized frames are sized and positioned by the window
      ;; manager; calling `set-frame-position' on them only shoves the
      ;; already-full-size frame partly off-screen.  Leave them alone.
      (when (and wa
                 (not (memq fs '(fullboth fullscreen maximized)))
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

;; Opt in to emoji icons in TTY — terminal renders them natively from the
;; Unicode codepoint.  Requires local/icons.el patch (see CLAUDE.md).
(setq icons-tty-emoji t)

(provide 'ui-config)

;;; ui-config.el ends here
