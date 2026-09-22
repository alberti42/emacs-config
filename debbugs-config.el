;;; debbugs-config.el --- GNU bug tracker client -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `debbugs' talks to the tracker at debbugs.gnu.org over its SOAP
;; interface, which is a different thing from the bug mail carried by
;; `yhetil.emacs.bugs' (see `gnus-servers.el').  A report here has a
;; package, a severity, tags and an open or closed state; it can be
;; queried on any of those, and it can be changed -- closing, tagging or
;; reassigning one sends the control message to control@debbugs.gnu.org.
;;
;; `M-x debbugs-gnu' asks for severities and packages and lists what
;; matches, `M-x debbugs-gnu-bugs' follows given bug numbers, `M-x
;; debbugs-gnu-my-open-bugs' the ones submitted from your address, `M-x
;; debbugs-gnu-search' searches, `M-x debbugs-gnu-patches' lists the
;; reports tagged `patch'.  Opening a report shows its thread in a Gnus
;; ephemeral group, which is what `debbugs-gnu-mail-backend' selects and
;; is already its default.
;;
;; Emacs itself can fetch one report without this package:
;; `M-x gnus-read-ephemeral-emacs-bug-group' takes bug numbers and opens
;; the messages.  What it cannot do is any of the state above.
;;

;;; Code:

(use-package debbugs
  :straight t
  :defer t
  :commands (debbugs-gnu
             debbugs-gnu-bugs
             debbugs-gnu-my-open-bugs
             debbugs-gnu-search
             debbugs-gnu-patches
             debbugs-gnu-tagged)
  :init
  ;; The tags and marks put on reports from here, and nothing else --
  ;; `debbugs-gnu-local-tags' and `debbugs-gnu-local-marks'.  Nothing
  ;; rebuilds them, so they are state; the package's own default is a
  ;; defvar naming `user-emacs-directory', a symlink into this worktree.
  (setq debbugs-gnu-persistency-file (emacs-config-state-file "debbugs")))

(provide 'debbugs-config)
;;; debbugs-config.el ends here
