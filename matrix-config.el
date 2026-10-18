;;; matrix-config.el --- Matrix client (elneo) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; elneo is a Matrix client with end-to-end encryption.  The Matrix
;; protocol work (connection, sync, encryption) runs in a separate
;; `elneo-server' process per account, built on matrix-rust-sdk; Emacs
;; draws the room bar and the room buffers.
;;
;; The first `M-x elneo-start' (or `M-x elneo-add-account') offers to
;; download the `elneo-server' release binary for this machine into
;; elneo's data directory, `~/Library/Application Support/fi.aard.elneo/'
;; on macOS.  That directory also holds each account's access token and
;; encryption keys, unencrypted (elneo issue #1).
;;
;; `M-x elneo-add-account' logs an account in, `M-x elneo-start' brings
;; every registered account online and shows the room bar.
;;
;; `elneo-alert.el' is left out of the build: it requires `alert.el',
;; which this configuration does not install.
;;

;;; Code:

(use-package elneo
  :straight (elneo :type git :host github :repo "aard-fi/elneo"
                   :files ("lisp/*.el" (:exclude "lisp/elneo-alert.el")))
  :defer t
  :init
  ;; Both defaults name `user-emacs-directory', a symlink into this
  ;; worktree.  The account registry (profile names, homeservers, no
  ;; secrets) is what `elneo-add-account' produced, so it is state.
  (setq elneo-account-file (emacs-config-state-file "elneo-accounts.el"))
  ;; One log file for every profile's daemon, where the default is one
  ;; file per profile.
  (setq elneo-server-logfile (emacs-config-state-file "elneo-server.log"))
  :config
  (advice-add 'elneo-add-account :around #'matrix-config--forget-password))

(defun matrix-config--forget-password (fn &rest args)
  "Call FN with ARGS, then drop its entries from `command-history'.
`elneo-add-account' reads the password in its interactive form, and
`call-interactively' records a command run with \\[execute-extended-command]
in `command-history' together with its argument values, which savehist
then writes to disk.  The entries are removed whether or not the login
succeeds."
  (unwind-protect
      (apply fn args)
    (setq command-history
          (seq-remove (lambda (entry) (eq (car-safe entry) 'elneo-add-account))
                      command-history))))

(provide 'matrix-config)
;;; matrix-config.el ends here
