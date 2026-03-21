;;; TutorCastPlugin.lsp
;;; TutorCast AutoCAD for Mac — AutoLISP Fallback Plugin
;;;
;;; Registers command reactors and sends events to TutorCast.
;;; Works with AutoCAD 2019+ for Mac.
;;;
;;; Installation:
;;; 1. Copy this file to: ~/Library/Application Support/Autodesk/AutoCAD <version>/Support/
;;; 2. Load via acaddoc.lsp: (load "TutorCastPlugin")
;;;    or manually: (load "/path/to/TutorCastPlugin")
;;;
;;; Transport: Newline-delimited JSON written to /tmp/tutorcast_event.json
;;; TutorCast monitors this file via FSEvents for changes.

;;; ============================================================================
;;; CONFIGURATION
;;; ============================================================================

(setq tutorcast-event-file "/tmp/tutorcast_event.json")
(setq tutorcast-debug nil)  ; Set to T for console logging


;;; ============================================================================
;;; EVENT SERIALIZATION
;;; ============================================================================

(defun tutorcast-format-timestamp ()
  "Format current time as ISO 8601 UTC string (YYYY-MM-DDTHH:MM:SSZ)."
  (let ((date-str (menucmd "M=$(edtime,$(getvar,DATE),YYYY-MM-DD HH:MM:SS)")))
    (if date-str
      (strcat (substr date-str 1 10) "T" (substr date-str 12 8) "Z")
      ""
    )
  )
)

(defun tutorcast-json-escape-string (str)
  "Escape special characters in a string for JSON."
  (if (null str) ""
    (progn
      (setq str (vl-string-subst "\\\"" "\"" str))
      (setq str (vl-string-subst "\\\\" "\\" str))
      (setq str (vl-string-subst "\\n" (chr 10) str))
      (setq str (vl-string-subst "\\r" (chr 13) str))
      str
    )
  )
)

(defun tutorcast-build-event (type cmd-name subcommand / json)
  "Build a JSON event object.
   Args:
     type - Event type string (e.g., 'commandStarted')
     cmd-name - Command name (e.g., 'LINE')
     subcommand - Subcommand/prompt text (nil for command events)
   Returns: JSON string"
  
  (setq json "{")
  (setq json (strcat json "\"type\":\"" type "\","))
  (setq json (strcat json "\"commandName\":\"" (strcase (tutorcast-json-escape-string cmd-name)) "\","))
  
  (if subcommand
    (setq json (strcat json "\"subcommand\":\"" (tutorcast-json-escape-string subcommand) "\","))
    (setq json (strcat json "\"subcommand\":null,"))
  )
  
  (setq json (strcat json "\"activeOptions\":null,"))
  (setq json (strcat json "\"selectedOption\":null,"))
  (setq json (strcat json "\"rawCommandLineText\":null,"))
  (setq json (strcat json "\"timestamp\":\"" (tutorcast-format-timestamp) "\","))
  (setq json (strcat json "\"source\":\"nativePlugin\""))
  (setq json (strcat json "}"))
  
  json
)

(defun tutorcast-write-event (json-str)
  "Write event JSON to file."
  (let ((fp (open tutorcast-event-file "w")))
    (if fp
      (progn
        (write-line json-str fp)
        (close fp)
        (if tutorcast-debug (print (strcat "[TutorCast] Event written: " json-str)))
        T
      )
      (print "[TutorCast] ERROR: Could not write to event file")
    )
  )
)

(defun tutorcast-send-event (type cmd-name subcommand)
  "Build and send an event to TutorCast."
  (let ((json (tutorcast-build-event type cmd-name subcommand)))
    (tutorcast-write-event json)
  )
)


;;; ============================================================================
;;; COMMAND REACTOR CALLBACKS
;;; ============================================================================

(defun tutorcast-cmd-will-start (reactor cmd-list / cmd)
  "Reactor callback: command is about to start."
  (setq cmd (car cmd-list))
  (tutorcast-send-event "commandStarted" cmd nil)
)

(defun tutorcast-cmd-ended (reactor cmd-list / cmd)
  "Reactor callback: command completed normally."
  (setq cmd (car cmd-list))
  (tutorcast-send-event "commandCompleted" cmd nil)
)

(defun tutorcast-cmd-cancelled (reactor cmd-list / cmd)
  "Reactor callback: command was cancelled (ESC or error)."
  (setq cmd (car cmd-list))
  (tutorcast-send-event "commandCancelled" cmd nil)
)


;;; ============================================================================
;;; REACTOR REGISTRATION
;;; ============================================================================

(defun c:TUTORCAST-REACTOR-SETUP ()
  "Register TutorCast command reactors.
   Call this once to enable monitoring for the current session.
   Add to acad.lsp or acaddoc.lsp to auto-load."
  
  (vlr-command-reactor nil
    '(
      (:vlr-commandWillStart . tutorcast-cmd-will-start)
      (:vlr-commandEnded     . tutorcast-cmd-ended)
      (:vlr-commandCancelled . tutorcast-cmd-cancelled)
    )
  )
  
  (if tutorcast-debug
    (print "\n[TutorCast] Reactor registered and monitoring commands")
    (princ "\n[TutorCast] Reactor registered\n")
  )
  
  (princ)
)


;;; ============================================================================
;;; AUTO-LOAD SETUP
;;; ============================================================================

;;; Auto-register on plugin load
;;; Uncomment below if loading this file automatically via acaddoc.lsp

;(if (not tutorcast-reactor-loaded)
;  (progn
;    (c:TUTORCAST-REACTOR-SETUP)
;    (setq tutorcast-reactor-loaded T)
;  )
;)

;;; For manual testing:
(c:TUTORCAST-REACTOR-SETUP)

(print "\n[TutorCast] Plugin loaded. Command monitoring active.")
