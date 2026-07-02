;;;; tvision-sixel.lisp --- a JPEG shown as sixel graphics inside a tv2 view.
;;;;
;;;; tv2 renders into a character-cell back buffer and flushes only the cells
;;;; that changed. Sixel graphics are not cells — they are a raw escape sequence
;;;; the terminal paints at the current cursor pixel. So IMAGE-VIEW plays by two
;;;; rules at once:
;;;;
;;;;   * as a tv2 view it draws its chrome (title bar, hint line, a cleared
;;;;     image area) into the cell buffer through the normal DRAW helpers;
;;;;   * the picture itself is written straight to the terminal *after* each
;;;;     FLUSH-SCREEN, positioned at the image area's top-left cell and wrapped
;;;;     in DECSC/DECRC so it never perturbs the cursor state tv2 tracks.
;;;;
;;;; Because FLUSH-SCREEN only rewrites changed cells, the cleared image area is
;;;; only written on frames where it actually changes; the sixel painted on top
;;;; therefore survives until the next redraw, at which point we re-emit it.

(in-package #:tvision-sixel)

(defparameter *default-image*
  (asdf:system-relative-pathname "tvision-sixel" "media/coast.jpg")
  "The baseline JPEG shown by (RUN) when no path is given. (cl-jpeg cannot
   decode progressive JPEGs, so bundled samples are baseline-encoded.)")

;;; ---------------------------------------------------------------------------
;;; The view
;;; ---------------------------------------------------------------------------

(defclass image-view (tv2:view)
  ((file   :initarg :file   :accessor iv-file)
   (title  :initarg :title  :initform " image " :accessor iv-title)
   (sixel  :initform nil     :accessor iv-sixel)  ; cached sixel string, or NIL
   (col    :initform 0       :accessor iv-col)    ; absolute cell origin of image
   (row    :initform 0       :accessor iv-row)
   (cell-w :initarg :cell-w :initform 10 :accessor iv-cell-w) ; px per cell
   (cell-h :initarg :cell-h :initform 20 :accessor iv-cell-h))
  (:metaclass tv2:reactive-class)
  (:documentation "A full-view widget that paints a JPEG as sixel graphics."))

(defun prepare-sixel (v)
  "Compute the on-screen image area from V's bounds and cell size, then encode
   V's JPEG to a sixel string scaled to fit that area. Stores the string (or NIL
   on failure) and the area's top-left cell in V."
  (let* ((b   (tv2:view-bounds v))
         (ax  (tvision::rect-ax b))
         (ay  (tvision::rect-ay b))
         (w   (tvision::rect-width b))
         (h   (tvision::rect-height b))
         ;; leave a 2-cell inset on the sides, a title row on top and a hint
         ;; row on the bottom (each with a blank gap).
         (region-cols (max 1 (- w 4)))
         (region-rows (max 1 (- h 4)))
         (box-w (* region-cols (iv-cell-w v)))
         (box-h (* region-rows (iv-cell-h v))))
    (setf (iv-col v) (+ ax 2)
          (iv-row v) (+ ay 2)
          (iv-sixel v)
          (ignore-errors
            (jpeg-sixel:jpeg->sixel (iv-file v)
                                    :dither t
                                    :max-colors 255
                                    :max-width box-w
                                    :max-height box-h)))
    (iv-sixel v)))

