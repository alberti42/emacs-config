;;; avy-config.el --- Label-based jumping to visible text -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Jump anywhere on screen by typing a short label, in the style of
;; tmux-thumbs / Vimium: press the key, every candidate sprouts a home-row
;; label, type it, point is there.  No search prompt, no narrowing step.
;;
;; Bound under the built-in goto-map (M-g), where the other "take me
;; somewhere" commands already live (M-g g goto-line, M-g c goto-char,
;; M-g n / M-g p next/previous error):
;;
;;   M-g a  `avy-goto-char-timer'  type as many characters as you like, then
;;                                 press RET; labels appear on the remaining
;;                                 matches (and with a single match left it
;;                                 jumps straight there).  The primary
;;                                 gesture: it stays usable in a dense buffer,
;;                                 where labelling every word would exhaust
;;                                 the one-character labels.  The name is
;;                                 upstream's -- there is no timer here, see
;;                                 `avy-timeout-seconds' below.
;;   M-g A  `avy-goto-word-0'      label EVERY word in the visible windows at
;;                                 once.  Nothing is typed first; this is the
;;                                 tmux-thumbs gesture, best on sparse screens.
;;   M-g l  `avy-goto-line'        label the start of every visible line.
;;
;; The goto-map is preferred over a single chord such as M-j: M-j is
;; `default-indent-new-line', which this configuration's author uses as a
;; C-j substitute, and M-g survives a TTY frame just as well.
;;
;; Beyond jumping, avy can ACT on a target without moving point: at the
;; "select a label" prompt, press a dispatch key first, then the label.
;; From the default `avy-dispatch-alist':
;;
;;   n  copy target        y  yank target here     t  teleport target here
;;   x  kill target, move  X  kill target, stay    m  mark target
;;   Y  yank target line   z  zap to target        i  ispell target
;;
;; So `M-g a n <label>' copies a distant word to the kill ring while leaving
;; point where it is -- the "hint it and it lands in the clipboard" half of
;; tmux-thumbs.

;;; Code:

(use-package avy
  :straight t
  :bind (:map goto-map
              ("A" . avy-goto-word-0)
              ("a" . avy-goto-char-timer)
              ("l" . avy-goto-line))
  :custom
  ;; Use home row (matching avy's default). Labels are assigned in
  ;; buffer-position order via a balanced tree; the balanced tree ensures that
  ;; all candidates get labels differing by at most one key in length. In
  ;; general, the label's length depends on how many matches there are.
  (avy-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l))
  ;; Do not label every visible window, just the selected one.
  (avy-all-windows t)
  ;; ...but label all windows with C-u M-g a.
  (avy-all-windows-alt t)
  ;; Overlay the label on top of the target instead of shifting text right, so
  ;; nothing reflows.
  (avy-style 'at-full)
  ;; Case-insensitive matching for `avy-goto-char-timer'.
  (avy-case-fold-search t)
  ;; No timer: type the pattern at my own pace and end it with RET.  Timer is
  ;; relevant for `avy-goto-char-timer', which stops collecting input once this
  ;; many seconds pass without a keystroke; unless nil is provided.
  (avy-timeout-seconds nil)
  ;; With exactly one candidate there is nothing to disambiguate.  Consulted by
  ;; `avy--process-1' once the pattern has been read, i.e. after RET.
  (avy-single-candidate-jump t))

(provide 'avy-config)

;;; avy-config.el ends here
