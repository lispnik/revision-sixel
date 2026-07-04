;;;; build.lisp --- dump a standalone revision-sixel-demo executable.
;;;;
;;;;   sbcl --script build.lisp        (or: make bin)
;;;;
;;;; Loads the system, bakes the bundled sample JPEGs into the image (so the
;;;; binary needs no external files), and saves an executable whose toplevel is
;;;; revision-sixel:main.

(require :asdf)
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system "revision-sixel"))

;; Bake the sample images into the image being dumped. save-lisp-and-die
;; snapshots special-variable values, so *embedded-images* travels with it.
(setf revision-sixel::*embedded-images*
      (loop for path in revision-sixel:*gallery*
            collect (cons (file-namestring path)
                          (revision-sixel::slurp-bytes path))))

(format t "~&Embedded ~d image(s); dumping executable…~%"
        (length revision-sixel::*embedded-images*))

(sb-ext:save-lisp-and-die
 "revision-sixel-demo"
 :executable t
 :toplevel #'revision-sixel:main
 :save-runtime-options t)
