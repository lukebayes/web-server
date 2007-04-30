(module util mzscheme
  (require (lib "contract.ss")
           (lib "string.ss")
           (lib "list.ss")
           (lib "url.ss" "net")
           (lib "plt-match.ss")
           (lib "uri-codec.ss" "net"))
  (require "../request-structs.ss")
  
  ;; valid-port? : any/c -> boolean?
  (define (valid-port? p)
    (and (integer? p) (exact? p) (<= 1 p 65535)))
  
  ;; ripped this off from url-unit.ss
  (define (url-path->string strs)
    (apply string-append
           (apply append
                  (map (lambda (s) (list "/" (maybe-join-params s)))
                       strs))))
  
  ;; needs to unquote things!
  (define (maybe-join-params s)
    (if (string? s)
        s
        (let ([s (path/param-path s)])
          (if (string? s)
              s
              (case s
                [(same) "."]
                [(up)   ".."]
                [else (error 'maybe-join-params
                             "bad value from path/param-path: ~e" s)])))))
  
  ;; decompse-request : request -> uri * symbol * string
  (define (decompose-request req)
    (let* ([uri (request-uri req)]
           [method (request-method req)]
           [path (uri-decode (url-path->string (url-path uri)))])
      (values uri method path)))
  
  ;; network-error: symbol string . values -> void
  ;; throws a formatted exn:fail:network
  (define (network-error src fmt . args)
    (raise (make-exn:fail:network (format "~a: ~a" src (apply format fmt args))
                                  (current-continuation-marks))))
  
  ;; build-path-unless-absolute : path-string? path-string? -> path?
  (define (build-path-unless-absolute base path)
    (if (absolute-path? path)
        (build-path path)
        (build-path base path)))
  
  ;; exn->string : (or/c exn any) -> string
  (define (exn->string exn)
    (if (exn? exn)
        (parameterize ([current-error-port (open-output-string)])
          ((error-display-handler) (exn-message exn) exn)
          (get-output-string (current-error-port)))
        (format "~s\n" exn)))
  
  ; lowercase-symbol! : (or/c string bytes) -> symbol
  (define (lowercase-symbol! s)
    (let ([s (if (bytes? s)
                 (bytes->string/utf-8 s)
                 s)])
      (string-lowercase! s)
      (string->symbol s)))
  
  ; prefix? : str -> str -> bool
  ; more here - consider moving this to mzlib's string.ss
  ;; Notes: (GregP)
  ;; 1. What's the significance of char # 255 ???
  ;; 2. 255 isn't an ascii character. ascii is 7-bit
  ;; 3. OK f this. It is only used in three places, some of them
  ;;    will involve bytes while the others may involve strings. So
  ;;    I will just use regular expressions and get on with life.
  (define (prefix?-old prefix)
    (let* ([len (string-length prefix)]
           [last (string-ref prefix (sub1 len))]
           [ascii (char->integer last)])
      (if (= 255 ascii)
          ; something could be done about this - ab255 -> ac
          ; and all 255's eliminates upper range check
          (error 'prefix? "prefix can't end in the largest character")
          (let ([next (string-append (substring prefix 0 (sub1 len))
                                     (string (integer->char (add1 ascii))))])
            (lambda (x)
              (and (string<=? prefix x) (string<? x next)))))))      
  
  (define (directory-part path)
    (let-values ([(base name must-be-dir) (split-path path)])
      (cond
        [(eq? 'relative base) (current-directory)]
        [(not base) (error 'directory-part "~a is a top-level directory" path)]
        [(path? base) base])))
  
  ; to convert a platform dependent path into a listof path parts such that
  ; (forall x (equal? (path->list x) (path->list (apply build-path (path->list x)))))
  (define (path->list p)
    (let loop ([p p] [acc null])
      (let-values ([(base name must-be-dir?) (split-path p)])
        (let ([new-acc (cons name acc)])
          (cond
            [(string? base) (loop base new-acc)]
            [else ; conflate 'relative and #f
             new-acc])))))
  
  ; this is used by launchers
  ; extract-flag : sym (listof (cons sym alpha)) alpha -> alpha
  ; XXX remove
  (define (extract-flag name flags default)
    (let ([x (assq name flags)])
      (if x
          (cdr x)
          default)))
  
  ; hash-table-empty? : hash-table -> bool
  (define (hash-table-empty? table)
    (zero? (hash-table-count table)))
  
  (provide/contract
   [url-path->string ((listof (or/c string? path/param?)) . -> . string?)]
   [extract-flag (symbol? (listof (cons/c symbol? any/c)) any/c . -> . any/c)]
   [hash-table-empty? (any/c . -> . boolean?)]
   [valid-port? (any/c . -> . boolean?)]
   [decompose-request ((request?) . ->* . (url? symbol? string?))]
   [network-error ((symbol? string?) (listof any/c) . ->* . (void))]
   [path->list  (path? . -> . (cons/c (or/c path? (symbols 'up 'same))
                                      (listof (or/c path? (symbols 'up 'same)))))]
   [directory-part (path? . -> . path?)]
   [lowercase-symbol! ((or/c string? bytes?) . -> . symbol?)]
   [exn->string ((or/c exn? any/c) . -> . string?)]
   [build-path-unless-absolute (path-string? path-string? . -> . path?)]))