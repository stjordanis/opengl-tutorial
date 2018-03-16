(define-library (lib opengl)
   (export
      (exports (EGL version-1-1))
      (exports (OpenGL ES version-2-0))
      (exports (otus ffi))

      glBegin glEnd
      glVertex glVertex2f glVertex3f

      opengl:init)

   (import
      (r5rs core)
      (EGL version-1-1)
      (OpenGL ES version-2-0)
      (owl interop) (owl ff) (owl io)
      (otus ffi)
      (owl string) (owl math))

   (begin

(fork-server 'opengl (lambda ()
(let this ((dictionary #empty))
(let* ((envelope (wait-mail))
       (sender msg envelope))
   (tuple-case msg
      ((debug)
         (mail sender dictionary)
         (this dictionary))

      ; display
      ((set-display display)
         (this (put dictionary 'display display)))
      ((get-display)
         (mail sender (get dictionary 'display 0))
         (this dictionary))

      ; surface
      ((set-surface surface)
         (this (put dictionary 'surface surface)))
      ((get-surface)
         (mail sender (get dictionary 'surface 0))
         (this dictionary))

      ; context
      ((set-context context)
         (this (put dictionary 'context context)))
      ((get-context)
         (mail sender (get dictionary 'context 0))
         (this dictionary))

      ; shaders
      ((set-program program)
         (this (put dictionary 'program program)))
      ((get-program)
         (mail sender (get dictionary 'program 0))
         (this dictionary))

      ; drawing
      ((glBegin mode)
         (let*((dictionary (put dictionary 'mode mode))
               (dictionary (put dictionary 'data '()))
               (dictionary (put dictionary 'vbo ((lambda ()
                              (define vpo '(0))
                              (glGenBuffers 1 vpo)
                              (car vpo))))))
            (this dictionary)))
      ((glColor r g b)
         (let ((dictionary (put dictionary 'color (list r g b))))
            (this dictionary)))
      ((glVertex x y z)
         (let ((dictionary (put dictionary 'data (append
                              (get dictionary 'data '())
                              (list x y z)
;                              (get dictionary 'color '(1 1 1))
                              ))))
            (this dictionary)))
      ((glEnd)
         (let ((data (get dictionary 'data '()))
               (vbo (get dictionary 'vbo 0))
               (vPosition (glGetAttribLocation (get dictionary 'program 0) "vPosition")))
            (glBindBuffer GL_ARRAY_BUFFER vbo)
            (glBufferData GL_ARRAY_BUFFER (* 4 (length data)) data GL_STATIC_DRAW) ; 4 = sizeof(float)

            (glUseProgram (get dictionary 'program 0))
            (glBindBuffer GL_ARRAY_BUFFER vbo)
            (glVertexAttribPointer vPosition 3 GL_FLOAT GL_FALSE 0 #false)
            (glEnableVertexAttribArray vPosition)
            (glDrawArrays GL_TRIANGLES 0 3)
         (this dictionary)))

      (else
         (print-to stderr "Unknown opengl server command " msg)
         (this dictionary)))))))

(define opengl:init
(let*((init (lambda (title)
               (let ((major '(0))
                     (minor '(0))
                     (numConfigs '(0))
                     (attribList '(
                        #x3024 5 ; red
                        #x3023 6 ; green
                        #x3022 5 ; blue
                        #x3021 8 ; alpha
                        #x3025 8 ; depth
                        ;#x3026 ; stencil
                        #x3032 1 ; sample buffers
                        #x3038)) ; EGL_NONE
                     (config (make-vptr-array 1))
                     (contextAttribs '(
                        #x3098 2 #x3038 #x3038))) ; EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE, EGL_NONE
               (print) ; empty print, some king of 'flag' in output

               (define display (eglGetDisplay #false))
               (mail 'opengl (tuple 'set-display display))

               (eglInitialize display major minor)
               (print "eglInitialize: " (car major) "/" (car minor))

               (eglGetConfigs display #f 0 numConfigs)
               (print "eglGetConfigs: " (car numConfigs))

               (eglChooseConfig display attribList config (car numConfigs) numConfigs)
               (define surface (eglCreateWindowSurface display (car config) 2 #false))                 ; temp "2" instead of XCreateWindow
               (mail 'opengl (tuple 'set-surface surface))

               (define context (eglCreateContext display (car config) EGL_NO_CONTEXT contextAttribs))
               (mail 'opengl (tuple 'set-context context))

               ; default opengl shaders
               (define vertex-shader "
                  attribute vec4 vPosition;
                  void main()
                  {
                     gl_Position = vPosition;
                  }")
               (define fragment-shader "
                  precision mediump float;
                  void main()
                  {
                     gl_FragColor = vec4( 0.0, 0.3, 0.0, 1.0 );
                  }")

               (define (CreateGLProgram vstext fstext)
               (let ((po (glCreateProgram))
                     (vs (glCreateShader GL_VERTEX_SHADER))
                     (fs (glCreateShader GL_FRAGMENT_SHADER)))
                  (if (= po 0)
                     (runtime-error "Can't create shader program." #f))

                  ; пример, как можно передать в функцию массив указателей на строки:
                  ; vertex shader:
                  ; http://steps3d.narod.ru/tutorials/lighting-tutorial.html
                  (glShaderSource vs 1 (list (c-string vstext)) #false)
                  (glCompileShader vs)
                  (let ((isCompiled '(0)))
                     (glGetShaderiv vs GL_COMPILE_STATUS isCompiled)

                     (if (eq? (car isCompiled) 0)
                        (let*((maxLength "??")
                              (_ (glGetShaderiv vs GL_INFO_LOG_LENGTH maxLength))
                              (maxLengthValue (+ (ref maxLength 0) (* (ref maxLength 1) 256)))
                              (errorLog (make-string maxLengthValue 0))
                              (_ (glGetShaderInfoLog vs maxLengthValue maxLength errorLog)))
                           (runtime-error errorLog vs))))
                  (glAttachShader po vs)

                  ; fragment shader:
                  (glShaderSource fs 1 (list (c-string fstext)) #false)
                  (glCompileShader fs)
                  (let ((isCompiled '(0)))
                     (glGetShaderiv fs GL_COMPILE_STATUS isCompiled)

                     (if (eq? (car isCompiled) 0)
                        (let*((maxLength "??")
                              (_ (glGetShaderiv fs GL_INFO_LOG_LENGTH maxLength))
                              (maxLengthValue (+ (ref maxLength 0) (* (ref maxLength 1) 256)))
                              (errorLog (make-string maxLengthValue 0))
                              (_ (glGetShaderInfoLog fs maxLengthValue maxLength errorLog)))
                           (runtime-error errorLog fs))))

                  (glAttachShader po fs)

                  (glLinkProgram po)
                  (glDetachShader po fs)
                  (glDetachShader po vs)

                  po ; return result index
               ))

               (define shader-program (CreateGLProgram vertex-shader fragment-shader))
               (glUseProgram shader-program)
               (mail 'opengl (tuple 'set-program shader-program))

               #true))))
   (case-lambda
      (() (init ""))
      ((title) (init title)))))

   (opengl:init "lib/opengl")


   ; opengl function emulation
   (define (glBegin mode)
      (mail 'opengl (tuple 'glBegin mode)))
   (define (glEnd)
      (mail 'opengl (tuple 'glEnd)))
   ; vertex
   (define (glVertex2f x y)
      (mail 'opengl (tuple 'glVertex x y 0)))
   (define (glVertex3f x y z)
      (mail 'opengl (tuple 'glVertex x y z)))
   (define glVertex (case-lambda
      ((x y)
         (glVertex2f x y))
      ((x y z)
         (glVertex3f x y z))))


))