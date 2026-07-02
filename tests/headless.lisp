;;;; headless.lisp --- no-tty tests for tvision-sixel.
;;;;
;;;; These exercise everything that does NOT need a live terminal: view
;;;; construction, geometry, real sixel generation from the bundled JPEG, and
;;;; that DRAW is safe when there is no screen (tvision:*screen* is NIL, so the
;;;; cell writes are no-ops). The interactive RUN loop needs a real sixel
;;;; terminal and is not driven here.

(defpackage #:tvision-sixel-test
  (:use #:cl)
  (:export #:run-tests))
(in-package #:tvision-sixel-test)

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
  (format t "~&tvision-sixel headless tests:~%")
  (let ((v (make-instance 'tvision-sixel::image-view
                          :files (list tvision-sixel:*default-image*)
                          :cell-w 10 :cell-h 20)))
    ;; give it an 80x24 full-screen bounds
    (setf (tv2:view-bounds v) (tv2:rect 0 0 80 24))
    (check (probe-file tvision-sixel:*default-image*)
           "bundled sample image exists")
    (check (>= (length tvision-sixel:*gallery*) 1)
           "gallery has at least one image")
    ;; generate the sixel
    (let ((sx (tvision-sixel::prepare-sixel v)))
      (check (esc-p sx) "prepare-sixel returns a sixel (starts with ESC)")
      (check (st-p sx)  "sixel ends with ST (ESC backslash)")
      (check (eq sx (tvision-sixel::iv-sixel v)) "sixel cached on the view")
      (check (and (= (tvision-sixel::iv-col v) 2)
                  (= (tvision-sixel::iv-row v) 2))
             "image origin inset to (2,2)"))
    ;; draw must be a no-op-safe call when there is no screen
    (check (let ((tvision:*screen* nil)) (tv2:draw v) t)
           "draw is safe with no screen")
    ;; emit-overlay must be a no-op with no screen (no error, no output)
    (check (let ((tvision:*screen* nil)) (tvision-sixel::emit-overlay v) t)
           "emit-overlay is a no-op with no screen")
    ;; the keymap resolves the quit binding
    (check (tv2::keymap-lookup tvision-sixel::*image-keys* #\q)
           "keymap binds q")
    (check (tv2::keymap-lookup tvision-sixel::*image-keys* :esc)
           "keymap binds Esc")
    (check (tv2::keymap-lookup tvision-sixel::*image-keys* :right)
           "keymap binds Right (next)"))
  ;; gallery navigation: switching images re-encodes a fresh sixel
  (when (> (length tvision-sixel:*gallery*) 1)
    (let ((g (make-instance 'tvision-sixel::image-view
                            :files tvision-sixel:*gallery* :cell-w 10 :cell-h 20)))
      (setf (tv2:view-bounds g) (tv2:rect 0 0 80 24))
      (tvision-sixel::prepare-sixel g)
      (let ((i0 (tvision-sixel::iv-index g)))
        (tvision-sixel::show-image g (1+ i0))
        (check (= (tvision-sixel::iv-index g) (1+ i0)) "next advances the index")
        (check (esc-p (tvision-sixel::iv-sixel g)) "next re-encodes a valid sixel"))
      ;; wrap-around
      (tvision-sixel::show-image g (length tvision-sixel:*gallery*))
      (check (= 0 (tvision-sixel::iv-index g)) "index wraps around")))
  (format t "~&~%~d checks, ~[all passed.~:;~:*~d failure(s).~]~%" *checks* *failures*)
  (when (plusp *failures*)
    (error "tvision-sixel tests failed: ~d/~d" *failures* *checks*))
  t)
