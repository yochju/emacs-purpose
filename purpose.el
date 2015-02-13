;;; purpose.el --- Handle buffers and windows by their purposes

;; Author: Bar Magal (2015)
;; Package: purpose
;; Version: 1.0.50
;; Keywords: frames
;; Homepage: https://github.com/bmag/emacs-purpose
;; Package-Requires: ((emacs "24.3") (let-alist "1.0.3"))

;;; Commentary:

;; Purpose is a package that introduces the concept of a "purpose" for
;; windows and buffers, and then helps you maintain a robust window
;; layout easily. Purpose is intended to help both regular users and
;; developers who want Emacs to have a more IDE-like behavior.

;; Typical Usage (Regular User)
;; 1. Turn Purpose on (`purpose-mode').
;; 2. Configure which purposes you want your windows to have (see
;;    purpose-configuration.el).
;; 3. Arrange your window layout as you want it to be. Any window which
;;    you want to dedicate to a specific purpose (so it won't be used
;;    for other purposes), you shuld dedicate with
;;    `purpose-toggle-window-purpose-dedicated'.
;; 4. Use purpose-aware commands instead of your regular commands when
;;    you need to change buffers (e.g. `purpose-switch-buffer' instead
;;    of `switch-to-buffer'). This will open your buffers in the correct
;;    windows.
;; - To save your layout, or load a previously saved layout, use
;;    `purpose-save-layout' and `purpose-load-layout'. You can load a
;;    saved layout and skip phases 1 and 2, of course.

;; Purpose-Aware commands that replace common commands:
;; `purpose-switch-buffer': instead of `switch-to-buffer'
;; `purpose-pop-buffer': instead of `pop-to-buffer'
;; `purpose-find-file': instead of `find-file'
;; `purpose-find-file-other-window': instead of `find-file-other-window'

;; Important Features:
;; - Configurable: Configure how Purpose decides what's your buffer's
;;    purpose. Note that the window's purpose is determined by its
;;    buffer.
;; - Persistent Window Layout: You can save and load your window layout
;;    between sessions by using `purpose-save-layout' and
;;    `purpose-load-layout'.
;; - Purpose-Aware Buffer Switching: Commands for switching buffers
;;    without ruining your layout. The main ones are
;;    `purpose-switch-buffer', `purpose-pop-buffer' and
;;    `purpose-find-file'. Also, purpose-aware switching is supported
;;    for any function that uses `display-buffer' internally
;;    (`switch-to-buffer' doesn't). See purpose-switch.el for more.
;; - Developer-Friendly: Purpose has hooks and an API that should make
;;    it easy for developers to use it as a part of more sophisticated
;;    plugins. If it isn't, your input is welcome.

;; Developer Usage (informal API):
;; - `purpose-set-layout', `purpose-load-layout': use this to set a
;;    window layout that suits your plugin.
;; - `purpose-get-layout' or `purpose-save-layout': use this to save a
;;    layout so you can add it to your plugin later.
;; - `purpose-get-extra-window-params-function': use this if you want to
;;    save additional window parameters that make sense for your plugin,
;;    when `purpose-get-layout' is called.
;; - `purpose-set-window-properties-functions': use this hook if you
;;    want to set extra properties for new windows, when
;;    `purpose-set-layout' is called.
;; - `set-configuration', `add-configuration': use these to change the
;;    purpose configuration to suit your plugin's needs.
;; - `with-action-function-inactive': use this macro if you need
;;    `display-buffer' to ignore purposes (original behavior) while
;;    executing some piece of code.
;; - `purpose-display-buffer-hook': use this if you want to run some
;;    code every time a buffer is displayed.

;;; Installation:
;; Download Purpose's source files and put them in your `load-path'.
;; - Note: Purpose is not yet on any package repository. Once it will be
;;    there, you could download it with Emacs' package manager. For now,
;;    you have to do it manually.
;; Add these lines to your init file:
;;    (require 'purpose)
;;    (purpose-mode)

;;; Code:

(require 'purpose-configuration)
(require 'purpose-core)
(require 'purpose-layout)
(require 'purpose-switch)
(require 'purpose-prefix-overload)

(defconst purpose-version "1.0.50"
  "Purpose's version.")


;;; Commands for using Purpose-less behavior
(fset 'find-file-without-purpose
      (without-purpose-command #'ido-find-file))

(fset 'find-file-other-window-without-purpose
      (without-purpose-command #'ido-find-file-other-window))

(fset 'find-file-other-frame-without-purpose
      (without-purpose-command #'ido-find-file-other-frame))

(fset 'switch-buffer-without-purpose
      (without-purpose-command #'ido-switch-buffer))

(fset 'switch-buffer-other-window-without-purpose
      (without-purpose-command #'ido-switch-buffer-other-window))

(fset 'switch-buffer-other-frame-without-purpose
      (without-purpose-command #'ido-switch-buffer-other-frame))


;;; Overloaded commands: (C-u to get original Purpose-less behavior)
(define-purpose-prefix-overload purpose-find-file-overload
  '(ido-find-file find-file-without-purpose))

(define-purpose-prefix-overload purpose-find-file-other-window-overload
  '(ido-find-file-other-window find-file-other-window-without-purpose))

(define-purpose-prefix-overload purpose-find-file-other-frame-overload
  '(ido-find-file-other-frame find-file-other-frame-without-purpose))

(define-purpose-prefix-overload purpose-switch-buffer-overload
  '(ido-switch-buffer switch-buffer-without-purpose))

(define-purpose-prefix-overload purpose-switch-buffer-other-window-overload
  '(ido-switch-buffer-other-window switch-buffer-other-window-without-purpose))

(define-purpose-prefix-overload purpose-switch-buffer-other-frame-overload
  '(ido-switch-buffer-other-frame switch-buffer-other-frame-without-purpose))



(defvar purpose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-x C-f") #'purpose-find-file-overload)
    (define-key map (kbd "C-x 4 f") #'purpose-find-file-other-window-overload)
    (define-key map (kbd "C-x 4 C-f") #'purpose-find-file-other-window-overload)
    (define-key map (kbd "C-x 5 f") #'purpose-find-file-other-frame-overload)
    (define-key map (kbd "C-x 5 C-f") #'purpose-find-file-other-frame-overload)
    
    (define-key map (kbd "C-x b") #'purpose-switch-buffer-overload)
    (define-key map (kbd "C-x 4 b") #'purpose-switch-buffer-other-window-overload)
    (define-key map (kbd "C-x 5 b") #'purpose-switch-buffer-other-frame-overload)

    ;; Helpful for quitting temporary windows. Close in meaning to
    ;; `kill-buffer', so we map it to a close key ("C-x j" is close to
    ;; "C-x k")
    (define-key map (kbd "C-x j") #'quit-window)

    ;; We use "C-c ," for compatibility with key-binding conventions
    (define-key map (kbd "C-c ,") 'purpose-mode-prefix-map)
    (define-prefix-command 'purpose-mode-prefix-map)
    (define-key purpose-mode-prefix-map (kbd "o") #'purpose-switch-buffer)
    (define-key purpose-mode-prefix-map
      (kbd "[") #'purpose-switch-buffer-other-frame)
    (define-key purpose-mode-prefix-map
      (kbd "p") #'purpose-switch-buffer-other-window)
    (define-key purpose-mode-prefix-map
      (kbd "d") #'purpose-toggle-window-purpose-dedicated)
    (define-key purpose-mode-prefix-map
      (kbd "D") #'purpose-toggle-window-buffer-dedicated)

    map)
  "Keymap for Purpose mode.")

;; https://www.gnu.org/software/emacs/manual/html_node/elisp/Menu-Keymaps.html#Menu-Keymaps
;; (defvar purpose-menu-bar-map (make-sparse-keymap "Purpose"))

(defun purpose--modeline-string ()
  "Return the presentation of a window's purpose for display in the
modeline.  The string returned has two forms.  For example, if window's
purpose is 'edit: If (purpose-window-purpose-dedicated-p), return
\"[edit!]\", otherwise return \"[edit]\"."
  (format " [%s%s]"
	  (purpose-window-purpose)
	  (if (purpose-window-purpose-dedicated-p) "!" "")))

(defun purpose--add-advices ()
  "Add all advices needed for Purpose to work.
This function is called when `purpose-mode' is activated."
  (advice-add 'switch-to-buffer
	      :around #'purpose-switch-to-buffer-advice)
  (advice-add 'switch-to-buffer-other-window
	      :around #'purpose-switch-to-buffer-other-window-advice)
  (advice-add 'switch-to-buffer-other-frame
	      :around #'purpose-switch-to-buffer-other-frame-advice)
  (advice-add 'pop-to-buffer :around #'purpose-pop-to-buffer-advice)
  (advice-add 'pop-to-buffer-same-window
	      :around #'purpose-pop-to-buffer-same-window-advice)
  (advice-add 'display-buffer :around #'purpose-display-buffer-advice))

(defun purpose--remove-advices ()
  "Remove all advices needed for Purpose to work.
This function is called when `purpose-mode' is deactivated."
  (advice-remove 'switch-to-buffer #'purpose-switch-to-buffer-advice)
  (advice-remove 'switch-to-buffer-other-window
		 #'purpose-switch-to-buffer-other-window-advice)
  (advice-remove 'switch-to-buffer-other-frame
		 #'purpose-switch-to-buffer-other-frame-advice)
  (advice-remove 'pop-to-buffer #'purpose-pop-to-buffer-advice)
  (advice-remove 'pop-to-buffer-same-window
		 #'purpose-pop-to-buffer-same-window-advice)
  (advice-remove 'display-buffer #'purpose-display-buffer-advice))

(define-minor-mode purpose-mode
  nil :global t :lighter (:eval (purpose--modeline-string))
  (if purpose-mode
      (progn
	(purpose--add-advices)
	(setq display-buffer-overriding-action
	      '(purpose--action-function . nil))
	(setq purpose--active-p t))
    (purpose--remove-advices)
    (setq purpose--active-p nil)))

(provide 'purpose)
;;; purpose.el ends here
