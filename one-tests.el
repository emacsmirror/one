;;; require

(require 'one)
(require 'ert)
(require 'cl) ; flet

;;; macro from org-mode repository

;; testing/org-test.el
(defmacro org-test-with-temp-text (text &rest body)
  "Run body in a temporary buffer with Org mode as the active
mode holding TEXT.  If the string \"<point>\" appears in TEXT
then remove it and place the point there before running BODY,
otherwise place the point at the beginning of the inserted text."
  (declare (indent 1))
  `(let ((inside-text (if (stringp ,text) ,text (eval ,text)))
         (org-mode-hook nil))
     (with-temp-buffer
       (org-mode)
       (let ((point (string-match "<point>" inside-text)))
         (if point
             (progn
               (insert (replace-match "" nil nil inside-text))
               (goto-char (1+ (match-beginning 0))))
           (insert inside-text)
           (goto-char (point-min))))
       (font-lock-ensure (point-min) (point-max))
       ,@body)))

;; testing/lisp/test-ox.el
(defmacro org-test-with-parsed-data (data &rest body)
  "Execute body with parsed data available.
DATA is a string containing the data to be parsed.  BODY is the
body to execute.  Parse tree is available under the `tree'
variable, and communication channel under `info'."
  (declare (debug (form body)) (indent 1))
  `(org-test-with-temp-text ,data
     (org-export--delete-comment-trees)
     (let* ((tree (org-element-parse-buffer))
            (info (org-combine-plists
                   (org-export--get-export-attributes)
                   (org-export-get-environment))))
       (org-export--prune-tree tree info)
       (org-export--remove-uninterpreted-data tree info)
       (let ((info (org-combine-plists
                    info (org-export--collect-tree-properties tree info))))
         ,@body))))

;;; utils

(ert-deftest one-escape-test ()
  (should (string= (one-escape "<") "&lt;"))
  (should (string= (one-escape ">") "&gt;"))
  (should (string= (one-escape "&") "&amp;"))
  (should (string= (one-escape "\"") "&quot;"))
  (should (string= (one-escape "'") "&apos;"))
  (should (string= (one-escape "regular text") "regular text"))
  (should (string= (one-escape "<...>...&...\"...'") "&lt;...&gt;...&amp;...&quot;...&apos;")))

;;; one-ox tests

;; (global-set-key (kbd "C-<f1>") (lambda () (interactive)(ert "one-ox-section-markup-plain-list-test")))

;;;; headline, section, paragraph, etc.

(ert-deftest one-ox-headline-test ()
  (let ((get-headline
         (lambda (rv tree)
           (car (org-element-map tree 'headline
                  (lambda (e)
                    (when (string= (org-element-property :raw-value e) rv)
                      e)))))))
    (should
     (string=
      (org-test-with-temp-text "* headline 1\n** headline 2
:PROPERTIES:
:CUSTOM_ID: /path/to/page/#id-test
:END:"
        (let* ((tree (one-parse-buffer))
               (headline (funcall get-headline "headline 2" tree)))
          (one-ox-headline headline "<div>contents<div>" nil)))
      "<div><h2 id=\"id-test\">headline 2</h2><div>contents<div></div>"))
    (should
     (string=
      (org-test-with-temp-text "* headline 1\n** headline 2
:PROPERTIES:
:CUSTOM_ID: /path/to/page/#id-test
:END:"
        (let* ((tree (one-parse-buffer))
               (headline (funcall get-headline "headline 2" tree)))
          (one-ox-headline headline nil nil)))
      "<div><h2 id=\"id-test\">headline 2</h2></div>"))
    (should
     (string-match-p "id=\"one-.*\""
                     (org-test-with-temp-text "* headline 1\n** headline 2
:PROPERTIES:
:no-custom-id: so a random :one-internal-id id is set by one-parse-buffer
:END:"
                       (let* ((tree (one-parse-buffer))
                              (headline (funcall get-headline "headline 2" tree)))
                         (one-ox-headline headline nil nil)))))))

(ert-deftest one-ox-section-markup-plain-list-test ()
  ;; section, paragraph, plain-text, bold, italic, strike-through, underline, subscript, superscript
  (should (string= (one-ox-section nil "section" nil) "<div>section</div>"))
  (should (string= (one-ox-section nil nil nil) ""))
  (should (string= (one-ox-paragraph nil "paragraph" nil) "<p>paragraph</p>"))
  (should (string= (one-ox-plain-text "<...>...&" nil) "&lt;...&gt;...&amp;"))
  (should (string= (one-ox-bold nil "bold" nil) "<b>bold</b>"))
  (should (string= (one-ox-italic nil "italic" nil) "<i>italic</i>"))
  (should (string= (one-ox-strike-through nil "strike-through" nil) "<del>strike-through</del>"))
  (should (string= (one-ox-underline nil "underline" nil) "<u>underline</u>"))
  (should (string= (one-ox-no-subscript nil "foo" nil) "_foo"))
  (should (string= (one-ox-no-superscript nil "bar" nil) "^bar"))
  ;; plain-list, item
  (let ((ordered-list
         (org-test-with-temp-text "<point>1) first
2) second
3) third"
           (org-element-at-point)))
        (unordered-list
         (org-test-with-temp-text "<point>- first
- second
- third"
           (org-element-at-point)))
        (other-list
         (org-test-with-temp-text "<point>- first :: description 1
- second :: description 2
- third :: description 3"
           (org-element-at-point))))
    (should (string= (one-ox-plain-list ordered-list "contents" nil) "<ol>contents</ol>"))
    (should (string= (one-ox-plain-list unordered-list "contents" nil) "<ul>contents</ul>"))
    (should-error (one-ox-plain-list other-list "contents" nil)))
  (should (string= (one-ox-item nil "item" nil) "<li>item</li>")))

(ert-deftest one-ox-code-and-verbatim-test ()
  ;; code and verbatim nodes
  (let ((code (org-test-with-temp-text "before the ~inline code<point>~"
                (org-element-context)))
        (verbatim (org-test-with-temp-text "before the ~verbatim<point>~"
                    (org-element-context))))
    (should (string= (one-ox-code code nil nil)
                     "<code class=\"one-hl one-hl-inline\">inline code</code>"))
    (should (string= (one-ox-verbatim verbatim nil nil)
                     "<code class=\"one-hl one-hl-inline\">verbatim</code>"))))

;;;; blocks

(ert-deftest one-ox-blocks-test ()
  ;; `one-ox-htmlize'
  ;; note that in `sh-mode', `echo' word has the face `font-lock-builtin-face',
  ;; and strings have the faces `font-lock-string-face'.
  ;; normal blocks
  (should (string= (one-ox-htmlize "echo \"Hello world!\"" "bash")
                   (concat "<pre><code class=\"one-hl one-hl-block\">"
                           "<span class=\"one-hl-builtin\">echo</span> "
                           "<span class=\"one-hl-string\">\"Hello world!\"</span>"
                           "</code></pre>")))
  ;; results blocks
  (should (string= (one-ox-htmlize "echo \"Hello world!\"" "bash" t)
                   (concat "<pre><code class=\"one-hl one-hl-results\">"
                           "<span class=\"one-hl-builtin\">echo</span> "
                           "<span class=\"one-hl-string\">\"Hello world!\"</span>"
                           "</code></pre>")))

  ;; `one-ox-src-block'
  (let ((src-block (org-test-with-temp-text "
#+BEGIN_SRC bash
echo \"Hello world!\"
#+END_SRC<point>"
                     (org-element-context))))
    (should (string= (one-ox-src-block src-block nil nil )
                     (concat "<pre><code class=\"one-hl one-hl-block\">"
                             "<span class=\"one-hl-builtin\">echo</span> "
                             "<span class=\"one-hl-string\">\"Hello world!\"</span>"
                             "</code></pre>"))))

  ;; `one-ox-example-block'
  (let ((example-block (org-test-with-temp-text "
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                         (org-element-context)))
        (example-block-results-1 (org-test-with-temp-text "
#+RESULTS:
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                                   (org-element-context))))
    (should (string= (one-ox-example-block example-block nil nil)
                     (concat "<pre><code class=\"one-hl one-hl-block\">"
                             "A simple example"
                             "</code></pre>")))
    (should (string= (one-ox-example-block example-block-results-1 nil nil)
                     (concat "<pre><code class=\"one-hl one-hl-results\">"
                             "A simple example"
                             "</code></pre>"))))
  ;; `one-ox-fixed-width'
  (let ((fixed-width (org-test-with-temp-text "
: I'm a multiline fixed width
: yes I am!<point>"
                       (org-element-context)))
        (fixed-width-results-1 (org-test-with-temp-text "
#+RESULTS:
: I'm a multiline fixed width
: yes I am!<point>"
                                 (org-element-context))))
    (should (string= (one-ox-fixed-width fixed-width nil nil)
                     (concat "<pre><code class=\"one-hl one-hl-block\">"
                             "I'm a multiline fixed width\nyes I am!"
                             "</code></pre>")))
    (should (string= (one-ox-fixed-width fixed-width-results-1 nil nil)
                     (concat "<pre><code class=\"one-hl one-hl-results\">"
                             "I'm a multiline fixed width\nyes I am!"
                             "</code></pre>"))))

  ;; `one-ox-quote-block'
  (should (string= (one-ox-quote-block nil "I'm a quote. —Tony Aldon" nil)
                   "<blockquote class=\"one-blockquote\">I'm a quote. —Tony Aldon</blockquote>")))

;;;; links

(ert-deftest one-ox-link--custom-id-https-mailto-test ()
  "link type: custom-id, https, mailto"
  (let ((backend
         (org-export-create-backend
          :transcoders
          '((section . (lambda (_e c _i) c))
            (paragraph . (lambda (_e c _i) c))
            (link . one-ox-link)))))
    (should
     (string=
      (org-test-with-temp-text "[[#foo][bar]]"
        (org-export-as backend))
      "<a href=\"foo\">bar</a>\n"))
    (should
     (string=
      (org-test-with-temp-text "[[#foo]]"
        (org-export-as backend))
      "<a href=\"foo\">foo</a>\n"))
    (should
     (string=
      (org-test-with-temp-text "https://tonyaldon.com"
        (org-export-as backend))
      "<a href=\"https://tonyaldon.com\">https://tonyaldon.com</a>\n"))
    (should
     (string=
      (org-test-with-temp-text "[[https://tonyaldon.com][Tony Aldon]]"
        (org-export-as backend))
      "<a href=\"https://tonyaldon.com\">Tony Aldon</a>\n"))
    (should
     (string=
      (org-test-with-temp-text "mailto:aldon.tony.adm@gmail.com"
        (org-export-as backend))
      "<a href=\"mailto:aldon.tony.adm@gmail.com\">mailto:aldon.tony.adm@gmail.com</a>\n"))
    (should
     (string=
      (org-test-with-temp-text "[[mailto:aldon.tony.adm@gmail.com][my email]]"
        (org-export-as backend))
      "<a href=\"mailto:aldon.tony.adm@gmail.com\">my email</a>\n"))))

