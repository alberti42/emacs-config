;;; diff-review-config.el --- Pull-request style review of git diffs -*- lexical-binding: t; -*-

;;; Commentary:

;; `diff-review' (https://github.com/xiaoxinghu/diff-review) reviews a git
;; diff the way a pull request page does: an overview of the changed files,
;; each file opened in its own major mode with the removed lines shown inline,
;; viewed marks and comment threads kept in a JSON file under the common
;; `.git' directory.  Entry points are `diff-review-branch',
;; `diff-review-find-file' and, from a Magit buffer, `diff-review-magit-commits'
;; (`d v' in the diff menu).  In a reviewed file the commands sit under
;; `C-c _'.

;;; Code:

(use-package diff-review
  :straight (diff-review :type git :host github :repo "xiaoxinghu/diff-review")
  :init
  ;; Add the worktree branches to magit-status and `d v' to magit's diff menu.
  ;; The mode's autoload loads the package, so it stays out of startup until
  ;; Magit loads.
  (with-eval-after-load 'magit
    (diff-review-magit-mode)))

(provide 'diff-review-config)
;;; diff-review-config.el ends here
