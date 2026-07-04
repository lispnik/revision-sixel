;;;; revision-sixel.asd
;;;;
;;;; A small demo: decode a JPEG with jpeg-sixel and display it as real sixel
;;;; graphics inside a revision (CLOS-native Turbo Vision) view.
;;;;
;;;; Both dependencies are sibling projects under ~/Projects/common-lisp/ and are
;;;; resolved by the global ASDF source-registry (:tree) config — no ocicl entry
;;;; is needed for them. revision pulls in its own deps via tvision's systems/.

(asdf:defsystem "revision-sixel"
  :description "Display a JPEG as sixel graphics inside a revision Turbo Vision view."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("revision" "jpeg-sixel")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "revision-sixel"))))
  :in-order-to ((asdf:test-op (asdf:test-op "revision-sixel/test"))))

(asdf:defsystem "revision-sixel/test"
  :description "Headless (no-tty) tests for revision-sixel."
  :depends-on ("revision-sixel")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "headless"))))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :revision-sixel-test :run-tests)))
