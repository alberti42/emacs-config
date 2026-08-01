;;; latex-to-svg-config.el --- Configure the latex-to-svg rendering engine -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Single place that registers and configures the `latex-to-svg' rendering
;; engine (LaTeX -> SVG, content-addressed on-disk cache, color- and
;; size-independent, tinted/scaled at display time).
;;
;; `latex-to-svg' is a *library* shared by multiple front-ends —
;; `agent-shell-math-renderer' (math in agent-shell) and `org-latex-to-svg'
;; (Org math preview).  Its settings are therefore global and belong here, not
;; inside any one front-end's config (which is where `font-scale' etc. used to
;; live, misleadingly, in `agent-shell-setup.el').
;;
;; Load order: this module must load BEFORE those front-ends so straight can
;; resolve their `latex-to-svg' `Package-Requires' dependency from the local
;; checkout (see init.el, where it precedes `org-config' and `agent-shell-setup').
;; It is the sole owner of the local-checkout straight recipe.

;;; Code:

(use-package latex-to-svg
  :straight (latex-to-svg
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg")
  :defer t
  :custom
  ;; Equation size relative to the surrounding buffer font.  1.0 = match; a bit
  ;; above 1 makes both inline and display math slightly larger than the text.
  (latex-to-svg-font-scale 1.1)
  ;; Daemon / mixed TTY+GUI: compile even when a non-graphic frame is selected,
  ;; so equations are ready as soon as a GUI frame views the buffer.
  (latex-to-svg-render-on-non-graphic t)
  ;; Extra LaTeX packages available in *every* equation (all front-ends).
  ;; Folded into the content hash, so editing it invalidates stale cached SVGs.
  (latex-to-svg-appended-preamble
   "\\usepackage{physics}
\\usepackage[only,llbracket,rrbracket]{stmaryrd}
\\usepackage{siunitx}
\\usepackage{mathtools}
\\sisetup{
detect-weight=true,
exponent-product={\\times},
output-decimal-marker={.},
print-unity-mantissa=false,
}"))

(provide 'latex-to-svg-config)
;;; latex-to-svg-config.el ends here