(ert-deftest one-ox-link--fuzzy-test ()
  "link type: fuzzy"
  (let ((backend
         (org-export-create-backend
          :transcoders
          '((section . (lambda (_e c _i) c))
            (paragraph . (lambda (_e c _i) c))
            (link . one-ox-link)))))
    (should-error
     (org-test-with-temp-text "[[fuzzy search]]"
       (org-export-as backend)))
    (should-error
     (org-test-with-temp-text "[[*fuzzy search]]"
       (org-export-as backend)))))

(ert-deftest one-ox-link--file-public-and-assets-test ()
  ;; relative file links starting with ./public or ./assets
  (let ((backend
         (org-export-create-backend
          :transcoders
          '((section . (lambda (_e c _i) c))
            (paragraph . (lambda (_e c _i) c))
            (link . one-ox-link)))))
    (should
     (string=
      (org-test-with-temp-text "[[./public/blog/page-1.md][Page 1 in markdown]]"
        (org-export-as backend))
      "<a href=\"/blog/page-1.md\">Page 1 in markdown</a>\n"))
    ;; images
    (should
     (string=
      (org-test-with-temp-text "[[./assets/images/one.png]]"
        (org-export-as backend))
      "<img src=\"/images/one.png\" alt=\"/images/one.png\" />\n"))
    (should
     (string=
      (org-test-with-temp-text "[[./assets/images/one.png][one image]]"
        (org-export-as backend))
      "<img src=\"/images/one.png\" alt=\"one image\" />\n"))))

