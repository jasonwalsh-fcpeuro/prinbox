;;; prinbox-test.el --- Tests for prinbox.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by Tests/Adapters/run.sh in batch Emacs against the stub command: every command runs asynchronously, so
;; each step pumps the process loop until the buffer shows what it waits for.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'prinbox)

(defvar prinbox-test--root
  (expand-file-name "../../.." (file-name-directory (or load-file-name buffer-file-name)))
  "The repository root.")

(defvar prinbox-test--stub (expand-file-name "Tests/Adapters/bin/prinbox" prinbox-test--root)
  "The stub command.")

(defvar prinbox-test--log (make-temp-file "prinbox-stub-log")
  "Where the stub records its calls.")

(defvar prinbox-test--opened nil
  "URLs handed to `browse-url'.")

(defun prinbox-test--wait (predicate)
  "Pump the process loop until PREDICATE holds or five seconds pass; fail if it never holds."
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (should (funcall predicate))))

(defun prinbox-test--log-lines ()
  "The stub's log, one call per line."
  (with-temp-buffer
    (insert-file-contents prinbox-test--log)
    (split-string (buffer-string) "\n" t)))

(defun prinbox-test--reset ()
  "Point the package at the stub and start from nothing.
A run left over from the previous test finishes first, so its log line and its
count cannot leak into this one."
  (prinbox-test--wait
   (lambda () (not (seq-some (lambda (process) (and (string-prefix-p "prinbox" (process-name process))
                                                     (process-live-p process)))
                             (process-list)))))
  (accept-process-output nil 0.05) ; the last sentinel runs
  (setq prinbox-command prinbox-test--stub)
  (setenv "PRINBOX_STUB_LOG" prinbox-test--log)
  (setenv "PRINBOX_STUB_EXIT" nil)
  (setenv "PRINBOX_STUB_VERSION" nil)
  (with-temp-file prinbox-test--log (insert ""))
  (when (get-buffer "*prinbox*") (kill-buffer "*prinbox*"))
  (setq prinbox-test--opened nil)
  (setq prinbox--last nil)
  (setq prinbox--failed nil)
  (setq prinbox-mode-line-string ""))

(defun prinbox-test--entries ()
  "The entries the buffer shows."
  (with-current-buffer "*prinbox*" tabulated-list-entries))

(defun prinbox-test--cell (entry column)
  "Text of COLUMN in ENTRY, without properties."
  (substring-no-properties (aref (cadr entry) column)))

(defun prinbox-test--wait-for-rows ()
  "Wait until the demo rows are shown."
  (prinbox-test--wait (lambda () (and (get-buffer "*prinbox*") (> (length (prinbox-test--entries)) 10)))))

