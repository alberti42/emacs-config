;;; gnus-servers.el --- The servers Gnus reads from -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Which servers this Emacs contacts, kept apart from `gnus-config.el' so
;; that the settings and the accounts can be moved and reasoned about
;; separately.  Which groups are subscribed on them is in neither file:
;; Gnus keeps that in `newsrc.eld'.
;;
;; `news.yhetil.org' mirrors the GNU mailing lists as newsgroups over
;; NNTP, with no account and no password.  Two to start with:
;;
;;   yhetil.emacs.orgmode   emacs-orgmode@gnu.org
;;   yhetil.emacs.bugs      bug-gnu-emacs@gnu.org, the debbugs traffic
;;
;; They are read-only: the server answers "post via email", so a reply
;; leaves as mail through `smtpmail' -- `S W' in the summary buffer, not
;; `F'.
;;

;;; Code:

;; No primary server.  Every server is a secondary one, so adding an
;; account later is one more entry rather than a rearrangement.
(setq gnus-select-method '(nnnil ""))

(setq gnus-secondary-select-methods
      ;; Plain NNTP on 119.  The host offers no TLS port.
      '((nntp "yhetil"
              (nntp-address "news.yhetil.org")
              (nntp-port-number 119))))

(provide 'gnus-servers)
;;; gnus-servers.el ends here
