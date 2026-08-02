;;; latex-to-svg-config.el --- Configure the latex-to-svg library stack -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Registers the local-checkout straight recipes for the `latex-to-svg' stack
;; and configures the engine:
;;
;;   `latex-to-svg-backend'  — the rendering engine (LaTeX -> SVG, content-
;;                             addressed cache, tinted/scaled at display).  A
;;                             library shared by `agent-shell-math-renderer' and
;;                             the mode adaptors below.
;;   `latex-to-svg-frontend' — the shared preview core (detection, overlays,
;;                             numbering, `\ref'/`\eqref', …) that the per-mode
;;                             adaptors (`latex-to-svg-for-markdown',
;;                             `latex-to-svg-for-org') build on.  Lives in the
;;                             `latex-to-svg' repo alongside the adaptors.
;;
;; Engine settings are global and belong here.  This module must load BEFORE
;; the front-ends (see init.el) so straight can resolve their `Package-Requires'
;; from the local checkouts; it is the sole owner of these two recipes.

;;; Code:

(use-package latex-to-svg-backend
  :straight (latex-to-svg-backend
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg-backend")
  :defer t
  :custom
  ;; Equation size relative to the surrounding buffer font.  1.0 = match; a bit
  ;; above 1 makes both inline and display math slightly larger than the text.
  (latex-to-svg-backend-font-scale 1.0)
  ;; Daemon / mixed TTY+GUI: compile even when a non-graphic frame is selected,
  ;; so equations are ready as soon as a GUI frame views the buffer.
  (latex-to-svg-backend-render-on-non-graphic t)
  ;; Extra LaTeX packages available in *every* equation (all front-ends).
  ;; Folded into the content hash, so editing it invalidates stale cached SVGs.
  (latex-to-svg-backend-appended-preamble
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

;; Shared preview core for the mode adaptors.  Registered here (not built until
;; an adaptor requires it) so straight can resolve each adaptor's dependency on
;; it from the local `latex-to-svg' checkout.
(use-package latex-to-svg-frontend
  :straight (latex-to-svg-frontend
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg"
             :files ("latex-to-svg-frontend.el"))
  :defer t)

(provide 'latex-to-svg-config)
;;; latex-to-svg-config.el ends here
