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
        '(("https://rss.arxiv.org/rss/quant-ph" arxiv quant-ph)))
  :config
  (add-hook 'elfeed-new-entry-hook #'elfeed-config--tag-arxiv-announce-type))

(defun elfeed-config--tag-arxiv-announce-type (entry)
  "Tag ENTRY with its arXiv announcement type.
An arXiv RSS listing mixes four kinds of item, and each one names its
kind at the start of its description, as in \"Announce Type: new\":
`new' (submitted to the category), `cross' (cross-listed from another
one), `replace' and `replace-cross' (a new version of an older paper).
The type becomes a tag, so a filter such as `+new' or `-replace' picks
them apart.  Entries of feeds not served by rss.arxiv.org are left
alone."
  (when (string-prefix-p "https://rss.arxiv.org/" (elfeed-entry-feed-id entry))
    (let ((content (elfeed-deref (elfeed-entry-content entry))))
      (when (and content
                 (string-match "Announce Type: \\([a-z-]+\\)" content))
        (elfeed-tag entry (intern (match-string 1 content)))))))

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
