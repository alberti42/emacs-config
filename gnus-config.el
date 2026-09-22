;;; gnus-config.el --- Gnus mail and news reader -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; How Gnus behaves and where it keeps its files.  Two things are
;; deliberately elsewhere:
;;
;;   - which servers to contact: `gnus-servers.el';
;;   - which groups are subscribed: Gnus writes that to `newsrc.eld'
;;     itself, whenever a group is subscribed, entered or left.  It is
;;     state in the sense `emacs-config-core.el' means -- nothing
;;     rebuilds it -- so it goes to `emacs-config-state-dir' and never
;;     into this repo.
;;
;; To read: `M-x gnus', then `U <group> RET' to subscribe to one, `RET'
;; to open it, `L' to list every subscribed group.  The default listing
;; shows only groups holding unread articles, so a group read to the end
;; drops out of sight until something new arrives in it.
;;

;;; Code:

(defconst gnus-config-directory
  (let ((dir (file-name-as-directory (emacs-config-state-file "gnus"))))
    (make-directory dir t)
    dir)
  "Directory holding every file Gnus writes.")

(use-package gnus
  :straight nil
  :defer t
  :init
  ;; Every path is named here rather than derived.  gnus.el computes
  ;; `gnus-startup-file' from `gnus-home-directory', and
  ;; `gnus-cache-directory', `gnus-kill-files-directory' and
  ;; `gnus-article-save-directory' from `gnus-directory', each at its own
  ;; defcustom -- so setting those two moves the rest only while gnus.el
  ;; is still unloaded, and by the time this module runs it is loaded:
  ;; `org-modules' includes `ol-gnus', `ol-gnus' requires `gnus-sum', and
  ;; org-config.el is loaded well before this file.
  (setq gnus-home-directory gnus-config-directory
        gnus-directory gnus-config-directory
        gnus-cache-directory (expand-file-name "cache/" gnus-config-directory)
        gnus-agent-directory (expand-file-name "agent/" gnus-config-directory)
        gnus-kill-files-directory gnus-config-directory
        gnus-article-save-directory gnus-config-directory)
  ;; `gnus-startup-file' names the base; Gnus writes `newsrc.eld' beside
  ;; it, and that file holds the subscriptions and the read marks.  Naming
  ;; the `.eld' to `emacs-config-state-file' moves an earlier run's copy
  ;; out of ~ the first time.
  (setq gnus-startup-file
        (file-name-sans-extension
         (emacs-config-state-file "gnus/newsrc.eld"
                                  (expand-file-name "~/.newsrc.eld"))))
  ;; `.newsrc' is the plain-text format other newsreaders read.  Gnus
  ;; keeps its own `newsrc.eld' either way, and no other newsreader runs
  ;; here, so skip both halves of that file.
  (setq gnus-read-newsrc-file nil
        gnus-save-newsrc-file nil)
  ;; Ask every server for its whole group list at startup.  The default,
  ;; `some', asks only about groups already named in `newsrc.eld', so a
  ;; server nothing has been subscribed to yet stays invisible and `U'
  ;; has nothing to offer.  That default is meant for Usenet servers
  ;; carrying tens of thousands of groups; news.yhetil.org carries 20.
  (setq gnus-read-active-file t)
  ;; Show the newest 5000 articles of a group and never ask.  Two settings
  ;; are needed and they work at different points:
  ;; `gnus-newsgroup-maximum-articles' drops everything older than the
  ;; newest 5000 when the unread list is built, and `gnus-large-newsgroup'
  ;; is the count above which Gnus asks how many to fetch -- equal to the
  ;; cap, so the question never comes up.  The price is that articles
  ;; below the window are out of reach from the summary; raise or unset
  ;; the cap to read further back.
  (setq gnus-newsgroup-maximum-articles 5000
        gnus-large-newsgroup 5000)
  ;; Hand every NNTP server to the Agent, which keeps headers and articles
  ;; on disk; without it Gnus asks the server for the headers of every
  ;; unread article again on each entry.  Gnus reads this variable only
  ;; while the agent's `lib/servers' file is absent, that is the first
  ;; time the Agent runs; afterwards the covered servers are edited in the
  ;; server buffer with `J a' and `J r'.
  (setq gnus-agent-auto-agentize-methods '(nntp))
  ;; A group that turns up on a server is killed rather than parked in the
  ;; zombie list, so the group buffer lists what was asked for and nothing
  ;; else.  `U' subscribes to one by name.
  (setq gnus-subscribe-newsgroup-method 'gnus-subscribe-killed)
  :custom
  ;; Gnus takes the whole frame otherwise.
  (gnus-use-full-window nil))

(provide 'gnus-config)
;;; gnus-config.el ends here
