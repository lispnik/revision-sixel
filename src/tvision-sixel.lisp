;;;; tvision-sixel.lisp --- JPEGs shown as sixel graphics inside a revision view.
;;;;
;;;; revision renders into a character-cell back buffer and flushes only the cells
;;;; that changed. Sixel graphics are not cells — they are a raw escape sequence
;;;; the terminal paints at the current cursor pixel. So IMAGE-VIEW plays by two
;;;; rules at once:
;;;;
;;;;   * as a revision view it draws its chrome (title bar, hint line, a cleared
;;;;     image area) into the cell buffer through the normal DRAW helpers;
;;;;   * the picture itself is written straight to the terminal *after* each
;;;;     FLUSH-SCREEN, positioned at the image area's top-left cell and wrapped
;;;;     in DECSC/DECRC so it never perturbs the cursor state revision tracks.
;;;;
;;;; Because FLUSH-SCREEN only rewrites changed cells, the cleared image area is
;;;; only written on frames where it actually changes; the sixel painted on top
;;;; therefore survives until the next redraw, at which point we re-emit it.
;;;; Switching images (the gallery demo) mutates a reactive slot, which forces a
;;;; redraw and a fresh emit — so the same seam handles dynamic content.

(in-package #:tvision-sixel)

(defun bundled-image (name)
  (asdf:system-relative-pathname "tvision-sixel"
                                 (format nil "media/~a" name)))

(defparameter *default-image* (bundled-image "coast.jpg")
  "The baseline JPEG shown by (RUN) when no path is given. (cl-jpeg cannot
   decode progressive JPEGs, so bundled samples are baseline-encoded.)")

(defparameter *gallery*
  (remove-if-not #'probe-file
                 (mapcar #'bundled-image '("coast.jpg" "nature.jpg" "flower.jpg")))
  "The images (DEMO) cycles through.")

;;; ---------------------------------------------------------------------------
;;; The view
;;; ---------------------------------------------------------------------------

(defclass image-view (revision::view)
  ((files  :initarg :files  :accessor iv-files)   ; list of JPEG pathnames
   (index  :initarg :index  :initform 0 :accessor iv-index) ; current file (reactive)
   (sixel  :initform nil     :accessor iv-sixel)  ; cached sixel string, or NIL
   (col    :initform 0       :accessor iv-col)    ; absolute cell origin of image
   (row    :initform 0       :accessor iv-row)
   (help-p :initform nil     :accessor iv-help-p) ; help overlay shown? (reactive)
   (cell-w :initarg :cell-w :initform 10 :accessor iv-cell-w) ; px per cell
   (cell-h :initarg :cell-h :initform 20 :accessor iv-cell-h))
  (:metaclass revision::reactive-class)
  (:documentation "A full-view widget that paints a JPEG as sixel graphics and
   can cycle through a list of them."))

(defun iv-current-file (v)
  (nth (iv-index v) (iv-files v)))

(defun prepare-sixel (v)
  "Compute the on-screen image area from V's bounds and cell size, then encode
   V's current JPEG to a sixel string scaled to fit that area. Stores the string
   (or NIL on failure) and the area's top-left cell in V."
  (let* ((b   (revision::view-bounds v))
         (ax  (revision::rect-ax b))
         (ay  (revision::rect-ay b))
         (w   (revision::rect-width b))
         (h   (revision::rect-height b))
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
            (jpeg-sixel:jpeg->sixel (iv-current-file v)
                                    :dither t
                                    :max-colors 255
                                    :max-width box-w
                                    :max-height box-h)))
    (iv-sixel v)))

(defun show-image (v i)
  "Switch V to image I (wrapping), re-encode, and request a redraw."
  (setf (iv-index v) (mod i (length (iv-files v))))
  (prepare-sixel v)
  (setf revision::*dirty* t))

;;; --- help overlay -----------------------------------------------------------

(defparameter *help-lines*
  '(""
    "  tvision-sixel — a jpeg-sixel picture inside a revision view"
    ""
    "   ←  →         previous / next image"
    "   Space  n     next image"
    "   p            previous image"
    "   r            redraw / re-emit the sixel"
    "   ?  F1        toggle this help"
    "   Esc  q       quit"
    ""
    "  The image is decoded and quantized by jpeg-sixel, then"
    "  written as a sixel escape straight to the terminal after"
    "  revision flushes its character cells."
    ""
    "  Press any key to close help."
    ""))

(defun draw-box (v x0 y0 bw bh attr)
  "Draw a light box-drawing frame of BW×BH at view-local (X0,Y0) in ATTR."
  (let* ((mid (make-string (max 0 (- bw 2)) :initial-element #\─))
         (top (format nil "┌~a┐" mid))
         (bot (format nil "└~a┘" mid)))
    (revision::draw-text v x0 y0 top attr)
    (revision::draw-text v x0 (+ y0 (1- bh)) bot attr)
    (loop for r from 1 below (1- bh) do
      (revision::draw-text v x0 (+ y0 r) "│" attr)
      (revision::draw-text v (+ x0 (1- bw)) (+ y0 r) "│" attr))))

(defun draw-help (v)
  "Fill the view and draw a centered help panel (cells only — no sixel)."
  (let* ((b   (revision::view-bounds v))
         (w   (revision::rect-width b))
         (h   (revision::rect-height b))
         (bg  (revision::role :normal))
         (panel (revision::role :label))
         (lines *help-lines*)
         (bw  (min w (+ 4 (reduce #'max lines :key #'length))))
         (bh  (min h (+ 2 (length lines))))
         (x0  (max 0 (floor (- w bw) 2)))
         (y0  (max 0 (floor (- h bh) 2))))
    ;; erase everything (this also paints over any sixel pixels underneath)
    (dotimes (r h) (revision::fill-row v 0 r w bg))
    ;; panel background + frame + text
    (dotimes (r bh) (revision::fill-row v x0 (+ y0 r) bw panel))
    (draw-box v x0 y0 bw bh panel)
    (loop for line in lines
          for r from 1
          while (< r (1- bh))
          do (revision::draw-text v (+ x0 1) (+ y0 r) line panel))))

(defmethod revision::draw ((v image-view))
  "Paint the cell chrome: a title bar, a hint line, and a cleared image area.
   The picture is drawn separately (see EMIT-OVERLAY) once the cells are flushed.
   When the help overlay is up, draw that instead and skip the picture."
  (when (iv-help-p v)
    (return-from revision::draw (draw-help v)))
  (let* ((b      (revision::view-bounds v))
         (w      (revision::rect-width b))
         (h      (revision::rect-height b))
         (bg     (revision::role :normal))
         (label  (revision::role :label))
         (status (revision::role :status))
         (n      (length (iv-files v)))
         (title  (format nil " jpeg-sixel -> revision    [~d/~d] ~a "
                         (1+ (iv-index v)) n
                         (file-namestring (iv-current-file v)))))
    ;; clear the whole view (so nothing bleeds through the image's margins)
    (dotimes (r h) (revision::fill-row v 0 r w bg))
    ;; title bar
    (revision::fill-row v 0 0 w label)
    (revision::draw-text v 1 0 title label)
    ;; hint line
    (revision::fill-row v 0 (1- h) w status)
    (revision::draw-text v 1 (1- h)
                    (if (iv-sixel v)
                        (if (> n 1)
                            " <-/->: prev/next     ?: help     Esc/q: quit "
                            " ?: help     r: redraw     Esc/q: quit ")
                        " image failed to load (baseline JPEG required) ")
                    status)))

(defun emit-overlay (v)
  "Write V's cached sixel straight to the terminal at the image area's origin.
   Wrapped in DECSC/DECRC (save/restore cursor) so it leaves revision's cursor and
   scroll state untouched. A no-op when there is no sixel or no live screen."
  (let ((sx (iv-sixel v)))
    (when (and sx revision::*screen* (not (iv-help-p v)))
      (let ((out (revision::screen-out revision::*screen*))
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

(revision::define-command tvs-quit (v e)
  (declare (ignore v e))
  (setf revision::*running* nil))

(revision::define-command tvs-redraw (v e)
  (declare (ignore v e))
  (setf revision::*dirty* t))

(revision::define-command tvs-next (v e)
  (declare (ignore e))
  (show-image v (1+ (iv-index v))))

(revision::define-command tvs-prev (v e)
  (declare (ignore e))
  (show-image v (1- (iv-index v))))

(revision::define-command tvs-help (v e)
  (declare (ignore e))
  (setf (iv-help-p v) (not (iv-help-p v))))

(revision::defkeymap *image-keys* ()
  (:esc   tvs-quit)
  (#\q    tvs-quit)
  (#\Q    tvs-quit)
  (#\r    tvs-redraw)
  (#\R    tvs-redraw)
  (#\?    tvs-help)
  (:f1    tvs-help)
  (:right tvs-next)
  (#\Space tvs-next)
  (#\n    tvs-next)
  (:left  tvs-prev)
  (#\p    tvs-prev))

(defmethod revision::handle-event ((v image-view) (e revision::key-event))
  "While the help overlay is up it is modal: q/Esc still quit, but any other key
   just dismisses it. Otherwise fall through to the normal keymap dispatch."
  (if (iv-help-p v)
      (let ((k (revision::event-keysym e)))
        (if (member k (list #\q #\Q :esc) :test #'eql)
            (setf revision::*running* nil)
            (setf (iv-help-p v) nil)))
      (call-next-method)))

;;; ---------------------------------------------------------------------------
;;; Runner
;;; ---------------------------------------------------------------------------

(defun probe-cell-size ()
  "Best-effort (cell-width cell-height) in pixels via jpeg-sixel's terminal
   probe, falling back to a typical 10x20 when there is no tty or no reply.
   Probed before entering the screen session so it can't fight revision's input."
  (multiple-value-bind (cw ch) (ignore-errors (jpeg-sixel:query-cell-size))
    (values (or cw 10) (or ch 20))))

(defun run-gallery (files)
  "Show FILES (baseline JPEG pathnames) full-screen as sixel graphics inside a
   revision view, one at a time. Arrow keys switch images; Esc or q quits."
  (multiple-value-bind (cw ch) (probe-cell-size)
    (revision::with-screen (s)
      (let ((v (make-instance 'image-view
                              :files (mapcar #'pathname files)
                              :keymap *image-keys*
                              :cell-w cw :cell-h ch)))
        (setf (revision::view-bounds v)
              (revision::rect 0 0 (revision::screen-width s) (revision::screen-height s)))
        (prepare-sixel v)
        (setf revision::*root* v
              revision::*ui-thread* sb-thread:*current-thread*
              revision::*running* t
              revision::*dirty* t)
        ;; The shared revision event loop, plus one line: paint the sixel on top
        ;; after the cell buffer has been flushed.
        (loop while revision::*running* do
          (when revision::*dirty*
            (revision::hide-cursor s)
            (revision::draw v)
            (revision::flush-screen s)
            (emit-overlay v)
            (setf revision::*dirty* nil))
          (revision::pump-input s 0.05)
          (let ((tev (revision::screen-next-event s)))
            (when tev
              (let ((ev (revision::translate tev)))
                (when (typep ev 'revision::key-event)
                  (revision::handle-event v ev))))))))))

(defun run (&optional (image *default-image*))
  "Show a single IMAGE (a baseline JPEG pathname) full-screen as sixel graphics.
   Esc or q quits; r redraws. Requires a sixel-capable terminal (iTerm2, foot,
   WezTerm, mlterm, xterm -ti vt340, …)."
  (run-gallery (list image)))

(defun demo (&optional (images *gallery*))
  "The gallery demo: cycle through IMAGES (default: the bundled samples) with
   the left/right arrows (or Space / n / p). Esc or q quits."
  (run-gallery (or images (list *default-image*))))

;;; ---------------------------------------------------------------------------
;;; Standalone executable
;;;
;;; save-lisp-and-die snapshots the heap but not external files, so the sample
;;; JPEGs are baked into *EMBEDDED-IMAGES* at build time (see build.lisp) and
;;; written to a temp dir at startup — the binary carries its own pictures.
;;; ---------------------------------------------------------------------------

(defvar *embedded-images* nil
  "In a dumped executable: a list of (basename . (unsigned-byte 8) vector) baked
   in at build time. NIL in a normal image (the bundled files are used instead).")

(defun slurp-bytes (path)
  "Read PATH into a fresh (unsigned-byte 8) vector."
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((buf (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence buf in)
      buf)))

(defun materialize-embedded (&optional (embedded *embedded-images*))
  "Write EMBEDDED (name . bytes) pairs to a fresh temp directory and return the
   list of pathnames, in order."
  (let ((dir (ensure-directories-exist
              (merge-pathnames (format nil "tvision-sixel-~d/" (sb-unix:unix-getpid))
                               (uiop:temporary-directory)))))
    (loop for (name . bytes) in embedded
          for path = (merge-pathnames name dir)
          do (with-open-file (out path :direction :output :if-exists :supersede
                                       :element-type '(unsigned-byte 8))
               (write-sequence bytes out))
          collect path)))

(defun main ()
  "Executable entry point. Any command-line arguments that name existing files
   are shown as the gallery; otherwise the embedded (or bundled) samples are."
  (let ((paths (remove-if-not #'probe-file (rest sb-ext:*posix-argv*))))
    (handler-case
        (cond (paths (run-gallery paths))
              (*embedded-images* (demo (materialize-embedded)))
              (t (demo)))
      (error (e)
        (format *error-output* "~&tvision-sixel: ~a~%" e))))
  (finish-output)
  (uiop:quit 0))
