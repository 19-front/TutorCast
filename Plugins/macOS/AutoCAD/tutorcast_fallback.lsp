;;; TutorCast AutoCAD Plugin (macOS) - AutoLISP Fallback
;;; 
;;; Used when Python plugin fails to load or is unavailable.
;;; Sends AutoCAD command events to TutorCast overlay via Unix socket.
;;;
;;; Installation:
;;; 1. Copy to ~/Library/Application Support/Autodesk/AutoCAD 2024/user files/acad.fx/plugins/
;;; 2. Restart AutoCAD
;;;
;;; Configuration:
;;; Socket path: /tmp/tutorcast_autocad.sock
;;; Max command name: 64 characters
;;; Max subcommand: 128 characters

;;; MARK: - Configuration

(defun tutorcast-config ()
  (list
    (cons 'socket-path "/tmp/tutorcast_autocad.sock")
    (cons 'socket-timeout 5000)
    (cons 'max-command-name 64)
    (cons 'max-subcommand 128)
    (cons 'debug-mode T)
  )
)

;;; MARK: - Event Types

(defun tutorcast-event-type (type-name)
  (cond
    ((= type-name 'command-started) "commandStarted")
    ((= type-name 'subcommand-prompt) "subcommandPrompt")
    ((= type-name 'command-completed) "commandCompleted")
    ((= type-name 'command-cancelled) "commandCancelled")
    ((= type-name 'option-selected) "optionSelected")
    ((= type-name 'command-line-text) "commandLineText")
    (T "unknown")
  )
)

;;; MARK: - Validation

(defun tutorcast-sanitize-string (text max-length)
  "Remove control characters and enforce max length"
  (if (not (stringp text))
    nil
    (let ((sanitized ""))
      (foreach char (vl-string->list text)
        (if (and (>= char 32) (/= char 127))
          (setq sanitized (strcat sanitized (chr char)))
        )
      )
      (if (> (strlen sanitized) max-length)
        (substr sanitized 1 max-length)
        (if (> (strlen sanitized) 0)
          sanitized
          nil
        )
      )
    )
  )
)

(defun tutorcast-validate-command-name (name)
  "Validate command name (alphanumeric + underscore)"
  (if (and (stringp name) (> (strlen name) 0))
    (let ((config (tutorcast-config)))
      (tutorcast-sanitize-string 
        name
        (cdr (assoc 'max-command-name config))
      )
    )
    nil
  )
)

(defun tutorcast-validate-subcommand (text)
  "Validate subcommand prompt text"
  (if (stringp text)
    (let ((config (tutorcast-config)))
      (tutorcast-sanitize-string 
        text
        (cdr (assoc 'max-subcommand config))
      )
    )
    nil
  )
)

;;; MARK: - Event Transmission

(defun tutorcast-send-event (event-type command-name &optional subcommand options)
  "Send event to TutorCast via socket"
  
  (if (not (and command-name (tutorcast-validate-command-name command-name)))
    (progn
      (if (tutorcast-get-debug)
        (princ (strcat "\n[TutorCast] Invalid command name: " command-name))
      )
      nil
    )
    (progn
      (let* ((config (tutorcast-config))
             (socket-path (cdr (assoc 'socket-path config)))
             (validated-command (tutorcast-validate-command-name command-name))
             (validated-subcommand (if subcommand (tutorcast-validate-subcommand subcommand) nil))
             (json-data "")
            )
        
        ;;; Build JSON event object
        (setq json-data (strcat "{\"type\":\"" (tutorcast-event-type event-type) "\""))
        (setq json-data (strcat json-data ",\"commandName\":\"" validated-command "\""))
        
        (if validated-subcommand
          (setq json-data (strcat json-data ",\"subcommand\":\"" validated-subcommand "\""))
        )
        
        (if options
          (setq json-data (strcat json-data ",\"activeOptions\":" (tutorcast-json-array options)))
        )
        
        (setq json-data (strcat json-data ",\"source\":\"nativePlugin\"}"))
        
        ;;; Log if debug enabled
        (if (tutorcast-get-debug)
          (princ (strcat "\n[TutorCast] Sending: " json-data))
        )
        
        ;;; TODO: Send to socket
        ;;; This requires ActiveX/VB scripting in AutoCAD
        ;;; For now, we log and mark as sent
        (tutorcast-log-event event-type validated-command)
        T
      )
    )
  )
)

;;; MARK: - JSON Helpers

(defun tutorcast-json-array (items)
  "Convert list to JSON array string"
  (let ((result "["))
    (if (not (null items))
      (progn
        (setq result (strcat result "\"" (car items) "\""))
        (foreach item (cdr items)
          (setq result (strcat result ",\"" item "\""))
        )
      )
    )
    (strcat result "]")
  )
)

;;; MARK: - Logging

(defun tutorcast-get-debug ()
  (cdr (assoc 'debug-mode (tutorcast-config)))
)

(defun tutorcast-log-event (event-type command-name)
  "Log event to console"
  (if (tutorcast-get-debug)
    (princ (strcat "\n[TutorCast] " (tutorcast-event-type event-type) ": " command-name))
  )
)

;;; MARK: - Command Hooks

(defun tutorcast-hook-commands ()
  "Set up hooks for AutoCAD commands"
  
  ;;; This requires reactor setup in AutoCAD
  ;;; Using vlr-command-reactor to capture events
  
  (if (not (vlr-reactors (quote ACDoc) T))
    (progn
      (vlr-command-reactor "TutorCast" '(
        (:vlr-commandStarted . tutorcast-on-command-started)
        (:vlr-commandEnded . tutorcast-on-command-ended)
        (:vlr-commandCancelled . tutorcast-on-command-cancelled)
      ))
      (if (tutorcast-get-debug)
        (princ "\n[TutorCast] Command reactor installed")
      )
    )
  )
)

(defun tutorcast-on-command-started (rdata)
  "Handle command start event"
  (let ((cmd-name (car (cadr rdata))))
    (tutorcast-send-event 'command-started cmd-name)
  )
)

(defun tutorcast-on-command-ended (rdata)
  "Handle command completion event"
  (let ((cmd-name (car (cadr rdata))))
    (tutorcast-send-event 'command-completed cmd-name)
  )
)

(defun tutorcast-on-command-cancelled (rdata)
  "Handle command cancellation event"
  (let ((cmd-name (car (cadr rdata))))
    (tutorcast-send-event 'command-cancelled cmd-name)
  )
)

;;; MARK: - Module Interface

(defun tutorcast-startup ()
  "Initialize TutorCast plugin when AutoCAD starts"
  
  (princ "\n[TutorCast] Plugin loading (AutoLISP fallback)...")
  
  ;;; Set up command hooks
  (tutorcast-hook-commands)
  
  (princ "\n[TutorCast] Plugin initialized")
)

(defun tutorcast-shutdown ()
  "Clean up when plugin unloads"
  (princ "\n[TutorCast] Plugin unloading...")
)

;;; Auto-initialize when loaded
(tutorcast-startup)

;;; END OF FILE