(ert-deftest one-ox-link--custom-type-test ()
  ;; link type with an export function defined with `org-link-set-parameters'
  (org-link-set-parameters
   "foo"
   :export (lambda (path desc backend info)
             (when (eq backend 'one-ox)
               (format "<a href=\"%s\">%s</a>"
                       (concat "foo::::" path)
                       desc))))
  (let ((backend
         (org-export-create-backend
          :transcoders
          '((section . (lambda (_e c _i) c))
            (paragraph . (lambda (_e c _i) c))
            (link . one-ox-link)))))
    (should
     (string=
      (org-test-with-temp-text "[[foo:bar][My foo type link]]"
        (org-export-as backend))
      "<a href=\"foo::::bar\">My foo type link</a>\n")))
  ;; remove specific link added with `org-link-set-parameters'
  (pop org-link-parameters))

;;; pages

(ert-deftest one-internal-id-test ()
  (let ((get-headline
         (lambda (rv tree)
           (car (org-element-map tree 'headline
                  (lambda (e)
                    (when (string= (org-element-property :raw-value e) rv)
                      e)))))))
    (should
     (string=
      (org-test-with-parsed-data "* headline 1
** headline 2
:PROPERTIES:
:CUSTOM_ID: /#id-test
:END:"
        (one-internal-id (funcall get-headline "headline 2" tree)))
      "id-test"))
    (should
     (string=
      (org-test-with-parsed-data "* headline 1
** headline 2
:PROPERTIES:
:CUSTOM_ID: /path/to/page/#id-test
:END:"
        (one-internal-id (funcall get-headline "headline 2" tree)))
      "id-test"))
    (should
     (string-prefix-p "one-"
                      (org-test-with-parsed-data "* headline 1
:PROPERTIES:
:CUSTOM_ID: /path/to/page/
:END:"
                        (one-internal-id (funcall get-headline "headline 1" tree)))))
    (should
     (string-prefix-p "one-"
                      (org-test-with-parsed-data "* headline 1
** headline 2"
                        (one-internal-id (funcall get-headline "headline 2" tree)))))))

