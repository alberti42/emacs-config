;;; elfeed-config.el --- Elfeed feed reader -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Elfeed fetches RSS and Atom feeds over HTTP itself, with no server in
;; between: the same arXiv listing that `gnus-servers.el' reads through
;; news.gwene.org is fetched here from rss.arxiv.org directly.
;;
;;   https://rss.arxiv.org/rss/quant-ph
;;
;; To read: `M-x elfeed', then `G' to fetch every feed, `RET' to open an
;; entry, `b' to open its link in the browser, `s' to edit the search
;; filter.  The default filter, `@6-months-ago +unread', shows only unread
;; entries, so an entry drops out of the list once it is opened.
;;

;;; Code:

(use-package elfeed
  :straight t
  :defer t
  :commands (elfeed)
  :init
  ;; The database holds the read marks and tags, which nothing rebuilds,
  ;; so it is state.  The package's default is `~/.elfeed'; naming it as
  ;; LEGACY moves an earlier run's database the first time.
  (setq elfeed-db-directory
        (emacs-config-state-file "elfeed" (expand-file-name "~/.elfeed")))
  (setq elfeed-feeds
        '(("https://rss.arxiv.org/rss/quant-ph" arxiv quant-ph))))

;;; -- latex-to-svg-for-elfeed: render math in elfeed articles -----------------

(use-package latex-to-svg-for-elfeed
  :straight (latex-to-svg-for-elfeed
             :type git
             :inherit nil
             :branch "develop"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg"
             :files ("latex-to-svg-for-elfeed.el"))
  :hook (elfeed-show-mode . latex-to-svg-for-elfeed-mode))

(provide 'elfeed-config)
;;; elfeed-config.el ends here
