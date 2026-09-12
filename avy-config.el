;;; avy-config.el --- Label-based jumping to visible text -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Jump anywhere on screen by typing a short label, in the style of
;; tmux-thumbs / Vimium: press the key, every candidate sprouts a home-row
;; label, type it, point is there.  No search prompt, no narrowing step.
;;
;; Two entry points are bound:
;;
;;   M-j  `avy-goto-word-0'      label EVERY word in the visible windows at
;;                               once.  Nothing is typed first; this is the
;;                               tmux-thumbs gesture.
;;   M-J  `avy-goto-char-timer'  type one or more characters, pause briefly,
;;                               then labels appear on the matches.  Use this
;;                               when the screen is dense enough that
;;                               `avy-goto-word-0' needs two-character labels.
;;
;; M-j is chosen because it is a single chord that survives in a TTY frame
;; (Super and C-; / C-. do not), and because its global binding,
;; `default-indent-new-line', is also on C-M-j -- so nothing is lost.
;;
;; Beyond jumping, avy can ACT on a target without moving point: at the
;; "select a label" prompt, press a dispatch key first, then the label.
;; From the default `avy-dispatch-alist':
;;
;;   n  copy target        y  yank target here     t  teleport target here
;;   x  kill target, move  X  kill target, stay    m  mark target
;;   Y  yank target line   z  zap to target        i  ispell target
;;
;; So `M-j n <label>' copies a distant word to the kill ring while leaving
;; point where it is -- the "hint it and it lands in the clipboard" half of
;; tmux-thumbs.

;;; Code:

(use-package avy
  :straight t
  :bind (("M-j" . avy-goto-word-0)
         ("M-J" . avy-goto-char-timer))
  :custom
  ;; Home row only.  Labels are drawn from this list in order, so the nearest
  ;; candidates get the strongest fingers.  Nine keys means up to 9 targets get
  ;; a one-character label and the rest get two -- which is the whole screen.
  (avy-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l))
  ;; Label every visible window, not just the selected one: this config runs
  ;; tmux-style multi-window frames (see windows-config.el), and jumping
  ;; across a split is most of the value.
  (avy-all-windows t)
  ;; ...but keep C-u M-j meaning "this window only".
  (avy-all-windows-alt nil)
  ;; Overlay the label on top of the target instead of shifting text right,
  ;; so nothing reflows -- important in buffers whose alignment matters
  ;; (org tables, markdown tables, code).
  (avy-style 'at-full)
  ;; Case-insensitive matching for `avy-goto-char-timer'.
  (avy-case-fold-search t)
  ;; How long `avy-goto-char-timer' waits after the last keystroke before it
  ;; stops collecting input and shows the labels.
  (avy-timeout-seconds 0.4)
  ;; With exactly one candidate there is nothing to disambiguate: go.
  (avy-single-candidate-jump t))

(provide 'avy-config)

;;; avy-config.el ends here