(ert-deftest prinbox-test-lists-sections-and-rows-in-order ()
  "The buffer lists every row under its section, in the document's order."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (should (derived-mode-p 'prinbox-mode))
    (should (string-match-p "^10 waiting on you · updated [0-9][0-9]:[0-9][0-9] · 4 new$" header-line-format))
    (should (equal (length tabulated-list-entries) 19))
    (let ((first (car tabulated-list-entries)) (last (car (last tabulated-list-entries))))
      (should (equal (car first) "DEMO_1290"))
      (should (equal (prinbox-test--cell first 0) "Needs your review"))
      (should (equal (prinbox-test--cell first 2) "Migrate the settings page to the new design system"))
      (should (equal (prinbox-test--cell first 6) "stack 1/2"))
      (should (equal (car last) "DEMO_1284"))
      (should (equal (prinbox-test--cell last 0) "Waiting on others"))
      (should (equal (prinbox-test--cell last 6) "snoozed")))
    (should (equal (prinbox--count) "10"))))

(defun prinbox-test--separators ()
  "The section separator overlays in the buffer."
  (seq-filter (lambda (o) (overlay-get o 'prinbox-separator)) (overlays-in (point-min) (point-max))))

(ert-deftest prinbox-test-sections-have-colors-and-separators ()
  "Each section's first label has its kind's face, later labels are dimmed, and a rule sits between sections."
  (prinbox-test--reset)
  (let ((prinbox-section-separator 'rule) (prinbox-section-repeat-label 'dim)
        (prinbox-section-faces prinbox-section-kind-faces))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (with-current-buffer "*prinbox*"
      (let* ((entries tabulated-list-entries)
             (first (car entries))
             (second (cadr entries))
             (titles (delete-dups (mapcar (lambda (entry) (prinbox-test--cell entry 0)) entries)))
             (separators (prinbox-test--separators)))
        (should (eq (get-text-property 0 'face (aref (cadr first) 0)) 'prinbox-section-needs-review))
        (when (equal (prinbox-test--cell second 0) (prinbox-test--cell first 0))
          (should (eq (get-text-property 0 'face (aref (cadr second) 0)) 'prinbox-section-continued)))
        ;; One rule per section after the first; the rows and their text are unchanged.
        (should (= (length separators) (1- (length titles))))
        (should (string-match-p "── Take another look"
                                (mapconcat (lambda (o) (overlay-get o 'before-string)) separators "")))
        (should (equal (length entries) 19))))))

(ert-deftest prinbox-test-section-label-and-separator-options ()
  "The repeat label shows, dims or hides; the separator is a rule, a blank line or nothing."
  (let ((section '((kind . "needsReview") (title . "Needs your review"))))
    (let ((prinbox-section-repeat-label 'show) (prinbox-section-faces prinbox-section-kind-faces))
      (should (eq (get-text-property 0 'face (prinbox--section-label section nil)) 'prinbox-section-needs-review)))
    (let ((prinbox-section-repeat-label 'hide))
      (let ((label (prinbox--section-label section nil)))
        (should (equal (substring-no-properties label) "Needs your review"))
        (should (equal (get-text-property 0 'display label) (make-string (length "Needs your review") ?\s))))))
  (dolist (case '((blank . "\n") (nil . nil)))
    (prinbox-test--reset)
    (let ((prinbox-section-separator (car case)))
      (prinbox)
      (prinbox-test--wait-for-rows)
      (with-current-buffer "*prinbox*"
        (if (cdr case)
            (should (seq-every-p (lambda (o) (equal (overlay-get o 'before-string) (cdr case)))
                                 (prinbox-test--separators)))
          (should-not (prinbox-test--separators)))))))

(ert-deftest prinbox-test-section-defaults ()
  "Out of the box the buffer looks as before: no rules, every label shown in `prinbox-section'."
  (cl-flet ((standard (symbol) (eval (car (get symbol 'standard-value)) t)))
    (should (eq (standard 'prinbox-section-separator) nil))
    (should (eq (standard 'prinbox-section-repeat-label) 'show))
    (should (eq (standard 'prinbox-section-faces) nil))
    (should (eq (get-text-property 0 'face (prinbox--section-label '((kind . "needsReview") (title . "N")) t))
                'prinbox-section))
    (should (equal (cdr (assoc "needsReview" prinbox-section-kind-faces)) 'prinbox-section-needs-review))))

(ert-deftest prinbox-test-ret-opens-and-s-u-run-the-command ()
  "RET opens the row's URL; s and u run the command, then re-read the cache."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  ;; Both inbox runs (the cache, then the refresh) finish before the log is cleared.
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (with-current-buffer "*prinbox*"
    (goto-char (point-min))
    (should (string-match-p "Section" (buffer-substring-no-properties (point-min) (line-end-position))))
    (should (string-prefix-p "10 waiting on you" header-line-format))
    (forward-line 1)
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
      (prinbox-open))
    (should (equal prinbox-test--opened '("https://github.com/acme/web/pull/1290")))
    (with-temp-file prinbox-test--log (insert ""))
    (forward-line 1)
    (prinbox-snooze)
    (prinbox-test--wait (lambda () (= (length (prinbox-test--log-lines)) 2)))
    (should (equal (prinbox-test--log-lines) '("snooze DEMO_1291" "inbox json")))
    (prinbox-unsnooze)
    (prinbox-test--wait (lambda () (= (length (prinbox-test--log-lines)) 4)))
    (should (equal (nth 2 (prinbox-test--log-lines)) "unsnooze DEMO_1291"))))

(ert-deftest prinbox-test-list-mode-conventions ()
  "b opens like RET, G fetches like g, y and w copy the link, M-n and M-p jump between sections."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (with-current-buffer "*prinbox*"
    (dolist (pair '(("b" . prinbox-open) ("G" . prinbox-refresh) ("y" . prinbox-copy-link)
                    ("w" . prinbox-copy-link) ("a" . prinbox-toggle-all)
                    ("M-n" . prinbox-next-section) ("M-p" . prinbox-previous-section)))
      (should (eq (keymap-lookup prinbox-mode-map (car pair)) (cdr pair))))
    (goto-char (point-min))
    (forward-line 1)
    (prinbox-copy-link)
    (should (equal (current-kill 0) "https://github.com/acme/web/pull/1290"))
    (let ((first (substring-no-properties (aref (tabulated-list-get-entry) 0))))
      (prinbox-next-section)
      (should-not (equal (substring-no-properties (aref (tabulated-list-get-entry) 0)) first))
      (let ((second-start (point)))
        (forward-line 1)
        (prinbox-previous-section)
        (should (= (point) second-start))
        (prinbox-previous-section)
        (should (equal (substring-no-properties (aref (tabulated-list-get-entry) 0)) first))))))

(ert-deftest prinbox-test-a-toggles-the-reviewed-section ()
  "a flips `prinbox-all' and fetches with --all."
  (prinbox-test--reset)
  (let ((prinbox-all nil))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
    (with-current-buffer "*prinbox*"
      (prinbox-toggle-all)
      (should prinbox-all)
      (prinbox-test--wait (lambda () (member "inbox json all" (prinbox-test--log-lines)))))))

(ert-deftest prinbox-test-errors-are-shown ()
  "Each failure shows its text, and the count turns to `!' with the last badge."
  (prinbox-test--reset)
  (setenv "PRINBOX_STUB_EXIT" "3")
  (prinbox)
  (prinbox-test--wait
   (lambda () (and (get-buffer "*prinbox*")
                   (with-current-buffer "*prinbox*" (string-match-p "gh auth login" (buffer-string))))))
  (with-current-buffer "*prinbox*"
    (should (string-prefix-p "0 waiting on you" header-line-format))
    (should (equal (prinbox--count) "!")))
  (setenv "PRINBOX_STUB_EXIT" "1")
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*"
                (string-match-p "^10 waiting on you.*· GitHub did not answer in time$" header-line-format))))
  (should (equal (length (prinbox-test--entries)) 19))
  (should (equal (prinbox--count) "!10"))
  (setenv "PRINBOX_STUB_EXIT" nil)
  (setenv "PRINBOX_STUB_VERSION" "2")
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*"
                (equal header-line-format "prinbox prints JSON version 2; this plugin reads version 1"))))
  (should (equal (prinbox--count) "!10"))
  (setenv "PRINBOX_STUB_VERSION" nil)
  (setq prinbox-command (expand-file-name "Tests/Adapters/bin/no-such-prinbox" prinbox-test--root))
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*" (equal header-line-format prinbox--install))))
  (should (equal (prinbox--count) "!10")))

(ert-deftest prinbox-test-count-follows-every-run ()
  "A run that prints no document turns a healthy count into `!' and the last badge."
  (prinbox-test--reset)
  (prinbox--remember (list :document '((version . 1) (badge . 10))))
  (should (equal (prinbox--count) "10"))
  (prinbox--remember (list :message prinbox--install))
  (should (equal (prinbox--count) "!10"))
  (should (equal prinbox-mode-line-string "!10"))
  (prinbox--remember (list :message "prinbox prints JSON version 2; this plugin reads version 1"))
  (should (equal (prinbox--count) "!10"))
  (prinbox--remember (list :document '((version . 1) (badge . 10))))
  (should (equal (prinbox--count) "10")))

(ert-deftest prinbox-test-section-column-off ()
  "Without the Section column the header starts at #, every section gets a rule, and rows keep their section."
  (should (eq (eval (car (get 'prinbox-section-column 'standard-value)) t) t))
  (prinbox-test--reset)
  (let ((prinbox-section-column nil))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (with-current-buffer "*prinbox*"
      (goto-char (point-min))
      (should-not (string-match-p "Section" (buffer-substring-no-properties (point-min) (line-end-position))))
      (let* ((titles (delete-dups (mapcar (lambda (entry) (prinbox-test--cell entry 0)) tabulated-list-entries)))
             (separators (seq-filter (lambda (o) (overlay-get o 'prinbox-separator))
                                     (overlays-in (point-min) (point-max)))))
        (should (= (length separators) (length titles)))
        (should (string-match-p "── Needs your review"
                                (mapconcat (lambda (o) (overlay-get o 'before-string)) separators ""))))
      (forward-line 1)
      (should (equal (substring-no-properties (aref (tabulated-list-get-entry) 0)) "Needs your review"))
      (should (string-match-p "^ *1290 " (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
      (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
        (prinbox-open))
      (should (equal prinbox-test--opened '("https://github.com/acme/web/pull/1290")))))
  ;; With the column (the default) the header names the Section column and the first section has no rule.
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (goto-char (point-min))
    (should (string-match-p "Section" (buffer-substring-no-properties (point-min) (line-end-position))))
    (forward-line 1)
    (should-not (seq-filter (lambda (o) (overlay-get o 'prinbox-separator)) (overlays-at (point))))))

(ert-deftest prinbox-test-more-line-opens-the-section-page ()
  "A capped section ends with its more line, which opens the section's page."
  (prinbox-test--reset)
  (let* ((row '((id . "x") (number . 7) (title . "T") (repository . "acme/web")
                (reasonText . "Review requested") (age . "1h") (url . "https://example.test/7")))
         (section `((kind . "needsReview") (title . "Needs your review") (count . 3) (moreCount . 2)
                    (moreUrl . "https://example.test/more") (rows . (,row))))
         (document `((version . 1) (badge . 3) (sections . (,section)))))
    (prinbox--render (list :document document)))
  (with-current-buffer "*prinbox*"
    (should (equal (length tabulated-list-entries) 2))
    (let ((more (nth 1 tabulated-list-entries)))
      (should (equal (car more) "more-needsReview"))
      (should (equal (prinbox-test--cell more 2) "+2 more on GitHub")))
    (goto-char (point-min))
    (forward-line 2)
    (should (equal (tabulated-list-get-id) "more-needsReview"))
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
      (prinbox-open))
    (should (equal prinbox-test--opened '("https://example.test/more")))
    (prinbox-snooze)
    (accept-process-output nil 0.3)
    (should (equal (prinbox-test--log-lines) nil))))

(ert-deftest prinbox-test-reason-badges ()
  "CI is red, merge conflicts and changes requested show as failure badges; snoozed rows stay dim."
  (should (eq (default-value 'prinbox-reason-badges) nil))
  (prinbox-test--reset)
  (setq prinbox-reason-badges t)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (dolist (entry tabulated-list-entries)
      (let* ((row (cdr (seq-find (lambda (item) (equal (alist-get 'id (cdr item)) (car entry)))
                                 (prinbox--rows (plist-get prinbox--report :document)))))
             (face (get-text-property 0 'face (aref (cadr entry) 4))))
        (when row
          (cond ((alist-get 'snoozed row) (should (eq face 'prinbox-snoozed)))
                ((member (alist-get 'reason row) '("ciRed" "mergeConflicts" "changesRequested"))
                 (should (eq face 'prinbox-reason-failure)))
                ((equal (alist-get 'reason row) "readyToMerge")
                 (should (eq face 'prinbox-reason-success)))))))
    (should (eq (prinbox--reason-face '((reason . "ciRed"))) 'prinbox-reason-failure))
    (should (eq (prinbox--reason-face '((reason . "reviewRequested"))) 'prinbox-reason-attention))
    (should (eq (prinbox--reason-face '((reason . "draft"))) 'prinbox-reason-neutral)))
  (setq prinbox-reason-badges nil))

(ert-deftest prinbox-test-setup-replaces-the-rows ()
  "Exit 3 shows the setup steps in place of the rows, even cached ones."
  (let* ((row '((id . "DEMO_1290") (number . 1290) (title . "Migrate the settings page")
                (repository . "acme/web") (reasonText . "Review requested") (age . "2d")))
         (document `((version . 1) (badge . 1)
                     (sections ((kind . "needsReview") (title . "Needs your review") (rows ,row)))))
         (report (list :document document :message "Sign in to the GitHub CLI\n     gh auth login" :setup t))
         (entries (prinbox--entries report)))
    (should (equal (length entries) 2))
    (should (cl-every (lambda (entry) (string-prefix-p "message-" (car entry))) entries))
    (should (equal (mapcar (lambda (entry) (prinbox-test--cell entry 2)) entries)
                   '("Sign in to the GitHub CLI" "     gh auth login")))))

(ert-deftest prinbox-test-default-owners-shorten-repositories ()
  "Repositories of a default owner show without the owner; others and the URLs are unchanged."
  (should (null (eval (car (get 'prinbox-default-owners 'standard-value)) t)))
  (let ((prinbox-default-owners '("acme")))
    (should (equal (prinbox--short-repository "acme/web") "web"))
    (should (equal (prinbox--short-repository "ACME/web") "web"))
    (should (equal (prinbox--short-repository "other/web") "other/web"))
    (should (equal (prinbox--short-repository "noslash") "noslash")))
  (let ((prinbox-default-owners nil)
        (process-environment (cons (concat "XDG_CONFIG_HOME=" (make-temp-file "prinbox-xdg" t))
                                   process-environment)))
    (should (equal (prinbox--short-repository "acme/web") "acme/web"))
    ;; settings.json's defaultOwners applies when the option is unset; the option wins when set.
    (make-directory (file-name-directory (prinbox--settings-file)) t)
    (with-temp-file (prinbox--settings-file) (insert "{\"defaultOwners\": [\"acme\"], \"orgColors\": {}}"))
    (should (equal (prinbox--short-repository "acme/web") "web"))
    (let ((prinbox-default-owners '("other")))
      (should (equal (prinbox--short-repository "acme/web") "acme/web"))
      (should (equal (prinbox--short-repository "other/web") "web"))))
  (prinbox-test--reset)
  (let ((prinbox-default-owners '("acme")))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (with-current-buffer "*prinbox*"
      (should (equal (prinbox-test--cell (car tabulated-list-entries) 3) "web"))
      (goto-char (point-min))
      (forward-line 1)
      (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
        (prinbox-open))
      (should (equal prinbox-test--opened '("https://github.com/acme/web/pull/1290"))))))

(ert-deftest prinbox-test-auto-owner-is-the-only-org ()
  "`auto' drops the one owner besides the viewer; the viewer's repos and a second owner keep prefixes."
  (let ((one-org `((viewer . "me")
                   (sections ((kind . "needsReview") (title . "Needs your review")
                              (rows ((id . "a") (repository . "acme/web"))
                                    ((id . "b") (repository . "Acme/api"))
                                    ((id . "c") (repository . "me/dotfiles")))))))
        (two-orgs `((viewer . "me")
                    (sections ((kind . "needsReview") (title . "Needs your review")
                               (rows ((id . "a") (repository . "acme/web"))
                                     ((id . "b") (repository . "globex/api"))))))))
    (should (equal (prinbox--auto-owners one-org) '("acme")))
    (should-not (prinbox--auto-owners two-orgs))
    (let ((prinbox-default-owners 'auto)
          (prinbox--document-owners (prinbox--auto-owners one-org)))
      (should (equal (prinbox--short-repository "acme/web") "web"))
      (should (equal (prinbox--short-repository "me/dotfiles") "me/dotfiles")))
    ;; The demo spans three owners, so auto keeps every prefix.
    (prinbox-test--reset)
    (let ((prinbox-default-owners 'auto))
      (prinbox)
      (prinbox-test--wait-for-rows)
      (with-current-buffer "*prinbox*"
        (should (equal (prinbox-test--cell (car tabulated-list-entries) 3) "acme/web"))))))

(ert-deftest prinbox-test-report-maps-the-exit-codes ()
  "Every exit code maps to its report."
  (should (equal (plist-get (prinbox--report 0 "{\"version\":1,\"badge\":2}" "") :document)
                 '((version . 1) (badge . 2))))
  (should (equal (prinbox--report 0 "not json" "") '(:message "prinbox printed something that is not JSON")))
  (should (equal (plist-get (prinbox--report 1 "{\"version\":1,\"error\":{\"message\":\"Offline\"}}" "") :message)
                 "Offline"))
  (should (equal (plist-get (prinbox--report 3 "" "Sign in\n") :message) "Sign in"))
  (should (equal (prinbox--report 127 "" "") (list :message prinbox--install)))
  (should (equal (prinbox--report 2 "" "prinbox: unknown option\n") '(:message "prinbox: unknown option")))
  (should (equal (prinbox--report 0 "{\"version\":2}" "")
                 '(:message "prinbox prints JSON version 2; this plugin reads version 1"))))

(ert-deftest prinbox-test-icons ()
  "Every reason and section has a one-column Unicode icon; nerd falls back to Unicode without nerd-icons."
  (should (null (eval (car (get 'prinbox-icons 'standard-value)) t)))
  (let ((codes '("reviewRequested" "reReviewRequested" "mentioned" "awaitingReply" "openThreads"
                 "changesRequested" "mergeConflicts" "ciRed" "readyToMerge" "draft" "waitingForReview"
                 "snoozed" "pushedSinceApproval" "pushedSinceChangesRequested" "youApproved"
                 "youRequestedChanges" "youCommented" "needsReview" "repliesToYou" "takeAnotherLook"
                 "mentions" "yourPRs" "waitingOnOthers" "reviewed")))
    (let ((prinbox-icons nil))
      (should (equal (prinbox--with-icon "ciRed" "CI is red") "CI is red")))
    (let ((prinbox-icons 'unicode))
      (dolist (code codes)
        (let ((icon (prinbox--icon code)))
          (should (= (length icon) 1))
          (should (= (string-width icon) 1))))
      (should (equal (prinbox--with-icon "ciRed" "CI is red") "✗ CI is red"))
      (should (equal (prinbox--with-icon nil "x") "x")))
    (unless (featurep 'nerd-icons)
      (let ((prinbox-icons 'nerd))
        (should (equal (prinbox--icon "ciRed") "✗")))))
  (prinbox-test--reset)
  (let ((prinbox-icons 'unicode) (prinbox-section-separator 'rule))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (with-current-buffer "*prinbox*"
      (should (member "● Review requested"
                      (mapcar (lambda (entry) (prinbox-test--cell entry 4)) tabulated-list-entries)))
      ;; Section rules carry the section's icon too.
      (let ((rules (mapcar (lambda (o) (overlay-get o 'before-string))
                           (seq-filter (lambda (o) (overlay-get o 'prinbox-separator))
                                       (overlays-in (point-min) (point-max))))))
        (should rules)
        (should (seq-every-p (lambda (rule) (string-match-p "\\`── [●↩↻@◆○✓] " rule)) rules)))))
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (should (member "Review requested" (mapcar (lambda (entry) (prinbox-test--cell entry 4)) tabulated-list-entries)))))

(ert-deftest prinbox-test-mode-line-mode-polls ()
  "The minor mode adds the count to the mode line and takes it out again."
  (prinbox-test--reset)
  (let ((prinbox-poll-seconds 1))
    (prinbox-mode-line-mode 1)
    (prinbox-test--wait (lambda () (equal prinbox-mode-line-string "10")))
    (should (member '(:eval (prinbox--mode-line)) global-mode-string))
    (should (equal (prinbox--mode-line) " PR:10"))
    (prinbox-mode-line-mode -1)
    (should-not (member '(:eval (prinbox--mode-line)) global-mode-string))))

(ert-deftest prinbox-test-review-order-and-drafts ()
  "Review rows can be ordered small-and-recent first, with drafts last or hidden; own sections never move."
  (cl-flet ((standard (symbol) (eval (car (get symbol 'standard-value)) t)))
    (should (null (standard 'prinbox-review-order)))
    (should (eq (standard 'prinbox-review-drafts) 'show)))
  (let* ((row (lambda (n add draft since)
                `((id . ,(format "r%d" n)) (number . ,n) (additions . ,add) (deletions . 0)
                  (isDraft . ,(if draft t :false)) (waitingSince . ,since))))
         ;; A mock reviewer's queue in the CLI's order, longest waiting first: a stale draft, a large
         ;; migration, a very large refactor, a medium feature and a one-line fix.
         (rows (list (funcall row 201 240 t "2030-01-10T00:00:00Z")
                     (funcall row 202 1100 nil "2030-03-01T00:00:00Z")
                     (funcall row 203 5000 nil "2030-05-01T00:00:00Z")
                     (funcall row 204 800 nil "2030-05-20T00:00:00Z")
                     (funcall row 205 12 nil "2030-05-10T00:00:00Z")))
         (review '((kind . "needsReview")))
         (numbers (lambda (section) (mapcar (lambda (r) (alist-get 'number r))
                                            (prinbox--order-rows section rows)))))
    (let ((prinbox-review-order nil) (prinbox-review-drafts 'show))
      (should (equal (funcall numbers review) '(201 202 203 204 205))))
    (let ((prinbox-review-order 'quick) (prinbox-review-drafts 'last))
      ;; 205 (12 lines), 204 (800), then the two over 1000 newest first, then the draft.
      (should (equal (funcall numbers review) '(205 204 203 202 201))))
    (let ((prinbox-review-order 'recent) (prinbox-review-drafts 'hide))
      (should (equal (funcall numbers review) '(204 205 203 202))))
    (let ((prinbox-review-order 'small-first) (prinbox-review-drafts 'show))
      (should (equal (funcall numbers review) '(205 201 204 202 203))))
    (let ((prinbox-review-order 'quick) (prinbox-review-drafts 'hide))
      (should (equal (funcall numbers '((kind . "yourPRs"))) '(201 202 203 204 205))))
    ;; A stack moves as one block, in its own order.
    (let* ((stacked (list (funcall row 1 900 nil "2030-01-01T00:00:00Z")
                          (append (funcall row 2 10 nil "2030-02-01T00:00:00Z") '((stack . ((position . 1)))))
                          (append (funcall row 3 2000 nil "2030-02-01T00:00:00Z") '((stack . ((position . 2)))))))
           (prinbox-review-order 'quick) (prinbox-review-drafts 'show))
      (should (equal (mapcar (lambda (r) (alist-get 'number r)) (prinbox--order-rows review stacked))
                     '(2 3 1))))))

(ert-deftest prinbox-test-ret-opens-the-diff-since-your-review ()
  "A row whose diff moved since your review opens GitHub's diff since that review."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (goto-char (point-min))
    (while (and (not (eobp)) (not (equal (tabulated-list-get-id) "DEMO_2210")))
      (forward-line 1))
    (should (equal (tabulated-list-get-id) "DEMO_2210"))
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
      (prinbox-open))
    (should (equal prinbox-test--opened
                   '("https://github.com/acme/api/pull/2210/files/3f9c2d1..b7e41a0")))))

(ert-deftest prinbox-test-all-asks-for-the-reviewed-section ()
  "With `prinbox-all' set the buffer lists the Reviewed section."
  (prinbox-test--reset)
  (let ((prinbox-all t))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (prinbox-test--wait (lambda () (member "inbox json all" (prinbox-test--log-lines))))
    (with-current-buffer "*prinbox*"
      (should (seq-some (lambda (entry) (equal (car entry) "DEMO_1250")) tabulated-list-entries)))))

(ert-deftest prinbox-test-rows-pass-through ()
  "`prinbox-rows' is off by default and, when set, asks the command for that many rows per section."
  (should (null (eval (car (get 'prinbox-rows 'standard-value)) t)))
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (should-not (seq-some (lambda (line) (string-search "rows" line)) (prinbox-test--log-lines)))
  (prinbox-test--reset)
  (let ((prinbox-rows 20))
    (prinbox)
    (prinbox-test--wait-for-rows)
    (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
    (should (equal (prinbox-test--log-lines) '("inbox json rows 20" "inbox json rows 20")))))

(provide 'prinbox-test)
;;; prinbox-test.el ends here
