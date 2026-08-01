;;; pdf-preview.el --- Shared PDF viewer helpers -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Viewer-agnostic helpers for opening a compiled PDF, shared by document
;; modules (`latex-config.el', `typst-config.el', ...).  Factors out the two
;; concerns that were otherwise duplicated per mode:
;;
;;   - launching Skim on a PDF and reverting an already-open copy first, so a
;;     recompiled PDF refreshes even when Skim's "auto-update" is off
;;     (`pdf-preview-skim-revert' / `pdf-preview-skim-open');
;;   - choosing between Skim (external, macOS), pdf-tools (in-Emacs, GUI), and
;;     the OS default handler, driven by `pdf-preview-viewer'.
;;
;; This module owns *plain* preview — "open this PDF".  SyncTeX forward/inverse
;; search stays in `latex-config.el', since it is AUCTeX-specific and has no
;; analogue in the other document modes.

;;; Code:

(defgroup pdf-preview nil
  "Shared PDF viewer selection for document modes."
  :group 'text)

(defcustom pdf-preview-viewer 'skim
  "Which viewer `pdf-preview-open' uses.
Choices:
  `auto'       – pdf-tools in GUI frames, Skim in TTY frames (macOS),
                 OS default elsewhere; decided per call so it works when
                 GUI and TTY frames coexist on the same daemon.
  `skim'       – external macOS app (falls back to the OS default handler
                 off macOS).
  `pdf-tools'  – in-Emacs viewer (requires a GUI frame).
  `browse-url' – OS default handler for the file."
  :type '(choice (const :tag "Auto (GUI → pdf-tools, TTY → Skim)" auto)
                 (const :tag "Skim (macOS)"                       skim)
                 (const :tag "pdf-tools (in-Emacs, GUI only)"     pdf-tools)
                 (const :tag "OS default handler"                 browse-url))
  :group 'pdf-preview)

(defun pdf-preview-skim-revert (pdf-file)
  "Tell Skim to revert its open copy of PDF-FILE, if any (macOS only).
No-op off macOS, when PDF-FILE is not a string, or when Skim does not have
it open.  Safe to call before a jump/open so a recompiled PDF refreshes even
with Skim's \"Check for file changes\" disabled."
  (when (and (eq system-type 'darwin) (stringp pdf-file))
    (call-process "osascript" nil 0 nil
                  "-e"
                  (format "tell application \"Skim\" \
to revert (documents whose path is \"%s\")"
                          (expand-file-name pdf-file)))))

(defun pdf-preview-skim-open (pdf-file)
  "Open PDF-FILE in Skim (macOS), reverting an already-open copy first.
Off macOS this falls back to `browse-url'.  Skim is left in the background
\(the `open -g' flag)."
  (if (eq system-type 'darwin)
      (progn
        (pdf-preview-skim-revert pdf-file)
        (call-process "open" nil 0 nil "-g" "-a" "Skim"
                      (expand-file-name pdf-file)))
    (browse-url pdf-file)))

(defun pdf-preview--pdf-tools-open (pdf-file)
  "Display PDF-FILE in an Emacs `pdf-view' buffer, reverting if already open."
  (let ((buf (find-buffer-visiting pdf-file)))
    (if buf
        (with-current-buffer buf
          (revert-buffer :ignore-auto :noconfirm :preserve-modes))
      (setq buf (find-file-noselect pdf-file)))
    (display-buffer buf)))

;;;###autoload
(defun pdf-preview-open (pdf-file)
  "Open PDF-FILE in the viewer selected by `pdf-preview-viewer'.
Signals a `user-error' if PDF-FILE does not exist.  Suitable as the value
of e.g. `typst-ts-preview-function'."
  (unless (and (stringp pdf-file) (file-exists-p pdf-file))
    (user-error "PDF not found: %s" pdf-file))
  (pcase pdf-preview-viewer
    ('skim       (pdf-preview-skim-open pdf-file))
    ('pdf-tools  (pdf-preview--pdf-tools-open pdf-file))
    ('browse-url (browse-url pdf-file))
    ('auto       (cond
                  ((display-graphic-p)      (pdf-preview--pdf-tools-open pdf-file))
                  ((eq system-type 'darwin) (pdf-preview-skim-open pdf-file))
                  (t                        (browse-url pdf-file))))
    (_ (browse-url pdf-file))))

(provide 'pdf-preview)
;;; pdf-preview.el ends here
