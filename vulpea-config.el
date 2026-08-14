;;; vulpea-config.el --- Note database over the org notes (vulpea) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; vulpea v2 is a database layer over org notes: it indexes every org node
;; that carries an `:ID:' and answers queries about them without blocking.  It
;; is standalone as of v2 — no org-roam involved.
;;
;; This file is the *configuration*: which packages to install, which vault to
;; resume, which keys to bind, and the one thing true only of this machine (how
;; the vaults' rollups reach gitlab.mpcdf.mpg.de and github.com).  Everything else — what a
;; vault is, what it may declare, what follows from opening one — is in
;; vulpea-vault/, written as a package that happens not to be published:
;; nothing in there names a machine or a directory, and it would work for
;; anyone's vault.
;;
;; `org-id' itself is not configured here at all: where `org-id-locations-file'
;; lives is an org-wide, per-machine choice and belongs with the rest of it in
;; `org-config.el'.  What this vault adds is only the part that keeps `org-id'
;; in step with vulpea's database, which is `vulpea-vault/ids.el'.
;;
;; The seam is worth keeping, and there is a one-line test for anything added
;; later: WOULD THIS BE WRONG ON ANOTHER MACHINE OR FOR ANOTHER VAULT?  Then
;; it stays here; otherwise it belongs in vulpea-vault/.
;;
;; The modules, in the order they are loaded:
;;
;;   scheme        what a vault may declare in its `.dir-locals.el'
;;   core          which vault is in use, and the settings derived from it
;;   modified-stamp, select, directories, tags, create   note-level behaviour
;;   ids           `org-id' kept in step with vulpea's database
;;   attachments   the ID-keyed store, and cross-note `attachment:' links
;;   orphans       the dangling-link / unreferenced-file report
;;   bibdesk, pdffile, message                the vault's own link types
;;   switch, semantic, git    changing vaults, searching them, backing up
;;
;; `scheme' and `core' are loaded before the `use-package' forms rather than
;; with the rest: a `safe-local-variable' predicate must exist before any
;; `.dir-locals.el' naming it is read, and resuming the last vault reads one.

;;; Code:

;; This configuration is a database layer over *org* notes, so org is a hard
;; dependency, not an optional one.  Requiring it here — rather than leaning on
;; a submodule to pull it in transitively — makes the `:after org' + `:demand
;; t' on the `use-package vulpea' form below fire deterministically as that
;; form is reached, so the vault commands defined in vulpea-vault/ have
;; vulpea's (non-autoloaded) query API available even on a fresh Emacs where no
;; org file has been opened yet.
(require 'org)

(emacs-config-load-module
 "vulpea-vault/scheme"
 "Could not load vulpea-vault/scheme.el; vaults cannot be recognised as such.")

(emacs-config-load-module
 "vulpea-vault/core"
 "Could not load vulpea-vault/core.el; no vault can be opened.")

;; Resume the vault opened last.  No directory is named here, or anywhere in
;; this repository: a vault becomes known by being opened, `vulpea-vault-history'
;; (savehist) remembers it, and "no vault open" is an ordinary state.
;;
;; Before the `use-package' forms below, so their `:init' blocks and every
;; module loaded from here see the vault already in place.  Setting a defcustom
;; a package has not defined yet is what those blocks were doing anyway:
;; `defcustom' keeps a value that is already bound.
(vulpea-vault-resume)

(use-package vulpea
  :straight (vulpea :type git :host github :repo "d12frosted/vulpea")
  :after org
  ;; Load eagerly (org is required at the top of this file, so this fires as the
  ;; form is reached) rather than deferring to the first `:bind' command.  The
  ;; vault commands defined in vulpea-vault/ (e.g. `vulpea-vault-orphans',
  ;; `vulpea-vault-update-id-locations') call the query API in
  ;; `vulpea-db-query.el' directly, and those functions are NOT autoloaded (the
  ;; build emits only `register-definition-prefixes').  A lazy vulpea would
  ;; leave them void until a `:bind' command happened to load the package.
  ;; `require'-ing vulpea pulls in `vulpea-db-query' transitively (through
  ;; `vulpea-buffer'), so demanding it here makes the whole query API present.
  :demand t
  :bind (("C-c n f" . vulpea-find)
         ("C-c n i" . vulpea-insert)
         ("C-c n b" . vulpea-find-backlink))
  :init
  ;; `vulpea-db-sync-directories' and `vulpea-db-location' are set by
  ;; `vulpea-vault-apply', which follows the vault.  Note their exact names:
  ;; `vulpea-directory' and `vulpea-db-file' are NOT vulpea variables — the
  ;; first survives only in a commented example in vulpea.el's header, the
  ;; second never existed.  Setting those does nothing but create globals,
  ;; leaving vulpea on its defaults: the database in `user-emacs-directory'
  ;; and the watch list at `org-directory' (~/org), wider than any one vault.
  (setq ;; Parse in one reused buffer without re-running `org-mode' per file.
   ;; The default `temp-buffer' re-runs it WITH hooks, so a full scan fires
   ;; `org-mode-hook' once per note — here that means `org-appear-mode',
   ;; the latex-to-svg setup, and lsp-ltex-plus trying to attach to a
   ;; buffer that is not visiting a file, 1000 times over.
   ;;
   ;; Safe for these notes: vulpea reads `#+filetags:' from the parsed
   ;; syntax tree rather than from `org-file-tags' (which mode init would
   ;; set), no note uses per-file `#+TODO:', `#+PROPERTY:', `#+TAGS:',
   ;; `#+SETUPFILE:' or `:DIR:', and `org-attach-id-dir' is global.
   vulpea-db-parse-method 'single-temp-buffer

   ;; Silence the routine "Vulpea: Syncing N files... / Sync complete"
   ;; echoes, which autosync fires on every save.  Only these status
   ;; reports go through `vulpea-db-sync--message'; errors and warnings
   ;; call `message' directly and are unaffected.
   vulpea-db-sync-verbose nil)
  :config
  ;; Watch the tree and index in the background.  Guarded twice over, so both
  ;; "no vault opened yet" and "a vault whose tree is not there" degrade to
  ;; "vulpea installed but idle" rather than erroring at startup.
  ;; `vulpea-vault-switch' starts the watcher when a vault is opened later.
  (cond
   ((null vulpea-vault-directory)
    (message "vulpea: no vault open; M-x vulpea-vault-switch opens one"))
   ((file-directory-p vulpea-vault-directory)
    (vulpea-db-autosync-mode +1))
   (t
    (message "vulpea: %s does not exist yet; autosync not started"
             vulpea-vault-directory))))

;; The rest of vulpea-vault/, one concern per file, loaded the way
;; `completion.el' loads completions/.  Order matters where a module
;; `require's a sibling: `attachments' before `orphans', `ids' before `switch',
;; `switch' before `semantic'.
(emacs-config-load-module
 "vulpea-vault/modified-stamp"
 "Could not load vulpea-vault/modified-stamp.el; :MODIFIED: will not refresh on save.")

(emacs-config-load-module
 "vulpea-vault/select"
 "Could not load vulpea-vault/select.el; note selection will show no dates.")

(emacs-config-load-module
 "vulpea-vault/directories"
 "Could not load vulpea-vault/directories.el; the vault's folder roles are unavailable.")

(emacs-config-load-module
 "vulpea-vault/tags"
 "Could not load vulpea-vault/tags.el; the vault's tag groups will not be in effect.")

(emacs-config-load-module
 "vulpea-vault/create"
 "Could not load vulpea-vault/create.el; new notes will use vulpea's own defaults.")

(emacs-config-load-module
 "vulpea-vault/ids"
 "Could not load vulpea-vault/ids.el; [[id:…]] links will not follow new notes.")

(emacs-config-load-module
 "vulpea-vault/attachments"
 "Could not load vulpea-vault/attachments.el; attachment: links will not resolve.")

(emacs-config-load-module
 "vulpea-vault/orphans"
 "Could not load vulpea-vault/orphans.el; `vulpea-vault-orphans' is unavailable.")

(emacs-config-load-module
 "vulpea-vault/bibdesk"
 "Could not load vulpea-vault/bibdesk.el; x-bdsk: links will not open.")

(emacs-config-load-module
 "vulpea-vault/pdffile"
 "Could not load vulpea-vault/pdffile.el; pdffile: links will not open.")

(emacs-config-load-module
 "vulpea-vault/message"
 "Could not load vulpea-vault/message.el; message: links will not open.")

(emacs-config-load-module
 "vulpea-vault/switch"
 "Could not load vulpea-vault/switch.el; `vulpea-vault-switch' is unavailable.")

;; After switch.el, whose hooks it joins (and whose feature it requires).
(emacs-config-load-module
 "vulpea-vault/semantic"
 "Could not load vulpea-vault/semantic.el; org-semantic will not follow the vault.")

(emacs-config-load-module
 "vulpea-vault/git"
 "Could not load vulpea-vault/git.el; note saves will not be recorded in git.")

;; Push the vaults' rollups over HTTPS with a forge token rather than over SSH.
;; The remotes are `git@gitlab.mpcdf.mpg.de:…' and `git@github.com:…', which
;; authenticate through the 1Password SSH agent — fine for the occasional
;; interactive push, but the rollup timer would wake it every six hours,
;; unattended.  So only the rollup subprocess rewrites the remotes, and only in
;; its own environment: Magit and the shell keep using SSH, and nothing on disk
;; changes.
;;
;; The tokens live outside this repository, in the files the shell already
;; sources, and are read fresh at each rollup by `my/env-file-value' — nothing
;; secret is committed and nothing is baked into a variable at load time.  The
;; parser is in utils.el because reading such a file is not a vulpea concern;
;; only knowing which file, and which name in it, is.  `url.<https>.insteadOf'
;; does the rewrite through git's own GIT_CONFIG_* environment protocol, so no
;; on-disk git config is touched either.  A mapping whose remote no vault uses
;; costs nothing: git rewrites only URLs that match its prefix.  All of this is
;; host-specific and so lives here, not in the (vault-agnostic) git module.

(defconst vulpea-config-git-rollup-credentials
  '(("~/.config/envs/gitlab_mpcdf.sh" "GITLAB_MPCDF_TOKEN"
     "git@gitlab.mpcdf.mpg.de:" "https://oauth2:%s@gitlab.mpcdf.mpg.de/")
    ("~/.config/envs/github_org-vault.sh" "GITHUB_TOKEN"
     "git@github.com:" "https://x-access-token:%s@github.com/"))
  "How the rollup authenticates to each forge it may have to push to.

Each entry is (ENV-FILE VAR SSH-PREFIX HTTPS-FORMAT): the plain
`KEY=VALUE' file the shell sources, the name holding the token in it, the
SSH remote prefix to rewrite, and the HTTPS replacement with a single %s
for the token.  GitLab wants the token as the password of the `oauth2'
user; GitHub accepts a personal access token (classic or fine-grained,
with `contents: write' on the repository) as the password of any user, by
convention `x-access-token'.

An entry whose file or name is missing is simply skipped, leaving that
remote on SSH — an unconfigured forge is not an error.")

(defun vulpea-config-git-rollup-environment ()
  "Environment that pushes the vaults to their forges over HTTPS.
Rewrites each SSH remote named in `vulpea-config-git-rollup-credentials'
to an HTTPS URL carrying a token, so the rollup's push authenticates with
the token instead of an SSH key.  Returns nil when no token at all is
available, leaving every push on SSH.

The files are read at each rollup through `my/env-file-value' (utils.el),
so a token is never baked into a variable at load time and rotating one
needs no restart.  Called from the rollup timer, long after utils.el is
loaded, so the reference costs no load-order constraint."
  (let ((count 0)
        (settings nil))
    (pcase-dolist (`(,file ,var ,ssh ,https) vulpea-config-git-rollup-credentials)
      (when-let* ((token (my/env-file-value (expand-file-name file) var)))
        (push (format "GIT_CONFIG_KEY_%d=url.%s.insteadOf"
                      count (format https token))
              settings)
        (push (format "GIT_CONFIG_VALUE_%d=%s" count ssh) settings)
        (setq count (1+ count))))
    (when (> count 0)
      (cons (format "GIT_CONFIG_COUNT=%d" count) (nreverse settings)))))

(with-eval-after-load 'vulpea-vault-git
  (setq vulpea-vault-git-rollup-environment
        #'vulpea-config-git-rollup-environment))

(provide 'vulpea-config)
;;; vulpea-config.el ends here