(defmethod tv2:draw ((v image-view))
  "Paint the cell chrome: a title bar, a hint line, and a cleared image area.
   The picture is drawn separately (see EMIT-OVERLAY) once the cells are flushed."
  (let* ((b      (tv2:view-bounds v))
         (w      (tvision::rect-width b))
         (h      (tvision::rect-height b))
         (bg     (tv2::role :normal))
         (label  (tv2::role :label))
         (status (tv2::role :status)))
    ;; clear the whole view (so nothing bleeds through the image's margins)
    (dotimes (r h) (tv2::fill-row v 0 r w bg))
    ;; title bar
    (tv2::fill-row v 0 0 w label)
    (tv2::draw-text v 1 0 (iv-title v) label)
    ;; hint line
    (tv2::fill-row v 0 (1- h) w status)
    (tv2::draw-text v 1 (1- h)
                    (if (iv-sixel v)
                        " Esc/q: quit     r: redraw "
                        " image failed to load (baseline JPEG required) ")
                    status)))

(defun emit-overlay (v)
  "Write V's cached sixel straight to the terminal at the image area's origin.
   Wrapped in DECSC/DECRC (save/restore cursor) so it leaves tv2's cursor and
   scroll state untouched. A no-op when there is no sixel or no live screen."
  (let ((sx (iv-sixel v)))
    (when (and sx tvision:*screen*)
      (let ((out (tvision::screen-out tvision:*screen*))
            (esc (code-char 27)))
        ;; ESC 7            save cursor
        ;; ESC [ r ; c H    move to image origin (1-indexed cells)
        ;; <sixel>          the picture
        ;; ESC 8            restore cursor
        (write-string (format nil "~c7~c[~d;~dH" esc esc
                              (1+ (iv-row v)) (1+ (iv-col v)))
                      out)
        (write-string sx out)
        (write-char esc out) (write-char #\8 out)
        (finish-output out)))))

;;; ---------------------------------------------------------------------------
;;; Input: commands + keymap
;;; ---------------------------------------------------------------------------

(tv2:define-command tvs-quit (v e)
  (declare (ignore v e))
  (setf tv2::*running* nil))

(tv2:define-command tvs-redraw (v e)
  (declare (ignore v e))
  (setf tv2::*dirty* t))

(tv2:defkeymap *image-keys* ()
  (:esc tvs-quit)
  (#\q  tvs-quit)
  (#\Q  tvs-quit)
  (#\r  tvs-redraw)
  (#\R  tvs-redraw))

;;; ---------------------------------------------------------------------------
;;; Runner
;;; ---------------------------------------------------------------------------

(defun probe-cell-size ()
  "Best-effort (cell-width . cell-height) in pixels via jpeg-sixel's terminal
   probe, falling back to a typical 10x20 when there is no tty or no reply.
   Probed before entering the screen session so it can't fight tv2's input."
  (multiple-value-bind (cw ch) (ignore-errors (jpeg-sixel:query-cell-size))
    (values (or cw 10) (or ch 20))))

(defun run (&optional (image *default-image*))
  "Show IMAGE (a baseline JPEG pathname) full-screen as sixel graphics inside a
   tv2 view. Esc or q quits; r forces a redraw. Requires a sixel-capable
   terminal (iTerm2, foot, WezTerm, mlterm, xterm -ti vt340, …)."
  (multiple-value-bind (cw ch) (probe-cell-size)
    (tvision:with-screen (s)
      (let ((v (make-instance 'image-view
                              :file (pathname image)
                              :keymap *image-keys*
                              :cell-w cw :cell-h ch
                              :title (format nil " jpeg-sixel -> tv2    [~a] "
                                             (file-namestring image)))))
        (setf (tv2:view-bounds v)
              (tv2:rect 0 0 (tvision:screen-width s) (tvision:screen-height s)))
        (prepare-sixel v)
        (setf tv2::*root* v
              tv2::*ui-thread* sb-thread:*current-thread*
              tv2::*running* t
              tv2::*dirty* t)
        ;; The shared tv2 event loop, plus one line: paint the sixel on top
        ;; after the cell buffer has been flushed.
        (loop while tv2::*running* do
          (when tv2::*dirty*
            (tvision:hide-cursor s)
            (tv2:draw v)
            (tvision:flush-screen s)
            (emit-overlay v)
            (setf tv2::*dirty* nil))
          (tvision::pump-input s 0.05)
          (let ((tev (tvision::screen-next-event s)))
            (when tev
              (let ((ev (tv2::translate tev)))
                (when (typep ev 'tv2:key-event)
                  (tv2:handle-event v ev))))))))))
