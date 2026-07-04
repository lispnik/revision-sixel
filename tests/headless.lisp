;;;; headless.lisp --- no-tty tests for revision-sixel.
;;;;
;;;; These exercise everything that does NOT need a live terminal: view
;;;; construction, geometry, real sixel generation from the bundled JPEG, and
;;;; that DRAW is safe when there is no screen (revision::*screen* is NIL, so the
;;;; cell writes are no-ops). The interactive RUN loop needs a real sixel
;;;; terminal and is not driven here.

(defpackage #:revision-sixel-test
  (:use #:cl)
  (:export #:run-tests))
(in-package #:revision-sixel-test)

(defvar *failures* 0)
(defvar *checks* 0)

(defmacro check (form &optional msg)
  `(progn
     (incf *checks*)
     (handler-case
         (if ,form
             (format t "  ok   ~a~%" (or ,msg ',form))
             (progn (incf *failures*) (format t "  FAIL ~a~%" (or ,msg ',form))))
       (error (e)
         (incf *failures*)
         (format t "  FAIL ~a  [signalled ~a]~%" (or ,msg ',form) e)))))

(defun esc-p (s) (and (stringp s) (plusp (length s)) (char= (char s 0) (code-char 27))))
(defun st-p (s) (and (stringp s) (>= (length s) 2)
                     (char= (char s (- (length s) 2)) (code-char 27))
                     (char= (char s (1- (length s))) #\\)))

(defun run-tests ()
  (setf *failures* 0 *checks* 0)
  (format t "~&revision-sixel headless tests:~%")
  (let ((v (make-instance 'revision-sixel::image-view
                          :files (list revision-sixel:*default-image*)
                          :cell-w 10 :cell-h 20)))
    ;; give it an 80x24 full-screen bounds
    (setf (revision::view-bounds v) (revision::rect 0 0 80 24))
    (check (probe-file revision-sixel:*default-image*)
           "bundled sample image exists")
    (check (>= (length revision-sixel:*gallery*) 1)
           "gallery has at least one image")
    ;; generate the sixel
    (let ((sx (revision-sixel::prepare-sixel v)))
      (check (esc-p sx) "prepare-sixel returns a sixel (starts with ESC)")
      (check (st-p sx)  "sixel ends with ST (ESC backslash)")
      (check (eq sx (revision-sixel::iv-sixel v)) "sixel cached on the view")
      (check (and (= (revision-sixel::iv-col v) 2)
                  (= (revision-sixel::iv-row v) 2))
             "image origin inset to (2,2)"))
    ;; draw must be a no-op-safe call when there is no screen
    (check (let ((revision::*screen* nil)) (revision::draw v) t)
           "draw is safe with no screen")
    ;; emit-overlay must be a no-op with no screen (no error, no output)
    (check (let ((revision::*screen* nil)) (revision-sixel::emit-overlay v) t)
           "emit-overlay is a no-op with no screen")
    ;; help overlay: toggling suppresses the sixel and draw stays safe
    (check (not (revision-sixel::iv-help-p v)) "help starts hidden")
    (setf (revision-sixel::iv-help-p v) t)
    (check (let ((revision::*screen* nil)) (revision::draw v) t) "help draw is safe")
    (check (let ((revision::*screen* nil)) (revision-sixel::emit-overlay v) t)
           "emit-overlay is a no-op while help is up")
    (setf (revision-sixel::iv-help-p v) nil)
    (check (revision::keymap-lookup revision-sixel::*image-keys* #\?)
           "keymap binds ? (help)")
    ;; the keymap resolves the quit binding
    (check (revision::keymap-lookup revision-sixel::*image-keys* #\q)
           "keymap binds q")
    (check (revision::keymap-lookup revision-sixel::*image-keys* :esc)
           "keymap binds Esc")
    (check (revision::keymap-lookup revision-sixel::*image-keys* :right)
           "keymap binds Right (next)"))
  ;; gallery navigation: switching images re-encodes a fresh sixel
  (when (> (length revision-sixel:*gallery*) 1)
    (let ((g (make-instance 'revision-sixel::image-view
                            :files revision-sixel:*gallery* :cell-w 10 :cell-h 20)))
      (setf (revision::view-bounds g) (revision::rect 0 0 80 24))
      (revision-sixel::prepare-sixel g)
      (let ((i0 (revision-sixel::iv-index g)))
        (revision-sixel::show-image g (1+ i0))
        (check (= (revision-sixel::iv-index g) (1+ i0)) "next advances the index")
        (check (esc-p (revision-sixel::iv-sixel g)) "next re-encodes a valid sixel"))
      ;; wrap-around
      (revision-sixel::show-image g (length revision-sixel:*gallery*))
      (check (= 0 (revision-sixel::iv-index g)) "index wraps around")))
  (format t "~&~%~d checks, ~[all passed.~:;~:*~d failure(s).~]~%" *checks* *failures*)
  (when (plusp *failures*)
    (error "revision-sixel tests failed: ~d/~d" *failures* *checks*))
  t)
