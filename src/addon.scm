#!/bin/sh
exec guile -e '(audio-files-addon) main' -s $0 "$@"
!#
;; A simple addon for Docspell adding basic support audio files.
;;
;; It uses "stt" for speech-to-text and wkhtmltopdf to create a pdf
;; file from the extracted text. Docspell will automatically generate
;; the preview image from the pdf.

(define-module (audio-files-addon)
  #:use-module (json)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:export (main))

;; Some helpers
;; ------------------------------------------------------------------------------
(define* (errln formatstr . args)
  (apply format (current-error-port) formatstr args)
  (newline))

;; Macro for executing system commands and making this program exit in
;; case of failure.
(define-syntax sysexec
  (syntax-rules ()
    ((sysexec exp ...)
     (let ((rc (apply system* (list exp ...))))
       (unless (eqv? rc EXIT_SUCCESS)
         (format (current-error-port) "> '~a …' failed with: ~#*~:*~d~%" exp ... rc)
         (exit 1))
       #t))))

(fluid-set! %default-port-encoding "UTF-8")


;; External dependencies
;; ------------------------------------------------------------------------------
(define *curl* "curl")
(define *ffmpeg* "ffmpeg")
(define *stt* "stt")
(define *wkhtmltopdf* "wkhtmltopdf")

;; Getting some environment variables
(define *output-dir* (getenv "OUTPUT_DIR"))
(define *tmp-dir* (getenv "TMP_DIR"))
(define *cache-dir* (getenv "CACHE_DIR"))

(define *item-data-json* (getenv "ITEM_DATA_JSON"))
(define *original-files-json* (getenv "ITEM_ORIGINAL_JSON"))
(define *original-files-dir* (getenv "ITEM_ORIGINAL_DIR"))

;; fail early if not in the right context
(when (not *item-data-json*)
  (errln "No item data json file found.")
  (exit 1))


;; Input/Output
;; ------------------------------------------------------------------------------
;; The itemdata record, only the fields needed here.
(define-json-type <itemdata>
  (id))

;; The array of original files
(define-json-type <original-file>
  (id)
  (name)
  (position)
  (language)
  (mimetype)
  (length)
  (checksum))

;; The output record, what is returned to docspell
(define-json-type <itemfiles>
  (itemId)
  (textFiles)
  (pdfFiles))
(define-json-type <output>
  (files "files" #(<itemfiles>)))

;; Parses the JSON containing the item information
(define *itemdata-json*
  (scm->itemdata (call-with-input-file *item-data-json* json->scm)))

;; The JSON file containing meta data for all source files as vector.
(define *original-meta-json*
  (let ((props (vector->list (call-with-input-file *original-files-json* json->scm))))
    (map scm->original-file props)))


;; Convert audio files to WAV
;; ------------------------------------------------------------------------------
(define (is-wav? mime)
  "Test whether the mimetype MIME is denoting a wav file."
  (or (string-suffix? "/wav" mime)
      (string-suffix? "/x-wav" mime)
      (string-suffix? "/vnd.wav" mime)))

(define (find-audio-files)
  "Find all source files that are audio files."
  (filter! (lambda (el)
             (string-prefix?
              "audio/"
              (original-file-mimetype el)))
           *original-meta-json*))

(define (convert-wav id mime)
  "Run ffmpeg to convert to wav."
  (let ((src-file (format #f "~a/~a" *original-files-dir* id))
        (out-file (format #f "~a/in.wav" *tmp-dir*)))
    (if (is-wav? mime)
        src-file
        (begin
          (errln "Running ffmpeg to convert wav file...")
          (sysexec *ffmpeg* "-loglevel" "error" "-y" "-i" src-file out-file)
          out-file))))


;; Speech-to-text
;; ------------------------------------------------------------------------------
(define (get-model language)
  (let* ((lang (or language "eng"))
         (file (format #f "~a/model_~a.pbmm" *cache-dir* lang)))
    (unless (file-exists? file)
      (download-model lang file))
    file))

(define (download-model lang file)
  "Download model files per language. Nix has currently stt 0.9.3 packaged."
  (let ((url (cond
              ((string= lang "eng") "https://coqui.gateway.scarf.sh/english/coqui/v0.9.3/model.pbmm")
              ((string= lang "deu") "https://coqui.gateway.scarf.sh/german/AASHISHAG/v0.9.0/model.pbmm")
              (else (error "Unsupported language: " lang)))))
    (errln "Downloading model file for language: ~a" lang)
    (sysexec *curl* "-SsL" "-o" file url)
    file))

(define (extract-text model input out)
  "Runs stt for speech-to-text and writes the text into the file OUT."
  (errln "Extracting text from audio…")
  (with-output-to-file out
    (lambda ()
      (sysexec  *stt* "--model" model "--audio" input))))


;; Create PDF
;; ------------------------------------------------------------------------------
(define (create-pdf txt-file out)
  (define (line str)
    (format #t "~a\n" str))
  (errln "Creating pdf file…")
  (let ((tmphtml (format #f "~a/text.html" *tmp-dir*)))
    (with-output-to-file tmphtml
      (lambda ()
        (line "<!DOCTYPE html>")
        (line "<html>")
        (line "  <head><meta charset=\"UTF-8\"></head>")
        (line "  <body style=\"padding: 2em; font-size: large;\">")
        (line " <div style=\"padding: 0.5em; font-size:normal; font-weight: bold; border: 1px solid black;\">")
        (line "  Extracted from audio using stt on ")
        (display (strftime "%c" (localtime (current-time))))
        (line " </div>")
        (line " <p>")
        (display (call-with-input-file txt-file read-string))
        (line " </p>")
        (line "</body></html>")))
    (sysexec *wkhtmltopdf* tmphtml out)))


;; Main
;; ------------------------------------------------------------------------------
(define (process-file itemid file)
  "Processing a single audio file."
  (let* ((id (original-file-id file))
         (mime (original-file-mimetype file))
         (lang (original-file-language file))
         (txt-file (format #f "~a/~a.txt" *output-dir* id))
         (pdf-file (format #f "~a/~a.pdf" *output-dir* id))
         (wav (convert-wav id mime))
         (model (get-model lang)))
    (extract-text model wav txt-file)
    (create-pdf txt-file pdf-file)
    (make-itemfiles itemid
                    `((,id . ,(format #f "~a.txt" id)))
                    `((,id . ,(format #f "~a.pdf" id))))))

(define (process-all)
  (let ((item-id (itemdata-id *itemdata-json*)))
    (map (lambda (file)
           (process-file item-id file))
         (find-audio-files))))

(define (main args)
  (let ((out (make-output (process-all))))
    (display (output->json out))))

;; End
;; ------------------------------------------------------------------------------
;; Local Variables:
;; mode: scheme
;; End:
