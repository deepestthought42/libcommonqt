;;; -*- show-trailing-whitespace: t; indent-tabs-mode: nil -*-

;;; Copyright (c) 2009 David Lichteblau. All rights reserved.

;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.
;;;
;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package :qt)
#+sbcl (declaim (optimize (debug 2)))

(defvar *class-table*)
(defvar *method-table*)
(defvar *prototype-table*)
(defvar *type-table*)

(defclass qclass ()
  ((id :initarg :id
       :accessor qclass-id)
   (struct :initarg :struct
           :accessor qclass-struct)
   (name :initarg :name
         :accessor qclass-name)
   (superclasses :initarg :superclasses
                 :accessor qclass-superclasses)
   (flags :initarg :flags
          :accessor qclass-flags)
   (trampoline-fun :initarg :trampoline-fun
                   :accessor qclass-trampoline-fun)
   (enum-fun :initarg :enum-fun
             :accessor qclass-enum-fun)
   (prototypes :initform nil
               :accessor qclass-prototypes)
   (hashed-prototypes :initform nil
                      :accessor qclass-hashed-prototypes)
   (tracep :initform nil
           :accessor qclass-tracep)))

(defclass external-qclass ()
  ((id :initarg :id
       :accessor qclass-id)
   (struct :initarg :struct
           :accessor qclass-struct)))

(defmethod print-object ((instance qclass) stream)
  (print-unreadable-object (instance stream :type t :identity nil)
    (format stream "~A" (qclass-name instance))))

(defclass qmethod ()
  ((id :initarg :id
       :accessor qmethod-id)
   (struct :initarg :struct
           :accessor qmethod-struct)
   (class :initarg :class
          :accessor qmethod-class)
   (name :initarg :name
         :accessor qmethod-name)
   (flags :initarg :flags
         :accessor qmethod-flags)
   (return-type :initarg :return-type
                :accessor qmethod-return-type)
   (argument-types :initarg :argument-types
                   :accessor qmethod-argument-types)
   (method-arg-for-classfn :initarg :method-arg-for-classfn
                           :accessor qmethod-method-arg-for-classfn)
   (trace-counter :initform 0
                  :accessor qmethod-trace-counter)))

(defmethod print-object ((instance qmethod) stream)
  (print-unreadable-object (instance stream :type t :identity nil)
    (format stream "~A.~A"
            (qclass-name (qmethod-class instance))
            (qmethod-name instance))))

(defclass qprototype ()                 ;aka Smoke::MethodMap
  ((class :initarg :class
          :accessor qprototype-class)
   (methods :initarg :methods
            :accessor qprototype-methods)
   (name :initarg :name
         :accessor qprototype-name)))

(defclass qtype ()
  ((id :initarg :id
       :accessor qtype-id)
   (class :initarg :class
          :accessor qtype-class)
   (name :initarg :name
         :accessor qtype-name)
   (interned-name :initarg :interned-name
                  :accessor qtype-interned-name)
   (stack-item-slot :initarg :stack-item-slot
                    :accessor qtype-stack-item-slot)
   (kind :initarg :kind
         :accessor qtype-kind)
   (constp :initarg :constp
           :accessor qtype-constp)))

(defmethod print-object ((instance qtype) stream)
  (print-unreadable-object (instance stream :type t :identity nil)
    (format stream "(~A) kind: ~A, stack: ~A~@[, class: ~A~]"
            (qtype-name instance)
            (qtype-kind instance)
            (qtype-stack-item-slot instance)
            (qtype-class instance))))

(defmethod print-object ((instance qmethod) stream)
  (print-unreadable-object (instance stream :type t :identity nil)
    (format stream "~A.~A"
            (qclass-name (qmethod-class instance))
            (qmethod-name instance))))

