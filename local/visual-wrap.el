;;; visual-wrap.el --- Smart line-wrapping with wrap-prefix -*- lexical-binding: t -*-

;; Copyright (C) 2011-2021, 2024-2026 Free Software Foundation, Inc.

;; Author: Stephen Berman <stephen.berman@gmx.net>
;;         Stefan Monnier <monnier@iro.umontreal.ca>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: convenience
;; Package: emacs

;; This file is part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Local copy of `visual-wrap.el' carrying Stefan Monnier's proposed
;; redesign (emacs-devel discussion, 2026-05):
;;
;;   * `visual-wrap--content-prefix' returns the first-line prefix's
;;     natural pixel width instead of a column count.
;;   * `visual-wrap--apply-to-line' no longer installs a `min-width'
;;     display property on the first line.  The continuation
;;     `wrap-prefix' uses pixel-form `:align-to', i.e. `(space :align-to
;;     (PIX))', which aligns continuation lines to the same pixel
;;     column as the end of the first-line prefix without touching
;;     line 1 itself.
;;
;; This avoids reserving column-space for invisible prefix characters
;; (e.g. hidden `###' markers in `markdown-ts-mode' with
;; `markdown-ts-hide-markup' enabled).  Such characters render at 0
;; pixels on line 1 already; the old code's `min-width' computation
;; padded them back out using `string-width', which doesn't consult
;; `buffer-invisibility-spec'.

;;; Code:

(defcustom visual-wrap-extra-indent 0
  "Number of extra spaces to indent in `visual-wrap-prefix-mode'.

`visual-wrap-prefix-mode' indents the visual lines to the level
of the actual line plus `visual-wrap-extra-indent'.  A negative
value will do a relative de-indent.

Examples:

actual indent = 2
extra indent = -1

  Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed
 do eiusmod tempor incididunt ut labore et dolore magna
 aliqua. Ut enim ad minim veniam, quis nostrud exercitation
 ullamco laboris nisi ut aliquip ex ea commodo consequat.

actual indent = 2
extra indent = 2

  Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed
    do eiusmod tempor incididunt ut labore et dolore magna
    aliqua. Ut enim ad minim veniam, quis nostrud exercitation
    ullamco laboris nisi ut aliquip ex ea commodo consequat."
  :type 'integer
  :safe 'integerp
  :version "30.1"
  :group 'visual-line)

(defun visual-wrap--face-extend-p (face)
  ;; Before Emacs 27, faces always extended beyond EOL, so we check
  ;; for a non-default background instead.
  (cond
   ((listp face)
    (plist-get face (if (fboundp 'face-extend-p) :extend :background)))
   ((symbolp face)
    (if (fboundp 'face-extend-p)
        (face-extend-p face nil t)
      (face-background face nil t)))))

(defvar visual-wrap--safe-display-specs
  '(space-width min-width height raise)
  "A list of display specs that don't interfere with wrap prefixes.
A \"safe\" display spec is one that won't interfere with the additional
text properties that `visual-wrap-prefix-mode' uses.

Specs that replace the text are unsafe, since they generally determine
the range of text to replace via `eq'.  If `visual-wrap-prefix-mode'
were to add text properties to some subset of this range, it would
violate this assumption.")

(defun visual-wrap--display-property-safe-p (display)
  "Return non-nil if the display property DISPLAY is \"safe\".
A \"safe\" display property is one where all the display specs are
members of `visual-wrap--safe-display-specs' (which see)."
  ;; The display property could be a single display spec; if so, wrap it
  ;; in a list so we can iterate over it in our loop below.
  (when (and (consp display) (not (consp (car display))))
    (setq display (list display)))
  ;; Loop over all the display specs to check if they're safe.  Assume
  ;; any display property other than a vector or list (e.g. a string) is
  ;; unsafe.
  (when (or (vectorp display) (listp display))
    (not (catch 'unsafe
           (mapc (lambda (spec)
                   (unless (member (car-safe spec)
                                   visual-wrap--safe-display-specs)
                     (throw 'unsafe t)))
                 display)))))

(defun visual-wrap--prefix-face (fcp _beg end)
  ;; If the fill-context-prefix already specifies a face, just use that.
  (cond ((get-text-property 0 'face fcp))
        ;; Else, if the last character is a newline and has a face
        ;; that extends beyond EOL, assume that this face spans the
        ;; whole line and apply it to the prefix to preserve the
        ;; "block" visual effect.
        ;;
        ;; NB: the face might not actually span the whole line: see
        ;; for example removed lines in diff-mode, where the first
        ;; character has the diff-indicator-removed face, while the
        ;; rest of the line has the diff-removed face.
        ((= (char-before end) ?\n)
         (let ((eol-face (get-text-property (1- end) 'face)))
           ;; `eol-face' can be a face, a "face value"
           ;; (plist of face properties) or a list of one of those.
           (if (or (not (consp eol-face)) (keywordp (car eol-face)))
               ;; A single face.
               (if (visual-wrap--face-extend-p eol-face) eol-face)
             ;; A list of faces.  Keep the ones that extend beyond EOL.
             (delq nil (mapcar (lambda (f)
                                 (if (visual-wrap--face-extend-p f) f))
                               eol-face)))))))

(defun visual-wrap--adjust-prefix (prefix)
  "Adjust PREFIX with `visual-wrap-extra-indent'.
If PREFIX is a number it is treated as a pixel width and
`visual-wrap-extra-indent' is converted from canonical-char columns
to pixels before being added."
  (if (numberp prefix)
      (+ (* visual-wrap-extra-indent
            (string-pixel-width " " (current-buffer)))
         prefix)
    (let ((prefix-len (string-width prefix)))
      (cond
       ((= 0 visual-wrap-extra-indent)
        prefix)
       ((< 0 visual-wrap-extra-indent)
        (concat prefix (make-string visual-wrap-extra-indent ?\s)))
       ((< 0 (+ visual-wrap-extra-indent prefix-len))
        (substring prefix
                   0 (+ visual-wrap-extra-indent prefix-len)))
       (t
        "")))))

(defun visual-wrap--apply-to-line ()
  "Apply visual-wrapping properties to the logical line starting at point.

Per Stefan Monnier's proposed redesign (emacs-devel, 2026-05): when
`visual-wrap--content-prefix' returns a number (pixel width of the
first-line prefix), do NOT install a `min-width' display property on
line 1.  Instead, set the continuation `wrap-prefix' to a pixel-form
`:align-to', so wrapped lines line up with the end of the first-line
prefix without forcing line 1 to a wider rendering."
  (when-let* ((first-line-prefix (fill-match-adaptive-prefix))
              (next-line-prefix (visual-wrap--content-prefix
                                 first-line-prefix (point))))
    (setq next-line-prefix (visual-wrap--adjust-prefix next-line-prefix))
    (put-text-property
     (point) (pos-eol) 'wrap-prefix
     (if (numberp next-line-prefix)
         ;; Pixel-form `:align-to': the list `(PIX)' tells the display
         ;; engine that PIX is in pixels (not canonical-char columns).
         `(space :align-to (,next-line-prefix))
       next-line-prefix))))

(defun visual-wrap--content-prefix (prefix position)
  "Get the next-line prefix for the specified first-line PREFIX.
POSITION is the position in the buffer where PREFIX is located.

This returns a string prefix to use for subsequent lines; a number,
indicating the pixel width to use for whitespace alignment; or nil, if
PREFIX was empty.

Per Stefan Monnier's proposed redesign (emacs-devel, 2026-05): the
whitespace width returned here is the natural pixel width of PREFIX
itself.  Previously this function returned a column count derived from
`(max (string-width prefix) (ceiling pixel-width avg-space-width))',
which forced line 1's prefix to a rounded column width via a
`min-width' display property.  That rounding reserved space for
invisible characters (which render at 0 pixels but still have a
positive `string-width').  Returning the natural pixel width here, and
using it directly as the `:align-to' target, makes the continuation
whitespace match what line 1 actually occupies on screen."
  (cond
   ((string= prefix "")
    nil)
   ((or (and adaptive-fill-first-line-regexp
             (string-match adaptive-fill-first-line-regexp prefix))
        (and comment-start-skip
             (string-match comment-start-skip prefix)))
    ;; If we want to repeat the first-line prefix on subsequent lines,
    ;; return its string value.  However, we remove any `wrap-prefix'
    ;; property that might have been added earlier.  Otherwise, we end
    ;; up with a string containing a `wrap-prefix' string containing a
    ;; `wrap-prefix' string...
    (remove-text-properties 0 (length prefix) '(wrap-prefix) prefix)
    prefix)
   (t
    ;; Whitespace continuation: return the natural pixel width of the
    ;; first-line prefix.  No `min-width' to install on line 1.
    (add-display-text-property 0 (length prefix) 'min-width nil prefix)
    (string-pixel-width prefix (current-buffer)))))

(defun visual-wrap-fill-context-prefix (beg end)
  "Compute visual wrap prefix from text between BEG and END.
This is like `fill-context-prefix', but with prefix length adjusted
by `visual-wrap-extra-indent'."
  (declare (obsolete nil "31.1"))
  (let* ((fcp
          ;; `fill-context-prefix' ignores prefixes that look like
          ;; paragraph starts, in order to avoid inadvertently
          ;; creating a new paragraph while filling, but here we're
          ;; only dealing with single-line "paragraphs" and we don't
          ;; actually modify the buffer, so this restriction doesn't
          ;; make much sense (and is positively harmful in
          ;; taskpaper-mode where paragraph-start matches everything).
          (or (let ((paragraph-start regexp-unmatchable))
                (fill-context-prefix beg end))
              ;; Note: fill-context-prefix may return nil; See:
              ;; http://article.gmane.org/gmane.emacs.devel/156285
              ""))
         (prefix (visual-wrap--adjust-prefix fcp))
         (face (visual-wrap--prefix-face fcp beg end)))
    (if face
        (propertize prefix 'face face)
      prefix)))

(defun visual-wrap--remove-properties (start end)
  "Remove visual wrapping text properties from START to END."
  ;; Remove `min-width' from any prefixes we detected.
  (remove-display-text-property start end 'min-width)
  ;; Remove `wrap-prefix' related properties from any lines with
  ;; prefixes we detected.
  (remove-text-properties start end '(wrap-prefix nil)))

(defun visual-wrap-prefix-function (beg end)
  "Indent the region between BEG and END with visual filling."
  ;; Any change at the beginning of a line might change its wrap
  ;; prefix, which affects the whole line.  So we need to "round-up"
  ;; `end' to the nearest end of line.  We do the same with `beg'
  ;; although it's probably not needed.
  (goto-char end)
  (unless (bolp) (forward-line 1))
  (setq end (point))
  (goto-char beg)
  (forward-line 0)
  (setq beg (point))
  (visual-wrap--remove-properties beg end)
  (while (< (point) end)
    ;; Check if the display property at the end of this line is "safe".
    (if (visual-wrap--display-property-safe-p
         (get-char-property (pos-eol) 'display))
        ;; If so, we can apply our visual wrapping properties to this
        ;; line and continue to the next line.
        (progn
          (visual-wrap--apply-to-line)
          (forward-line))
      ;; Otherwise, skip ahead until the end of any unsafe display
      ;; properties.  NOTE: We do this out of an abundance of caution to
      ;; be as certain as possible that we're not interfering with the
      ;; display engine.  If this results in cases where we fail to add
      ;; wrapping properties when we should, then we should remove the
      ;; `while' loop below.  Without that loop, this should be the same
      ;; logic `handle_single_display_spec' in xdisp.c uses for
      ;; determining what text to replace.  See bug#73600.
      (goto-char (next-single-char-property-change (pos-eol) 'display))
      (while (not (visual-wrap--display-property-safe-p
                   (get-char-property (point) 'display)))
        (goto-char (next-single-char-property-change (point) 'display)))
      (unless (bolp) (forward-line 1))))
  `(jit-lock-bounds ,beg . ,end))

;;;###autoload
(define-minor-mode visual-wrap-prefix-mode
  "Display continuation lines with prefixes from surrounding context.
To enable this minor mode across all buffers, enable
`global-visual-wrap-prefix-mode'."
  :lighter ""
  :group 'visual-line
  (if visual-wrap-prefix-mode
      (progn
        ;; HACK ATTACK!  We want to run after font-lock (so our
        ;; wrap-prefix includes the faces applied by font-lock), but
        ;; jit-lock-register doesn't accept an `append' argument, so
        ;; we add ourselves beforehand, to make sure we're at the end
        ;; of the hook (bug#15155).
        (add-hook 'jit-lock-functions
                  #'visual-wrap-prefix-function 'append t)
        (jit-lock-register #'visual-wrap-prefix-function))
    (jit-lock-unregister #'visual-wrap-prefix-function)
    (with-silent-modifications
      (save-restriction
        (widen)
        (visual-wrap--remove-properties (point-min) (point-max))))))

;;;###autoload
(define-globalized-minor-mode global-visual-wrap-prefix-mode
  visual-wrap-prefix-mode visual-wrap-prefix-mode
  :init-value nil
  :group 'visual-line)

(provide 'visual-wrap)
;;; visual-wrap.el ends here
