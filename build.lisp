;;;; build.lisp --- dump a standalone tvision-sixel-demo executable.
;;;;
;;;;   sbcl --script build.lisp        (or: make bin)
;;;;
;;;; Loads the system, bakes the bundled sample JPEGs into the image (so the
;;;; binary needs no external files), and saves an executable whose toplevel is
;;;; tvision-sixel:main.

(require :asdf)
(handler-bind ((warning #'muffle-warning))
  (asdf:load-system "tvision-sixel"))

;; Bake the sample images into the image being dumped. save-lisp-and-die
;; snapshots special-variable values, so *embedded-images* travels with it.
(setf tvision-sixel::*embedded-images*
      (loop for path in tvision-sixel:*gallery*
            collect (cons (file-namestring path)
                          (tvision-sixel::slurp-bytes path))))

(format t "~&Embedded ~d image(s); dumping executable…~%"
        (length tvision-sixel::*embedded-images*))

(sb-ext:save-lisp-and-die
 "tvision-sixel-demo"
 :executable t
 :toplevel #'tvision-sixel:main
 :save-runtime-options t)
