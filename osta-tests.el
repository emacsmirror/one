;;; require

(require 'ert)

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

(ert-deftest osta-escape-test ()
  (should (string= (osta-escape "<") "&lt;"))
  (should (string= (osta-escape ">") "&gt;"))
  (should (string= (osta-escape "&") "&amp;"))
  (should (string= (osta-escape "\"") "&quot;"))
  (should (string= (osta-escape "'") "&apos;"))
  (should (string= (osta-escape "regular text") "regular text"))
  (should (string= (osta-escape "<...>...&...\"...'") "&lt;...&gt;...&amp;...&quot;...&apos;")))

;;; osta-ox tests

;; (global-set-key (kbd "C-<f1>") (lambda () (interactive)(ert "osta-ox-test")))

(ert-deftest osta-ox-test ()
  ;; osta-ox-headline
  (let ((get-headline
         (lambda (rv tree)
           (car (org-element-map tree 'headline
                  (lambda (e)
                    (when (string= (org-element-property :raw-value e) rv)
                      e)))))))
    ;; headline level 1 with contents
    (should
     (string=
      (org-test-with-parsed-data "* headline 1"
        (osta-ox-headline (funcall get-headline "headline 1" tree)
                          "<div>contents<div>" info))
      "<div><h1>headline 1</h1><div>contents<div></div>"))
    ;; headline level 1 with contents nil
    (should
     (string=
      (org-test-with-parsed-data "* headline 1"
        (osta-ox-headline (funcall get-headline "headline 1" tree)
                          nil info))
      "<div><h1>headline 1</h1></div>"))
    ;; headline level 2 with contents
    (should
     (string=
      (org-test-with-parsed-data "* headline 1\n** headline 2"
        (osta-ox-headline (funcall get-headline "headline 2" tree)
                          "<div>contents<div>" info))
      "<div><h2>headline 2</h2><div>contents<div></div>"))
    ;; headline with CUSTOM_ID without id part
    (should
     (string=
      (org-test-with-parsed-data "* headline 1
:PROPERTIES:
:CUSTOM_ID: /path/to/page/
:END:"
        (osta-ox-headline (funcall get-headline "headline 1" tree)
                          "<div>contents<div>" info))
      "<div><h1>headline 1</h1><div>contents<div></div>"))
    ;; headline with CUSTOM_ID and id part
    (should
     (string=
      (org-test-with-parsed-data "* headline 1\n** headline 2
:PROPERTIES:
:CUSTOM_ID: /path/to/page/#id-test
:END:"
        (osta-ox-headline (funcall get-headline "headline 2" tree) nil info))
      "<div><h2 id=\"id-test\">headline 2</h2></div>")))

  ;; section, paragraph, plain-text, bold, italic, strike-through, underline
  (should (string= (osta-ox-section nil "section" nil) "<div>section</div>"))
  (should (string= (osta-ox-section nil nil nil) ""))
  (should (string= (osta-ox-paragraph nil "paragraph" nil) "<p>paragraph</p>"))
  (should (string= (osta-ox-plain-text "<...>...&" nil) "&lt;...&gt;...&amp;"))
  (should (string= (osta-ox-bold nil "bold" nil) "<b>bold</b>"))
  (should (string= (osta-ox-italic nil "italic" nil) "<i>italic</i>"))
  (should (string= (osta-ox-strike-through nil "strike-through" nil) "<del>strike-through</del>"))
  (should (string= (osta-ox-underline nil "underline" nil) "<u>underline</u>"))

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
    (should (string= (osta-ox-plain-list ordered-list "contents" nil) "<ol>contents</ol>"))
    (should (string= (osta-ox-plain-list unordered-list "contents" nil) "<ul>contents</ul>"))
    (should-error (osta-ox-plain-list other-list "contents" nil)))
  (should (string= (osta-ox-item nil "item" nil) "<li>item</li>")))

(ert-deftest osta-ox-code-and-verbatim-test ()
  ;; code and verbatim nodes
  (let ((code (org-test-with-temp-text "before the ~inline code<point>~"
                (org-element-context)))
        (verbatim (org-test-with-temp-text "before the ~verbatim<point>~"
                    (org-element-context))))
    (should (string= (osta-ox-code code nil nil)
                     "<code class=\"osta-hl osta-hl-inline\">inline code</code>"))
    (should (string= (osta-ox-verbatim verbatim nil nil)
                     "<code class=\"osta-hl osta-hl-inline\">verbatim</code>"))))

(ert-deftest osta-ox--subscript-and-superscript ()
  ;; osta-ox-subscript, osta-ox-superscript
  (should (string= (osta-ox-subscript nil "subscript" nil)
                   "<sub>subscript</sub>"))
  (should (string= (osta-ox-superscript nil "superscript" nil)
                   "<sup>superscript</sup>"))

  ;; by default ox.el exports with specific transcode functions
  ;; for the org elements `subscript' and `superscript'.
  ;; This is controlled by the variable `org-export-with-sub-superscripts'.
  ;; See `org-export-options-alist'.
  (let ((backend
         (org-export-create-backend
          :transcoders
          '((section . (lambda (_e c _i) c))
            (paragraph . (lambda (_e c _i) c))
            (subscript . osta-ox-subscript)
            (superscript . osta-ox-superscript)))))
    (let ((org-export-with-sub-superscripts t))
      (should
       (string=
        (org-test-with-temp-text "foo_bar"
          (org-export-as backend))
        "foo<sub>bar</sub>\n"))
      (should
       (string=
        (org-test-with-temp-text "foo^bar"
          (org-export-as backend))
        "foo<sup>bar</sup>\n")))
    (let ((org-export-with-sub-superscripts nil))
      (should
       (string=
        (org-test-with-temp-text "foo_bar"
          (org-export-as backend))
        "foo_bar\n"))
      (should
       (string=
        (org-test-with-temp-text "foo^bar"
          (org-export-as backend))
        "foo^bar\n")))))

