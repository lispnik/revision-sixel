;;;; package.lisp --- revision-sixel

(defpackage #:revision-sixel
  (:use #:cl)
  (:documentation
   "Display a JPEG (decoded + quantized by jpeg-sixel) as sixel graphics inside a
    revision Turbo Vision view. IMAGE-VIEW draws its chrome into the revision cell buffer
    like any other view, but paints the picture itself by writing a raw sixel
    escape sequence straight to the terminal after each screen flush.")
  (:export #:run #:demo #:main #:image-view #:*default-image* #:*gallery*))
