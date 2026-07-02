;;;; package.lisp --- tvision-sixel

(defpackage #:tvision-sixel
  (:use #:cl)
  (:documentation
   "Display a JPEG (decoded + quantized by jpeg-sixel) as sixel graphics inside a
    tv2 Turbo Vision view. IMAGE-VIEW draws its chrome into the tv2 cell buffer
    like any other view, but paints the picture itself by writing a raw sixel
    escape sequence straight to the terminal after each screen flush.")
  (:export #:run #:demo #:image-view #:*default-image* #:*gallery*))