(ert-deftest one-is-page-test ()
  (should
   (let (headline)
     (equal
      (org-test-with-temp-text "* page 1
:PROPERTIES:
:ONE: render-function
:CUSTOM_ID: /path/to/page-1/
:END:"
        (setq headline (org-element-context))
        (one-is-page headline))
      `(:one-title "page 1"
        :one-path "/path/to/page-1/"
        :one-render-page-function render-function
        :one-page-tree ,headline))))
  (should-not
   (org-test-with-temp-text "** NOT A PAGE BECAUSE AT HEADLINE LEVEL > 1
:PROPERTIES:
:ONE: render-function
:CUSTOM_ID: /path/to/page-1/
:END:"
     (let* ((headline (org-element-context)))
       (one-is-page headline))))
  (should-not
   (org-test-with-temp-text "* NO PROPERTY ONE
:PROPERTIES:
:CUSTOM_ID: /path/to/page-1/
:END:"
     (let* ((headline (org-element-context)))
       (one-is-page headline))))
  (should-not
   (org-test-with-temp-text "* NO PROPERTY CUSTOM_ID
:PROPERTIES:
:ONE: render-function
:END:"
     (let* ((headline (org-element-context)))
       (one-is-page headline)))))

(ert-deftest one-list-pages-test ()
  ;; list pages
  (should
   (equal
    (org-test-with-temp-text "* page 1
:PROPERTIES:
:ONE: render-function-1
:CUSTOM_ID: /path/to/page-1/
:END:
* NOT A PAGE
* page 2
:PROPERTIES:
:ONE: render-function-2
:CUSTOM_ID: /path/to/page-2/
:END:
* Headline level 1
** NOT A PAGE (because at headline level 2)
:PROPERTIES:
:ONE: render-function-3
:CUSTOM_ID: /path/to/page-3/
:END:
* NO PROPERTY ONE
:PROPERTIES:
:CUSTOM_ID: /some/path/
:END:
* NO PROPERTY ONE
:PROPERTIES:
:ONE: render-function-4
:END:"
      (let* ((pages (one-list-pages (one-parse-buffer)))
             (page-1 (car pages))
             (page-2 (cadr pages)))
        (list (length pages)
              (plist-get page-1 :one-path)
              (plist-get page-1 :one-render-page-function)
              (car (plist-get page-1 :one-page-tree))
              (plist-get page-2 :one-path)
              (plist-get page-2 :one-render-page-function)
              (car (plist-get page-2 :one-page-tree)))))
    '(2
      "/path/to/page-1/" render-function-1 headline
      "/path/to/page-2/" render-function-2 headline)))
  ;; narrow to the first element
  (should
   (equal
    (org-test-with-temp-text "* page 1
:PROPERTIES:
:ONE: render-function-1
:CUSTOM_ID: /path/to/page-1/
:END:
* page 2
:PROPERTIES:
:ONE: render-function-2
:CUSTOM_ID: /path/to/page-2/
:END:"
      (org-narrow-to-element)
      (let* ((pages (one-list-pages (one-parse-buffer)))
             (page-1 (car pages)))
        (list (length pages)
              (plist-get page-1 :one-path)
              (plist-get page-1 :one-render-page-function)
              (car (plist-get page-1 :one-page-tree)))))
    '(1 "/path/to/page-1/" render-function-1 headline))))

(ert-deftest one-render-page-test ()
  (let* ((one-tree
          (org-test-with-temp-text "* Page foo bar
:PROPERTIES:
:ONE: render-function
:CUSTOM_ID: /foo/bar/
:END:
* Page foo bar baz
:PROPERTIES:
:ONE: render-function
:CUSTOM_ID: /foo/bar/baz/
:END:"
            (one-parse-buffer)))
         (page (one-is-page (nth 2 one-tree)))
         (pages (one-list-pages one-tree))
         (global (list :one-tree one-tree)))
    (flet ((render-function
            (page-tree pages global)
            (message "%S" pages)
            (concat "-- page   --\n"
                    ":ONE " (org-element-property :ONE page-tree) "\n"
                    ":CUSTOM_ID " (org-element-property :CUSTOM_ID page-tree) "\n"
                    "-- pages  --\n"
                    ":one-title " (plist-get (car pages) :one-title) "\n"
                    ":one-title " (plist-get (cadr pages) :one-title) "\n"
                    "-- global --\n"
                    ":one-tree " (symbol-name (car (plist-get global :one-tree))))))
      (let* ((temp-dir (file-name-as-directory
                        (expand-file-name
                         (make-temp-file "one-" 'dir))))
             (default-directory temp-dir))
        ;; we are testing `one-render-page'
        (one-render-page page pages global)
        (should
         (string=
          (with-current-buffer (find-file-noselect "public/foo/bar/index.html")
            (buffer-substring-no-properties (point-min) (point-max)))
          "-- page   --
:ONE render-function
:CUSTOM_ID /foo/bar/
-- pages  --
:one-title Page foo bar
:one-title Page foo bar baz
-- global --
:one-tree org-data"))
        (delete-directory temp-dir t)))))

(ert-deftest one-render-pages-test ()
  ;; test variables `one-add-to-global' and `one-hook',
  ;; and also that `onerc.el' file is loaded
  (flet ((render-function-1 (page-tree pages global)
                            (org-element-property :raw-value
                              (nth 2 (plist-get global :one-tree))))
         (render-function-2 (page-tree pages global)
                            (plist-get global :foo))
         ;; we define it below in the file "onerc.el"
         ;; but we want it to be local to the test
         (render-function-3 nil)
         (global-function (pages tree) "I'm BAR")
         ;; create page ./public/tag1/index.html and ./public/tag2/index.html
         (tag-hook (pages tree global)
                   (let ((tag-table (make-hash-table :test 'equal)))
                     (dolist (page pages)
                       (let ((path (plist-get page :one-path))
                             (tags (org-element-property
                                    :tags
                                    (plist-get page :one-page-tree))))
                         (dolist (tag tags)
                           (puthash (substring-no-properties tag)
                                    (push path (gethash tag tag-table)) tag-table))))
                     (maphash
                      (lambda (tag page-paths)
                        (let* ((path (concat "./public/" tag "/"))
                               (file (concat path "index.html")))
                          (make-directory path t)
                          (with-temp-file file
                            (insert (mapconcat #'identity (sort page-paths 'string<) "\n")))))
                      tag-table))))
    (let* ((temp-dir (file-name-as-directory
                      (expand-file-name
                       (make-temp-file "one-" 'dir))))
           (default-directory temp-dir)
           (_ (with-temp-file (concat temp-dir "onerc.el")
                (prin1 '(defun render-function-3 (page-tree pages global)
                          (plist-get global :bar))
                       (current-buffer))))
           (one-add-to-global
            '((:one-global-property :one-tree
               :one-global-function (lambda (pages tree) tree))
              (:one-global-property :foo
               :one-global-function (lambda (pages tree)
                                      (org-element-map tree 'headline
                                        (lambda (elt) (org-element-property :FOO elt))
                                        nil t)))
              (:one-global-property :bar
               :one-global-function global-function)))
           (one-hook '(tag-hook)))
      (org-test-with-temp-text "* Some global information
:PROPERTIES:
:FOO: FOO
:END:
* Page 1                  :tag1:
:PROPERTIES:
:ONE: render-function-1
:CUSTOM_ID: /page-1/
:END:
* Page 2                  :tag2:
:PROPERTIES:
:ONE: render-function-2
:CUSTOM_ID: /page-2/
:END:
* Page 3                  :tag1:tag2:
:PROPERTIES:
:ONE: render-function-3
:CUSTOM_ID: /page-3/
:END:"
        (one-render-pages))
      (should
       (string=
        (with-current-buffer (find-file-noselect "public/page-1/index.html")
          (buffer-substring-no-properties (point-min) (point-max)))
        "Some global information"))
      (should
       (string=
        (with-current-buffer (find-file-noselect "public/page-2/index.html")
          (buffer-substring-no-properties (point-min) (point-max)))
        "FOO"))
      (should
       (string=
        (with-current-buffer (find-file-noselect "public/page-3/index.html")
          (buffer-substring-no-properties (point-min) (point-max)))
        "I'm BAR"))
      (should
       (string=
        (with-current-buffer (find-file-noselect "public/tag1/index.html")
          (buffer-substring-no-properties (point-min) (point-max)))
        "/page-1/\n/page-3/"))
      (should
       (string=
        (with-current-buffer (find-file-noselect "public/tag2/index.html")
          (buffer-substring-no-properties (point-min) (point-max)))
        "/page-2/\n/page-3/"))
      (delete-directory temp-dir t))))

(ert-deftest one-page-at-point-test ()
  (let (one-path-1 one-path-2 one-path-3 one-path-4 one-path-5)
    (should
     (equal
      (org-test-with-temp-text "no page at point

* foo
:PROPERTIES:
:ONE: foo
:CUSTOM_ID: /foo/
:END:

some content here

* foo bar
:PROPERTIES:
:ONE: foo-bar
:CUSTOM_ID: /foo/bar/
:END:"
        (setq one-path-1 (one-page-at-point))
        (forward-line 2)
        (setq one-path-2 (one-page-at-point))
        (forward-line 6)
        (setq one-path-3 (one-page-at-point))
        (forward-line 2)
        (setq one-path-4 (one-page-at-point))
        (forward-line 2)
        (setq one-path-5 (one-page-at-point))
        (list one-path-1 one-path-2 one-path-3 one-path-4 one-path-5))
      '(nil "/foo/" "/foo/" "/foo/bar/" "/foo/bar/")))))

;;; default

(ert-deftest one-default-pages-test ()
  (should
   (equal
    (one-default-pages
     '((:one-title "HOME" :one-path "/")
       (:one-title "FOO-1" :one-path "/foo-1/")
       (:one-title "FOO-2" :one-path "/foo-2/")))
    '(:ul
      (:li (:a (@ :href "/") "HOME"))
      (:li (:a (@ :href "/foo-1/") "FOO-1"))
      (:li (:a (@ :href "/foo-2/") "FOO-2")))))
  (should
   (equal
    (one-default-pages
     '((:one-title "HOME" :one-path "/")
       (:one-title "FOO-1" :one-path "/foo-1/")
       (:one-title "FOO-2" :one-path "/foo-2/"))
     "/.+")
    '(:ul
      (:li (:a (@ :href "/foo-1/") "FOO-1"))
      (:li (:a (@ :href "/foo-2/") "FOO-2")))))
  (should
   (equal
    (one-default-pages
     '((:one-title "HOME" :one-path "/")
       (:one-title "FOO-1" :one-path "/foo/foo-1/")
       (:one-title "FOO-2" :one-path "/foo/foo-2/")
       (:one-title "BAR" :one-path "/bar/foo/")
       (:one-title "BAZ" :one-path "/baz/foo/"))
     "^/foo/")
    '(:ul
      (:li (:a (@ :href "/foo/foo-1/") "FOO-1"))
      (:li (:a (@ :href "/foo/foo-2/") "FOO-2")))))
  (should-not
   (one-default-pages '((:one-title "HOME" :one-path "/")) "/.+")))

(ert-deftest one-default-website-name-test ()
  (should
   (string=
    (one-default-website-name
     '((:one-title "HOME" :one-path "/")
       (:one-title "FOO-1" :one-path "/foo-1/")
       (:one-title "FOO-2" :one-path "/foo-2/")))
    "HOME"))
  (should-not
   (one-default-website-name
    '((:one-title "FOO-1" :one-path "/foo-1/")
      (:one-title "FOO-2" :one-path "/foo-2/")))))

(ert-deftest one-default-nav-test ()
  ;; Two pages different from the home page are expected
  (should
   (equal
    (one-default-nav
     "/foo-1/"
     '((:one-path "/")
       (:one-path "/foo-1/")))
    '(:div.nav (:a (@ :href "/") "PREV") nil nil)))
  (should
   (equal
    (one-default-nav
     "/"
     '((:one-path "/")
       (:one-path "/foo-1/")))
    '(:div.nav  nil nil (:a (@ :href "/foo-1/") "NEXT"))))
  (let* ((nav (one-default-nav
               "/foo-2/"
               '((:one-path "/")
                 (:one-path "/foo-1/")
                 (:one-path "/foo-2/")
                 (:one-path "/foo-3/")
                 (:one-path "/foo-4/"))))
         (random (nth 2 nav)))
    (should (equal (nth 1 nav) '(:a (@ :href "/foo-1/") "PREV")))
    (should (equal (nth 3 nav) '(:a (@ :href "/foo-3/") "NEXT")))
    (should-not (string= (nth 2 (nth 1 random)) "/foo-2/"))
    (should (member (nth 2 (nth 1 random)) '("/" "/foo-1/" "/foo-3/" "/foo-4/")))
    (should (equal (nth 2 random) "RANDOM"))))

(ert-deftest one-default-list-headlines-test ()
  (should
   (equal
    (org-test-with-temp-text "* page 1
:PROPERTIES:
:CUSTOM_ID: /path/to/page-1/
:END:
** headline 1.1
:PROPERTIES:
:CUSTOM_ID: /path/to/page-1/#id-11
:END:
** headline 1.2
*** headline 1.2.1
** headline 1.3
*** headline 1.3.1
* page 2
:PROPERTIES:
:CUSTOM_ID: /path/to/page-2/
:END:
** headline 2.1
*** headline 2.1.1
"
      (let* ((tree (one-parse-buffer))
             (headlines (one-default-list-headlines tree))
             (headline-1 (car headlines))
             (headline-2 (cadr headlines)))
        (list (length headlines)
              (substring-no-properties (plist-get headline-1 :id) 0 4)
              (plist-get headline-1 :level)
              (plist-get headline-1 :title)
              (plist-get headline-2 :id)
              (plist-get headline-2 :level)
              (plist-get headline-2 :title))))
    '(9
      "one-" 1 "page 1"
      "id-11" 2 "headline 1.1"))))

(global-set-key (kbd "C-<f1>") (lambda () (interactive) (ert "one-default-toc-test")))
(ert-deftest one-default-toc-test ()
  (should
   (equal
    (one-default-toc
     '((:level 2 :id "id-bar-1" :title "bar-1")
       (:level 3 :id "id-bar-1.1" :title "bar-1.1")
       (:level 3 :id "id-bar-1.2" :title "bar-1.2")
       (:level 4 :id "id-bar-1.2.1" :title "bar-1.2.1")
       (:level 4 :id "id-bar-1.2.2" :title "bar-1.2.2")
       (:level 5 :id "id-bar-1.2.2.1" :title "bar-1.2.2.1")
       (:level 5 :id "id-bar-1.2.2.2" :title "bar-1.2.2.2")
       (:level 6 :id "id-bar-1.2.2.2.1" :title "bar-1.2.2.2.1")
       (:level 6 :id "id-bar-1.2.2.2.2" :title "bar-1.2.2.2.2")
       (:level 6 :id "id-bar-1.2.2.2.3" :title "bar-1.2.2.2.3")
       (:level 2 :id "id-bar-2" :title "bar-2")
       (:level 3 :id "id-bar-2.1" :title "bar-2.1")
       (:level 3 :id "id-bar-2.2" :title "bar-2.2")
       (:level 2 :id "id-bar-3" :title "bar-3")
       (:level 3 :id "id-bar-3.1" :title "bar-3.1")
       (:level 2 :id "id-bar-4" :title "bar-4")))
    "
<ul>
<li><a href=\"#id-bar-1\">bar-1</a>
<ul>
<li><a href=\"#id-bar-1.1\">bar-1.1</a></li>
<li><a href=\"#id-bar-1.2\">bar-1.2</a>
<ul>
<li><a href=\"#id-bar-1.2.1\">bar-1.2.1</a></li>
<li><a href=\"#id-bar-1.2.2\">bar-1.2.2</a>
<ul>
<li><a href=\"#id-bar-1.2.2.1\">bar-1.2.2.1</a></li>
<li><a href=\"#id-bar-1.2.2.2\">bar-1.2.2.2</a>
<ul>
<li><a href=\"#id-bar-1.2.2.2.1\">bar-1.2.2.2.1</a></li>
<li><a href=\"#id-bar-1.2.2.2.2\">bar-1.2.2.2.2</a></li>
<li><a href=\"#id-bar-1.2.2.2.3\">bar-1.2.2.2.3</a></li>
</ul>
</li>
</ul>
</li>
</ul>
</li>
</ul>
</li>
<li><a href=\"#id-bar-2\">bar-2</a>
<ul>
<li><a href=\"#id-bar-2.1\">bar-2.1</a></li>
<li><a href=\"#id-bar-2.2\">bar-2.2</a></li>
</ul>
</li>
<li><a href=\"#id-bar-3\">bar-3</a>
<ul>
<li><a href=\"#id-bar-3.1\">bar-3.1</a></li>
</ul>
</li>
<li><a href=\"#id-bar-4\">bar-4</a></li>
</ul>
"))
  )
