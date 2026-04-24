;;; jupyter-config.el --- emacs-jupyter for remote Jupyter kernels -*- lexical-binding: t; -*-

;; emacs-jupyter talks to Jupyter kernels via the kernel protocol (ZMQ for
;; local kernels, WebSockets when going through a Jupyter Server).  The
;; on-disk format stays plain `.org' — no `.ipynb' involved; this is purely
;; the kernel-attach mechanism.
;;
;; Prerequisite: the `zmq' Emacs dynamic module compiles against libzmq at
;; install time.  If straight.el's build of `zmq' fails, install the C
;; library first (`brew install zmq' on macOS) and re-run
;; `straight-rebuild-package'.  The module is required by `emacs-jupyter'
;; even for server-mode workflows, where ZMQ itself isn't on the wire.

(use-package jupyter
  :straight t
  :after org
  :config
  ;; Register the jupyter babel backend so `#+begin_src jupyter-python'
  ;; (and any other `jupyter-LANG') is recognized.  org-babel-load-languages
  ;; needs the explicit `org-babel-do-load-languages' call to take effect.
  (add-to-list 'org-babel-load-languages '(jupyter . t))
  (org-babel-do-load-languages
   'org-babel-load-languages
   org-babel-load-languages))

(provide 'jupyter-config)
;;; jupyter-config.el ends here
