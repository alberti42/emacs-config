;;; osx-dictionary-config.el --- Look up words via macOS Dictionary.app -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; https://github.com/alberti42/fork-osx-dictionary.el (branch dictionary-selection)
;; Fork of https://github.com/xuchunyang/osx-dictionary.el
;;
;; Shows a word's definition in an Emacs buffer by querying the
;; `DCSCopyTextDefinition' Core Services API at runtime, i.e. whatever
;; dictionaries are installed in Dictionary.app (NOAD, Oxford Dictionary of
;; English, bilingual dictionaries, ...). No dictionary data is bundled or
;; redistributed. Darwin-only; loaded from init.el only under macOS.
;;
;; The fork adds `osx-dictionary-select-dictionary', to restrict lookups to
;; one installed dictionary (or back to all active ones); the choice is
;; persisted here under `emacs-config-cache-dir' rather than the fork's own
;; default (`user-emacs-directory', which in this config is a git worktree).
;; `osx-dictionary-allowed-dictionaries' below narrows which dictionaries
;; that command offers, and in what order -- edit it freely;
;; `M-: (osx-dictionary-get-all-dictionaries)' lists every name Dictionary.app
;; reports. An entry can be just that real name, or a (REAL . DISPLAY) cons
;; when the real name is too unwieldy to show, as for the two Italian
;; dictionaries below.

;;; Code:

(use-package osx-dictionary
  :straight (osx-dictionary
             :type git
             :host github
             :repo "alberti42/fork-osx-dictionary.el"
             :local-repo "~/Programming/Others/fork-osx-dictionary.el"
             :branch "dictionary-selection")
  :commands (osx-dictionary-search-word-at-point
             osx-dictionary-search-input
             osx-dictionary-select-dictionary)
  :init
  (defvar-keymap osx-dictionary-config-map
    "d" #'osx-dictionary-search-word-at-point
    "s" #'osx-dictionary-search-input
    "S" #'osx-dictionary-select-dictionary)
  :custom
  (osx-dictionary-last-dictionary-file
   (emacs-config-cache-file "osx-dictionary-last-dictionary"))
  (osx-dictionary-allowed-dictionaries
   '("Oxford Dictionary of English"
     "Oxford Thesaurus of English"
     "Duden-Wissensnetz deutsche Sprache"
     ("Dizionario italiano da un affiliato di Oxford University Press" . "Oxford Italian Dictionary ")
     ("Oxford Paravia Il Dizionario inglese - italiano/italiano - inglese" . "Oxford Paravia Italiano/Inglese")))
  :bind-keymap ("C-c d" . osx-dictionary-config-map))

;; Vertico re-sorts every prompt's candidates by default (see
;; minibuffer-vertico.el), which would override the order set above.  Turn
;; that off for this one prompt, same as the existing `recentf-open' entry.
(with-eval-after-load 'vertico-multiform
  (add-to-list 'vertico-multiform-commands
               '(osx-dictionary-select-dictionary (vertico-sort-function . nil))))

(provide 'osx-dictionary-config)
;;; osx-dictionary-config.el ends here