(ert-deftest osta-ox-blocks-test ()
  ;; `osta-ox-is-results-p'
  (let ((src-block (org-test-with-temp-text "
#+BEGIN_SRC bash
echo \"Hello world!\"
#+END_SRC<point>"
                     (org-element-context)))
        (src-block-results (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
#+BEGIN_SRC bash
echo \"Hello world!\"
#+END_SRC<point>"
                             (org-element-context)))
        (example-block (org-test-with-temp-text "
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                         (org-element-context)))
        (example-block-results-1 (org-test-with-temp-text "
#+RESULTS:
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                                   (org-element-context)))
        (example-block-results-2 (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                                   (org-element-context)))
        (fixed-width (org-test-with-temp-text "
: I'm a multiline fixed width
: yes I am!<point>"
                       (org-element-context)))
        (fixed-width-results-1 (org-test-with-temp-text "
#+RESULTS:
: I'm a multiline fixed width
: yes I am!<point>"
                                 (org-element-context)))
        (fixed-width-results-2 (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
: I'm a multiline fixed width
: yes I am!<point>"
                                 (org-element-context))))
    (should-not (osta-ox-is-results-p src-block))
    (should (osta-ox-is-results-p src-block-results))
    (should-not (osta-ox-is-results-p example-block))
    (should (osta-ox-is-results-p example-block-results-1))
    (should (osta-ox-is-results-p example-block-results-2))
    (should-not (osta-ox-is-results-p fixed-width))
    (should (osta-ox-is-results-p fixed-width-results-1))
    (should (osta-ox-is-results-p fixed-width-results-2)))

  ;; `osta-ox-htmlize'
  ;; note that in `sh-mode', `echo' word has the face `font-lock-builtin-face',
  ;; and strings have the faces `font-lock-string-face'.
  ;; normal blocks
  (should (string= (osta-ox-htmlize "echo \"Hello world!\"" "bash")
                   (concat "<pre><code class=\"osta-hl osta-hl-block\">"
                           "<span class=\"osta-hl-builtin\">echo</span> "
                           "<span class=\"osta-hl-string\">\"Hello world!\"</span>"
                           "</code></pre>")))
  ;; results blocks
  (should (string= (osta-ox-htmlize "echo \"Hello world!\"" "bash" t)
                   (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                           "<span class=\"osta-hl-builtin\">echo</span> "
                           "<span class=\"osta-hl-string\">\"Hello world!\"</span>"
                           "</code></pre>")))

  ;; `osta-ox-src-block'
  (let ((src-block (org-test-with-temp-text "
#+BEGIN_SRC bash
echo \"Hello world!\"
#+END_SRC<point>"
                     (org-element-context)))
        (src-block-results (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
#+BEGIN_SRC bash
echo \"Hello world!\"
#+END_SRC<point>"
                             (org-element-context))))
    (should (string= (osta-ox-src-block src-block nil nil )
                     (concat "<pre><code class=\"osta-hl osta-hl-block\">"
                             "<span class=\"osta-hl-builtin\">echo</span> "
                             "<span class=\"osta-hl-string\">\"Hello world!\"</span>"
                             "</code></pre>")))
    (should (string= (osta-ox-src-block src-block-results nil nil )
                     (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                             "<span class=\"osta-hl-builtin\">echo</span> "
                             "<span class=\"osta-hl-string\">\"Hello world!\"</span>"
                             "</code></pre>"))))

  ;; `osta-ox-example-block'
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
                                   (org-element-context)))
        (example-block-results-2 (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
#+BEGIN_EXAMPLE
A simple example
#+END_EXAMPLE<point>"
                                   (org-element-context))))
    (should (string= (osta-ox-example-block example-block nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-block\">"
                             "A simple example"
                             "</code></pre>")))
    (should (string= (osta-ox-example-block example-block-results-1 nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                             "A simple example"
                             "</code></pre>")))
    (should (string= (osta-ox-example-block example-block-results-2 nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                             "A simple example"
                             "</code></pre>"))))
  ;; `osta-ox-fixed-width'
  (let ((fixed-width (org-test-with-temp-text "
: I'm a multiline fixed width
: yes I am!<point>"
                       (org-element-context)))
        (fixed-width-results-1 (org-test-with-temp-text "
#+RESULTS:
: I'm a multiline fixed width
: yes I am!<point>"
                                 (org-element-context)))
        (fixed-width-results-2 (org-test-with-temp-text "
#+ATTR_OSTA_RESULTS:
: I'm a multiline fixed width
: yes I am!<point>"
                                 (org-element-context))))
    (should (string= (osta-ox-fixed-width fixed-width nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-block\">"
                             "I'm a multiline fixed width\nyes I am!"
                             "</code></pre>")))
    (should (string= (osta-ox-fixed-width fixed-width-results-1 nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                             "I'm a multiline fixed width\nyes I am!"
                             "</code></pre>")))
    (should (string= (osta-ox-fixed-width fixed-width-results-2 nil nil)
                     (concat "<pre><code class=\"osta-hl osta-hl-results\">"
                             "I'm a multiline fixed width\nyes I am!"
                             "</code></pre>"))))

  ;; `osta-ox-quote-block'
  (should (string= (osta-ox-quote-block nil "I'm a quote. —Tony Aldon" nil)
                   "<blockquote class=\"osta-blockquote\">I'm a quote. —Tony Aldon</blockquote>")))