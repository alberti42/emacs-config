;;; debug-markdown-ts-mode.el --- Test suite for markdown-ts-mode bugs -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive test suite for bugs in `markdown-ts-mode'.  Each test
;; creates a dedicated buffer and configures specific conditions so the
;; reviewer can verify the expected visual outcome.
;;
;; Tests are callable from "emacs -Q" against a build that has
;; `markdown-ts-mode' on `load-path' (Emacs 31+ bundles it; against a
;; shadowed copy, point `-L' at the directory containing the patched
;; file):
;;
;;   emacs -Q -L /path/to/dir-with-markdown-ts-mode/ \
;;             --load /path/to/debug-markdown-ts-mode.el \
;;             --eval "(markdown-ts-test-NNN)"
;;
;; Replace NNN with the test number (currently only 001).  Tests can
;; also be run interactively via M-x.
;;
;; The tree-sitter grammar for Markdown must be installed; run
;; M-x treesit-install-language-grammar markdown if it is not.
;;
;; All tests load the built-in `modus-operandi' theme so the
;; `markdown-ts-thematic-break' face (which inherits from `shadow' and
;; has `:extend t') is visually distinct, making the wrap bug obvious.

;;; Code:

(require 'markdown-ts-mode)

;;; Helpers

(defun markdown-ts-test--load-theme ()
  "Load `modus-operandi' without prompting."
  (load-theme 'modus-operandi t))

(defun markdown-ts-test--title (title)
  "Return TITLE formatted as a header banner."
  (format "%s\n\n" title))

(defun markdown-ts-test--force-hide-markup ()
  "Force `markdown-ts-hide-markup' on in the current buffer.
Sets the variable buffer-locally and replicates the side-effects of
`markdown-ts-toggle-hide-markup' (invisibility spec + font-lock
refresh) without relying on its flip semantics, so the test starts
from a known state regardless of the user's global `:custom' value."
  (setq-local markdown-ts-hide-markup t)
  (add-to-invisibility-spec 'markdown-ts--markup)
  (font-lock-flush)
  (font-lock-ensure))

;;; Test 001 — Thematic break overflows visible text area under
;;; soft-wrap with a right-margin layout.

(defun markdown-ts-test-001 ()
  "Thematic break wraps incorrectly with soft-wrap + right margin.
See test buffer for full explanation."
  (interactive)
  (markdown-ts-test--load-theme)
  (let ((buf (get-buffer-create "*markdown-ts-test-001*"))
        (target-width 60))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (markdown-ts-test--title
               "markdown-ts-test-001: thematic break overflows visible text area"))
      (insert "\
This test demonstrates a bug in `markdown-ts--fontify-thematic-break'.

When `markdown-ts-hide-markup' is on and the `markdown-ts-thematic-break'
face has `:extend' non-nil (the default, via `shadow'), the function
replaces the thematic-break node with a `display' property containing
N copies of the thematic-break character followed by a newline, where

  N = (- (window-body-width) col)

When the window has a non-zero right margin --- which is how soft-wrap
focus modes such as olivetti, visual-fill-column, writeroom-mode, and
darkroom constrain the visible text area --- the rendered line
overflows and wraps.  A short stub of horizontal bars appears on a
second visual line, breaking the visual flow.

The width also varies with the frame width in a way that does not
simply track the writable text area, suggesting the math does not
account for the actual area available to the row (margins, fringes,
wrap/line-prefix).

Setup applied to this buffer:

  - `markdown-ts-mode' enabled.
  - `markdown-ts-hide-markup' on.
  - `visual-line-mode' on.
  - The selected window has a right margin reserved so the text area
    is constrained to ~60 columns.

Expected (correct fix): the rendered horizontal-bar run fills exactly
the visible text area in one row.  No second visual line appears.

Actual (bug): the rendered run is wider than the visible text area
and wraps; a stub second visual line of horizontal bars appears.

Resize the frame width to confirm: the stub width changes as the
frame width changes, instead of always exactly filling the text area.

---

Paragraph above the thematic break.

---

Paragraph below the thematic break.
")
      (markdown-ts-mode)
      (visual-line-mode 1))
    (switch-to-buffer buf)
    (let ((right (max 0 (- (window-total-width) target-width))))
      (set-window-margins (selected-window) 0 right))
    (with-current-buffer buf
      (markdown-ts-test--force-hide-markup)
      (read-only-mode 1)
      (goto-char (point-min)))))

(provide 'debug-markdown-ts-mode)
;;; debug-markdown-ts-mode.el ends here
