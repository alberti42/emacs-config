;;; syntaxes/yaml.el --- YAML syntax highlighting -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-yaml t
  "Whether to enable YAML settings from syntaxes/yaml.el.")

(when emacs-config-syntaxes-enable-yaml
  (use-package yaml-mode
    :mode ("\\.ya?ml\\'" . yaml-mode)
    :hook ((yaml-mode yaml-ts-mode) . (lambda ()
                                        (setq-local indent-tabs-mode nil)
                                        (setq-local yaml-indent-offset 2)))))

(provide 'syntaxes-yaml)

;;; syntaxes/yaml.el ends here