(defun parse-qclass (id struct)
  (cffi:with-foreign-slots ((classname enumfn flags classfn parents
                                       external)
                            struct |struct Class|)
    (if (zerop external)
        (let ((parsed-flags '()))
          (flet ((flag (symbol mask)
                   (when (logtest mask flags)
                     (push symbol parsed-flags))))
            (flag :constructor #x01)
            (flag :deepcopy #x02)
            (flag :virtual #x04)
            (flag :undefined #x08))
          (make-instance 'qclass
                         :id id
                         :struct struct
                         :name classname
                         :enum-fun enumfn
                         :trampoline-fun classfn
                         :flags parsed-flags))
        (make-instance 'external-qclass
                       :id id
                       :struct struct))))

(defun parse-qclass-parents (qclass struct inheritancelist)
  (cffi:with-foreign-slots ((parents) struct |struct Class|)
    (setf (qclass-superclasses qclass)
          (loop
             for i from parents
             for classid = (cffi:mem-aref inheritancelist :short i)
             while (plusp classid)
             collect (elt *class-table* classid)))))

(defun parse-qmethod (id struct method-names argumentlist)
  (cffi:with-foreign-slots
      ((name classid ret args numargs flags methodForClassFun)
       struct |struct Method|)
    (let ((parsed-args
           (loop
              for i from args
              repeat numargs
              collect
              (let ((typeid (cffi:mem-aref argumentlist :short i)))
                (elt *type-table* typeid))))
          (parsed-flags '()))
      (flet ((flag (symbol mask)
               (when (logtest mask flags)
                 (push symbol parsed-flags))))
        (flag :static #x01)
        (flag :const #x02)
        (flag :copyctor #x04)
        (flag :internal #x08)
        (flag :enum #x10)
        (flag :ctor #x20)
        (flag :dtor #x40)
        (flag :protected #x80))
      (make-instance 'qmethod
                     :id id
                     :class (elt *class-table* classid)
                     :struct struct
                     :name (elt method-names name)
                     :return-type (elt *type-table* ret)
                     :argument-types parsed-args
                     :flags parsed-flags
                     :method-arg-for-classfn methodForClassFun))))

(defun parse-qprototype (struct method-names ambiguous-methods)
  (cffi:with-foreign-slots ((name classid methodid) struct |struct MethodMap|)
    (flet ((get-method (id)
             (elt *method-table* id)))
      (let ((methods
             (if (plusp methodid)
                 (list (get-method methodid))
                 (loop
                    for i from (- methodid)
                    for id = (cffi:mem-aref ambiguous-methods :short i)
                    while (plusp id)
                    collect (get-method id)))))
        (make-instance 'qprototype
                       :class (elt *class-table* classid)
                       :methods methods
                       :name (elt method-names name))))))

(defun parse-qtype (id struct)
  (cffi:with-foreign-slots ((name classid flags)
                            struct |struct Type|)
    (make-instance 'qtype
                   :id id
                   :class (elt *class-table* classid)
                   :name name
                   :interned-name (intern name :keyword)
                   :stack-item-slot (elt #(ptr bool char uchar short
                                           ushort int uint long ulong
                                           float double enum class)
                                         (logand #xf flags))
                   :kind (case (logand #x30 flags)
                           (#x10 :stack)
                           (#x20 :pointer)
                           (#x30 :reference))
                   :constp (logtest #x40 flags))))

(defun build-hash-prototypes! (class)
  (let ((table (make-hash-table :test 'equal)))
    (setf (qclass-hashed-prototypes class) table)
    (dolist (map (qclass-prototypes class))
      (let ((any-method (car (qprototype-methods map))))
        (when any-method
          (let* ((a (qmethod-name any-method))
                 (b (qprototype-name map))
                 (n (length (qmethod-name any-method)))
                 (m (length (qprototype-name map)))
                 (key
                  (cons a
                        (loop
                           for i from n below m
                           collect (ecase (elt b i)
                                     (#\$ '$)
                                     (#\# 'qobject)
                                     (#\? '?))))))
            (setf (gethash key table)
                  (qprototype-methods map))))))))

(defun qapropos (str)
  (setf str (string-upcase str))
  (map nil
       (lambda (class)
         (when (and class
                    (search str (string-upcase (qclass-name class))))
           (format t "Class ~A~%" (qclass-name class))))
       *class-table*)
  (map nil
       (lambda (method)
         (when (and method
                    (search str (string-upcase (qmethod-name method))))
           (format t "Method ~A~%" (qmethod-fancy-name method))))
       *method-table*))

(defun find-qclass-ignoring-case (str)
  (find str
        *class-table*
        :start 1
        :test #'string-equal
        :key #'qclass-name))

(defun qmethod-dotted-name (method)
  (format nil "~A.~A"
          (qclass-name (qmethod-class method))
          (qmethod-name method)))

(defun qmethod-fancy-name (method)
  (format nil "~A.~A [~D]"
          (qclass-name (qmethod-class method))
          (qmethod-name method)
          (qmethod-id method)))

(defun find-dotted-qmethods (str)
  (coerce (remove-if-not (lambda (method)
                           (and method
                                (string-equal (qmethod-dotted-name method)
                                              str)))
                         *method-table*)
          'list))

(defun describe-qclass-methods (class)
  (dolist (mminfo (qclass-prototypes class))
    (let ((methods (qprototype-methods mminfo)))
      (cond
        ((null methods)
         ;; fixme?
         )
        ((cdr methods)
         (format t "    ~A~30Tambiguous:~%"
                 (qprototype-name mminfo))
         (dolist (method methods)
           (format t "    ~34T~A:~%"
                   (qmethod-fancy-name method))))
        (t
         (format t "    ~A~30T~A~%"
                 (qprototype-name mminfo)
                 (qmethod-fancy-name (car methods))))))))

(defun describe-qclass (class &optional inherited)
  (format t "~A is a smoke class~%~%" class)
  (format t "    name: ~A~%" (qclass-name class))
  (format t "    flags:~{ ~A~^,~}~%" (qclass-flags class))
  (format t "~%Superclasses:~%")
  (if (qclass-superclasses class)
      (labels ((recurse (c indent)
                 (dolist (d (qclass-superclasses c))
                   (format t "~vT~A~%" indent (qclass-name d))
                   (recurse d (+ indent 4)))))
        (recurse class 4))
      (format t "    (none)~%"))
  (format t "~%Methods:~%")
  (describe-qclass-methods class)
  (let ((superclasses (qclass-superclasses class)))
    (when superclasses
      (cond
        (inherited
         (format t "~%Inherited methods:~%")
         (labels ((recurse (c)
                    (dolist (d (qclass-superclasses c))
                      (describe-qclass-methods d)
                      (recurse d))))
           (recurse class)))
        (t
         (format t "~%Use (QDESCRIBE ~S T) to see inherited methods.~%"
                 (qclass-name class))))))
  (describe-qclass-properties class inherited))

(defun describe-qmethod (method)
  (format t "~A is a smoke method~%" method)
  (format t "    class: ~A~%" (qmethod-class method))
  (format t "    name: ~A~%" (qmethod-name method))
  (format t "    return type: ~A~%" (qmethod-return-type method))
  (format t "    flags:~{ ~A~^,~}~%" (qmethod-flags method))
  (format t "  argument types:~%")
  (if (qmethod-argument-types method)
      (dolist (type (qmethod-argument-types method))
        (format t "    ~A~%" type))
      (format t "    (none)~%")))

(defun qdescribe (thing &optional inherited)
  (etypecase thing
    (string
     (let ((newlinep nil))
       (let ((class (find-qclass-ignoring-case thing)))
         (when class
           (setf newlinep t)
           (describe-qclass class inherited)))
       (dolist (method (find-dotted-qmethods thing))
         (if newlinep
             (terpri)
             (setf newlinep t))
         (describe-qmethod method))))
    (null-qobject
     (format t "~A is a null pointer~%" thing))
    (qobject
     (describe-qobject thing))))

(defvar *initialized* nil)
(defvar *cached-objects*)

(defun ensure-loaded ()
  (unless *loaded*
    (setf *initialized* nil)
    (load-smoke-library)))

(defvar *commonqtbinding*)
(defvar *castfn*)

(defun init-smoke ()
  (ensure-loaded)
  (setf *cached-objects* (make-hash-table))
  (cffi:with-foreign-object (data '|struct SmokeData|)
    (setf *commonqtbinding*
          (sw_init data (cffi:callback method-invocation-callback)))
    (cffi:with-foreign-slots (( ;;
                               nmethodmaps methodmaps
                               nclasses classes
                               nmethods methods
                               nmethodnames methodnames
                               ntypes types
                               argumentlist
                               inheritancelist
                               ambiguousmethodlist
                               castfn)
                              data |struct SmokeData|)
      (setf *castfn* castfn)
      (let ((qclasses (make-array (1+ nclasses) :initial-element nil))
            (method-names (make-array (1+ nmethodnames) :initial-element nil))
            (qmethods (make-array nmethods :initial-element nil))
            (qtypes (make-array (1+ ntypes) :initial-element nil)))
        (setf *class-table* qclasses)
        (setf *method-table* qmethods)
        (setf *type-table* qtypes)
        (loop for i from 1 to nclasses do
             (setf (elt qclasses i)
                   (parse-qclass
                    i
                    (cffi:mem-aref classes '|struct Class| i))))
        (loop for i from 1 to nclasses do
             (parse-qclass-parents (elt qclasses i)
                                   (cffi:mem-aref classes '|struct Class| i)
                                   inheritancelist))
        (loop for i from 1 to ntypes do
             (setf (elt qtypes i)
                   (parse-qtype
                    i
                    (cffi:mem-aref types '|struct Type| i))))
        (loop for i from 0 below nmethodnames do
             (setf (elt method-names i)
                   (cffi:mem-aref methodnames :string i)))
        (loop for i from 1 below nmethods do
             (setf (elt qmethods i)
                   (parse-qmethod
                    i
                    (cffi:mem-aref methods '|struct Method| i)
                    method-names
                    argumentlist)))
        (loop for i from 1 below nmethodmaps do
             (let ((mminfo
                    (parse-qprototype
                     (cffi:mem-aref methodmaps '|struct MethodMap| i)
                     method-names
                     ambiguousmethodlist)))
               (push mminfo
                     (qclass-prototypes
                      (qprototype-class mminfo)))))
        (loop for i from 1 to nclasses do
             (let ((class (elt qclasses i)))
               (build-hash-prototypes! class))))))
  (setf *initialized* t))

(defun ensure-smoke ()
  (ensure-loaded)
  (unless *initialized*
    (init-smoke)))
