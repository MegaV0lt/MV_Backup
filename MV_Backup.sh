#!/bin/bash
# = = = = = = = = = = = = =  MV_Backup.sh - RSYNC BACKUP  = = = = = = = = = = = = = = = #
#                                                                                       #
# Author: MegaV0lt, http://j.mp/cQIazU                                                  #
# Forum: http://j.mp/1TblNNj  GIT: http://j.mp/2deM7dk                                  #
# Basiert auf dem RSYNC-BACKUP-Skript von JaiBee (Siehe HISTORY)                        #
#                                                                                       #
# Alle Anpassungen zum Skript, kann man in der HISTORY und in der .conf nachlesen. Wer  #
# sich erkenntlich zeigen möchte, kann mir gerne einen kleinen Betrag zukommen lassen:  #
# => http://paypal.me/SteBlo <= Der Betrag kann frei gewählt werden.                    #
#                                                                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
VERSION=171126

# Dieses Skript sichert / synchronisiert Verzeichnisse mit rsync.
# Dabei können beliebig viele Profile konfiguriert oder die Pfade direkt an das Skript übergeben werden.
# Eine kurze Anleitung kann mit der Option -h aufgerufen werden.

# Sämtliche Einstellungen werden in der *.conf vorgenommen.
# ---> Bitte ab hier nichts mehr ändern! <---
if ((BASH_VERSINFO[0] < 4)) ; then  # Test, ob min. Bash Version 4.0
  echo 'Sorry, dieses Skript benötigt Bash Version 4.0 oder neuer!' >&2 ; exit 1
fi

# Skriptausgaben zusätzlich in Datei speichern. (DEBUG)
# exec > >(tee -a /var/log/MV_Backup.log) 2>&1

# --- INTERNE VARIABLEN ---
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"                          # skript.sh
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/${SELF_NAME%.*}.XXXX")"  # Ordner für temporäre Dateien
declare -a _RSYNC_OPT ERRLOGS LOGFILES RSYNCRC RSYNCPROF UNMOUNT  # Einige Array's
declare -A _arg _target _JOBS  # Array _JOBS wird für den Multi rsync-Modus benötigt
msgERR='\e[1;41m FEHLER! \e[0;1m'  # Anzeige "FEHLER!"
msgINF='\e[42m \e[0m' ; msgWRN='\e[103m \e[0m'  # " " mit grünem/gelben Hintergrund

# --- FUNKTIONEN ---
trap 'f_exit 3' SIGHUP SIGINT SIGQUIT SIGABRT  # Bei unerwarteten Ende (Strg-C) aufräumen
set -o errtrace  # ERR Trap auch in Funktionen

f_errtrap() {  # ERR-Trap mit "ON" aktivieren, ansonsten nur ins ERRLOG
  if [[ "${1^^}" == 'ON' ]] ; then
    trap 'f_exit 2 "$BASH_COMMAND" "$LINENO" ${FUNCNAME:-$BASH_SOURCE} $?' ERR  # Bei Fehlern und nicht gefundenen Programmen
  else  # ERR-Trap nur loggen
    trap 'echo "=> Info (Fehler $?) in Zeile "$LINENO" (${FUNCNAME:-$BASH_SOURCE}): $BASH_COMMAND" >> "${ERRLOG:-/tmp/${SELF_NAME%.*}.log}"' ERR
  fi
}

f_exit() {  # Beenden und aufräumen $1 = ExitCode
  local EXIT="${1:-0}"  # Wenn leer, dann 0
  [[ "$EXIT" -eq 5 ]] && echo -e "$msgERR Ungültige Konfiguration! (\"${CONFIG}\") $2"
  if [[ "$EXIT" -eq 3 ]] ; then  # Strg-C
    echo -e "\n=> Aufräumen und beenden [$$]"
    [[ -n "$POST_ACTION" ]] && echo 'Achtung: POST_ACTION wird nicht ausgeführt!'
    [[ -n "$MAILADRESS" ]] && echo 'Achtung: Es erfolgt kein eMail-Versand!'
  fi
  [[ "$EXIT" -eq 2 ]] && echo -e "$msgERR (${5:-x}) in Zeile $3 ($4):\e[0m\n$2\n" >&2
  if [[ "$EXIT" -ge 1 ]] ; then
    set -o posix ; set  > "/tmp/${SELF_NAME%.*}.env"  # Variablen speichern
    [[ $EUID -ne 0 ]] && echo -e "$msgWRN Skript ohne root-Rechte gestartet!"
  fi
  [[ -n "${exfrom[*]}" ]] && rm "${exfrom[@]}" &>/dev/null
  [[ -d "$TMPDIR" ]] && rm --recursive --force "$TMPDIR" &>/dev/null  # Ordner für temporäre Dateien
  [[ -n "$MFS_PID" ]] && f_mfs_kill  # Hintergrundüberwachung beenden
  [[ "$EXIT" -ne 4 ]] && rm --force "$PIDFILE" &>/dev/null  # PID-Datei entfernen
  exit "$EXIT"
}

f_mfs_kill() {  # Beenden der Hintergrundüberwachung
  echo -e "$msgINF Beende Hintergrundüberwachung…"
  kill "$MFS_PID" &>/dev/null  # Hintergrundüberwachung beenden
  if ps --pid "$MFS_PID" &>/dev/null ; then  # Noch aktiv!
    echo '!> Hintergrundüberwachung konnte nicht beendet werden! Versuche erneut…'
    kill -9 "$MFS_PID" &>/dev/null  # Hintergrundüberwachung beenden
  else
    unset -v 'MFS_PID'
  fi
}

f_remove_slash() {  # "/" am Ende entfernen. $1=Variablenname ohne $
  local __retval="$1" tmp="${!1}"  # $1=NAME, ${!1}=Inhalt
  [[ ${#tmp} -ge 2 && "${tmp: -1}" == '/' ]] && tmp="${tmp%/}"
  eval "$__retval='$tmp'"  # Ergebis in Variable aus $1
}

# Wird in der Konsole angezeigt, wenn eine Option nicht angegeben oder definiert wurde
f_help() {
  echo -e "Aufruf: \e[1m$0 \e[34m-p\e[0m \e[1;36mARGUMENT\e[0m [\e[1;34m-p\e[0m \e[1;36mARGUMENT\e[0m]"
  echo -e "        \e[1m$0 \e[34m-m\e[0m \e[1;36mQUELLE(n)\e[0m \e[1;36mZIEL\e[0m"
  echo
  echo -e '\e[37;100m Erforderlich \e[0m'
  for i in "${!arg[@]}" ; do
    echo -e "  \e[1;34m-p\e[0m \e[1;36m${arg[i]}\e[0m\tProfil \"${title[i]}\""
  done
  echo -e ' oder\n  \e[1;34m-a\e[0m\tAlle Sicherungs-Profile'
  echo -e ' oder\n  \e[1;34m-m\e[0m\tVerzeichnisse manuell angeben'
  echo
  echo -e '\e[37;100m Optional \e[0m'
  echo -e '  \e[1;34m-c\e[0m \e[1;36mBeispiel.conf\e[0m Konfigurationsdatei angeben (Pfad und Name)'
  echo -e '  \e[1;34m-e\e[0m \e[1;36mmy@email.de\e[0m   Sendet eMail inkl. angehängten Log(s)'
  echo -e '  \e[1;34m-f\e[0m    eMail nur senden, wenn Fehler auftreten (-e muss angegeben werden)'
  echo -e '  \e[1;34m-d\e[0m \e[1;36mx\e[0m  Sicherungs-Dateien die älter als x Tage sind löschen'
  echo -e '  \e[1;34m-s\e[0m    Nach Beendigung automatisch herunterfahren (benötigt u. U. Root-Rechte)'
  echo -e '  \e[1;34m-h\e[0m    Hilfe anzeigen'
  echo
  echo -e '\e[37;100m Optional \e[37;1m[Achtung] \e[0m'
  echo -e '  \e[1;34m--del-old-source\e[0m \e[1;36mx\e[0m  Alte Dateien in der \e[1mQuelle\e[0m die älter als x Tage sind löschen'
  echo
  echo -e '\e[37;100m Beispiele \e[0m'
  echo -e "  \e[32mProfil \"${title[2]}\"\e[0m starten und den Computer anschließend \e[31mherunterfahren\e[0m:"
  echo -e "\t$0 \e[32m-p${arg[2]}\e[0m \e[31m-s\e[0m\n"
  echo -e '  \e[33m"/tmp/Quelle1/"\e[0m und \e[35m"/Leer zeichen2/"\e[0m mit \e[36m"/media/extern"\e[0m synchronisieren;\n  anschließend \e[31mherunterfahren\e[0m:'
  echo -e "\t$0 \e[31m-s\e[0;4mm\e[0m \e[33m/tmp/Quelle1\e[0m \e[4m\"\e[0;35m/Leer zeichen2\e[0;4m\"\e[0m \e[36m/media/extern\e[0m"
  f_exit 1
}

f_settings() {
  local notset='\e[1;41m -LEER- \e[0m'  # Anzeige, wenn nicht gesetzt
  if [[ "$PROFIL" != 'customBak' ]] ; then
    # Benötigte Werte aus dem Array (.conf) holen
    for i in "${!arg[@]}" ; do  # Anzahl der vorhandenen Profile ermitteln
      if [[ "${arg[i]}" == "$PROFIL" ]] ; then  # Wenn das gewünschte Profil gefunden wurde
        # RSYNC_OPT, RSYNC_OPT_SNAPSHOT und MOUNT wieder herstelen
        [[ -n "${_RSYNC_OPT[*]}" ]] && { RSYNC_OPT=("${_RSYNC_OPT[@]}") ; unset -v '_RSYNC_OPT' ;}
        [[ -n "$_RSYNC_OPT_SNAPSHOT" ]] && { RSYNC_OPT_SNAPSHOT=("${_RSYNC_OPT_SNAPSHOT[@]}") ; unset -v '_RSYNC_OPT_SNAPSHOT' ;}
        [[ -n "$_MOUNT" ]] && { MOUNT="$_MOUNT" ; unset -v '_MOUNT' ;}
        [[ "$MOUNT" == '0' ]] && unset -v 'MOUNT'  # MOUNT war nicht gesetzt
        TITLE="${title[i]}"   ; ARG="${arg[i]}"       ; MODE="${mode[i]}"
        SOURCE="${source[i]}" ; FTPSRC="${ftpsrc[i]}" ; FTPMNT="${ftpmnt[i]}"
        TARGET="${target[i]}" ; LOG="${log[i]}"       ; SAVE_ACL="${save_acl[i]}"
        EXFROM="${exfrom[i]}" ; MINFREE="${minfree[i]}" ; SKIP_FULL="${skip_full[i]}"
        DRY_RUN="${dry_run[i]}" ; MINFREE_BG="${minfree_bg[i]}"
        # Variablen für die Extra Sicherung
        EXTRA_MOUNT="${extra_mount[i]}"   ; EXTRA_TARGET="${extra_target[i]}"
        EXTRA_MAXBAK="${extra_maxbak[i]}" ; EXTRA_MAXINC="${extra_maxinc[i]}"
        EXTRA_ARCHIV="${extra_archiv[i]}"
        # Erforderliche Werte prüfen, und ggf. Vorgaben setzen
        if [[ -z "$SOURCE" || -z "$TARGET" ]] ; then
          echo -e "$msgERR Quelle und/oder Ziel sind nicht konfiguriert!\e[0m" >&2
          echo -e " Profil:    \"${TITLE:-$notset}\"\n Parameter: \"${ARG:-$notset}\" (Nummer: $i)"
          echo -e " Quelle:    \"${SOURCE:-$notset}\"\n Ziel:      \"${TARGET:-$notset}\"" ; f_exit 1
        fi
        if [[ -n "$FTPSRC" && -z "$FTPMNT" ]] ; then
          echo -e "$msgERR FTP-Quelle und Einhängepunkt falsch konfiguriert!\e[0m" >&2
          echo -e " Profil:        \"${TITLE:-$notset}\"\n Parameter:     \"${ARG:-$notset}\" (Nummer: $i)"
          echo -e " FTP-Quelle:    \"${FTPSRC:-$notset}\"\n Einhängepunkt: \"${FTPMNT:-$notset}\"" ; f_exit 1
        fi
        if [[ -n "$DEL_OLD_SOURCE" && "${#P[@]}" -ne 1 ]] ; then
          echo -e "$msgERR \"--del-old-source\" kann nicht mit mehreren Profilen verwendet werden!\e[0m" >&2
          f_exit 1
        fi
        if [[ -n "$MINFREE" && -n "$MINFREE_BG" ]] ; then
          echo -e "$msgERR minfree und minfree_bg sind gesetzt! Bitte nur einen Wert verwenden!\e[0m" >&2
          echo -e " Profil:     \"${TITLE:-$notset}\"\n Parameter:  \"${ARG:-$notset}\" (Nummer: $i)"
          echo -e " MINFREE:    \"${MINFREE:-$notset}\"\n MINFREE_BG: \"${MINFREE_BG:-$notset}\"" ; f_exit 1
        fi
        : "${TITLE:=Profil_${ARG}}"  # Wenn Leer, dann Profil_ gefolgt von Parameter
        : "${LOG:=${TMPDIR}/${SELF_NAME%.*}.log}"  # Temporäre Logdatei
        : "${FILES_DIR:=_DATEIEN}"                 # Vorgabe für Sicherungsordner
        if [[ -n "$EXTRA_TARGET}" ]] ; then
          : "${EXTRA_ARCHIV:=tar.xz}" ; : "${EXTRA_MAXBAK:=0}" ; : "${EXTRA_MAXINC:=7}"
        fi
        # Bei mehreren Profilen müssen die Werte erst gesichert und später wieder zurückgesetzt werden
        [[ -n "${mount[i]}" ]] && { _MOUNT="${MOUNT:-0}" ; MOUNT="${mount[i]}" ;}  # Eigener Einhängepunkt
        case "${MODE^^}" in  # ${VAR^^} ergibt Großbuchstaben!
          SNAP*) MODE='S' ; MODE_TXT='Snapshot'
            [[ -n "${rsync_opt[i]}" ]] && { _RSYNC_OPT_SNAPSHOT=("${RSYNC_OPT_SNAPSHOT[@]}") ; RSYNC_OPT_SNAPSHOT=(${rsync_opt[i]}) ;}
          ;;
          M*) MODE='M' ; MODE_TXT='Multi rsync'  # Verwendet rsync-Optionen aus dem "normalen" Modus
            [[ -n "${rsync_opt[i]}" ]] && { _RSYNC_OPT=("${RSYNC_OPT[@]}") ; RSYNC_OPT=(${rsync_opt[i]}) ;}
          ;;
          *) MODE='N' ; MODE_TXT='Normal'  # Vorgabe: Normaler Modus
            [[ -n "${rsync_opt[i]}" ]] && { _RSYNC_OPT=("${RSYNC_OPT[@]}") ; RSYNC_OPT=(${rsync_opt[i]}) ;}
          ;;
        esac  # MODE
        [[ -n "$MINFREE_BG" && "$MODE" != 'S' ]] && MODE_TXT+=" + HÜ [${MINFREE_BG} MB]"
      fi
    done
  fi
  return 0
}

f_del_old_backup() {  # Verzeichnisse älter als $DEL_OLD_BACKUP Tage löschen
  local dt
  printf -v dt '%(%F %R.%S)T' || dt="$(date +'%F %R.%S')"
  echo "Lösche Sicherungs-Dateien aus ${1}, die älter als $DEL_OLD_BACKUP Tage sind…"
  { echo "${dt}: Lösche Sicherungs-Dateien aus ${1}, die älter als $DEL_OLD_BACKUP Tage sind…"
    find "$1" -maxdepth 1 -type d -mtime +"$DEL_OLD_BACKUP" -print0 \
      | xargs --null rm --recursive --force --verbose
    # Logdatei(en) löschen (Wenn $TITLE im Namen)
    find "${LOG%/*}" -maxdepth 1 -type f -mtime +"$DEL_OLD_BACKUP" \
      -name "*${TITLE}*" ! -name "${LOG##*/}" -print0 \
        | xargs --null rm --recursive --force --verbose
    [[ -n "$SAVE_ACL" ]] && { find "${SAVE_ACL%/*}" -maxdepth 1 -type f -mtime +"$DEL_OLD_BACKUP" \
      -name "*${TITLE}*" ! -name "${SAVE_ACL##*/}" -print0 \
        | xargs --null rm --recursive --force --verbose ;} || :
  } >> "$LOG"
}

f_del_old_source() {  # Dateien älter als $DEL_OLD_SOURCE Tage löschen ($1=Quelle $2=Ziel)
  local dt file srcdir="$1" targetdir="$2"
  [[ $# -ne 2 ]] && return 1  # Benötigt Quelle und Ziel als Parameter
  cd "$srcdir" || return 1    # Bei Fehler abbruch
  printf -v dt '%(%F %R.%S)T' || dt="$(date +'%F %R.%S')"
  echo "Lösche Dateien aus ${srcdir}, die älter als $DEL_OLD_SOURCE Tage sind…"
  echo "${dt}: Lösche Dateien aus ${srcdir}, die älter als $DEL_OLD_SOURCE Tage sind…" >> "$LOG"
  # Dateien auf Quelle die älter als $DEL_OLD_SOURCE Tage sind einlesen
  mapfile -t < <(find "./" -type f -mtime +"$DEL_OLD_SOURCE")
  # Alte Dateien, die im Ziel sind auf der Quelle löschen
  for i in "${!MAPFILE[@]}" ; do
    file="${MAPFILE[i]/.\/}"  # Führendes "./" entfernen
    if [[ -e "${targetdir}/${file}" ]] ; then
      echo "-> Datei $file in Quelle älter als $DEL_OLD_SOURCE Tage"
    else
      echo "-> Datei $file nicht im Ziel!"  # Sollte nie passieren
      unset -v 'MAPFILE[i]'  # Datei aus der Liste entfernen!
    fi
  done
  printf '%s\n' "${MAPFILE[@]}" # | xargs rm --verbose '{}' >> "$LOG"
  # Leere Ordner älter als $DEL_OLD_SOURCE in Quelle löschen
  find "./" -type d -empty -mtime +"$DEL_OLD_SOURCE" # -delete >> "$LOG"
}

f_countdown_wait() {
  # Länge des Strings [80] plus alle Steuerzeichen [9] (ohne \)
  printf '%-89b' "\n\e[30;46m  Profil \"${TITLE}\" wird in 5 Sekunden gestartet" ; printf '%b\n' '\e[0m'
  echo -e '\e[46m \e[0m Zum Abbrechen [Strg] + [C] drücken\n\e[46m \e[0m Zum Pausieren [Strg] + [Z] drücken (Fortsetzen mit "fg")\n'
  for i in {5..1} ; do  # Countdown ;)
    echo -e -n "\rStart in \e[97;44m  $i  \e[0m Sekunden"
    sleep 1
  done
  echo -e -n '\r' ; "$NOTIFY" "Sicherung startet (Profil: \"${TITLE}\")"
}

f_check_free_space() {  # Prüfen ob auf dem Ziel genug Platz ist
  local DF_LINE DF_FREE DRYLOG MFTEXT='MINFREE' TDATA TRANSFERRED
  if [[ -n "$DRY_RUN" ]] ; then  # In der *.conf angegeben
    DRYLOG="${LOG%.*}.dry.log"  # Extra Log zum Auswerten
    MFTEXT='DRYRUN'
    echo -e "$msgINF Starte rsync Testlauf (DRYRUN)…\n"
    rsync "${RSYNC_OPT[@]}" --dry-run --log-file="$DRYLOG" --exclude-from="$EXFROM" \
      --backup-dir="$BAK_DIR" "${SOURCE}/" "$R_TARGET" >/dev/null 2>> "$ERRLOG"
    TRANSFERRED=($(tail --lines=15 "$DRYLOG" | grep "Total transferred file size:"))
    # echo "Transferiert (DRY-RUN): ${TRANSFERRED[@]}"
    case ${TRANSFERRED[7]} in
      *K) TDATA=${TRANSFERRED[7]%K} ; MINFREE=$((${TDATA%.*}/1024 + 1)) ;;  # 1K-999K
      *M) TDATA=${TRANSFERRED[7]%M} ; MINFREE=$((${TDATA%.*} + 1)) ;;       # MB +1
      *G) TDATA=${TRANSFERRED[7]%G} ; MINFREE=$((${TDATA%.*}*1024 + ${TDATA#*.}0)) ;;
      *T) TDATA=${TRANSFERRED[7]%T} ; MINFREE=$((${TDATA%.*}*1024*1024 + ${TDATA#*.}0*1024)) ;;
      *) MINFREE=1 ;;  # 0-999 Bytes
    esac
  fi
  if [[ $MINFREE -gt 0 ]] ; then  # Aus DRY_RUN oder *.conf
    mapfile -t < <(df -B M "$TARGET")  # Ausgabe von df (in Megabyte) in Array (Zwei Zeilen)
    DF_LINE=(${MAPFILE[1]}) ; DF_FREE="${DF_LINE[3]%M}"  # Drittes Element ist der freie Platz (M)
    if [[ $DF_FREE -lt $MINFREE ]] ; then
      echo -e "msgWRN Auf dem Ziel (${TARGET}) sind nur $DF_FREE MegaByte frei! (${MFTEXT}=${MINFREE})"
      echo "Auf dem Ziel (${TARGET}) sind nur $DF_FREE MegaByte frei! (${MFTEXT}=${MINFREE})" >> "$ERRLOG"
      if [[ -z "$SKIP_FULL" ]] ; then  # In der Konfig definiert
        echo -e "\nDie Sicherung (${TITLE}) ist möglicherweise unvollständig!" >> "$ERRLOG"
        echo -e 'Bitte überprüfen Sie auch die Einträge in den Log-Dateien!\n' >> "$ERRLOG"
      else
        echo -e "\n\n => Die Sicherung (${TITLE}) wird nicht durchgeführt!" >> "$ERRLOG"
        FINISHEDTEXT='abgebrochen!'  # Text wird am Ende ausgegeben
      fi
    else
      [[ -n "$DRYLOG" ]] && echo -e "Testlauf (DRYRUN) von rsync ergab:\nBenötigt: $MINFREE MB Verfügbar: $DF_FREE MB" >> "$LOG"
      unset -v 'SKIP_FULL'  # Genug Platz! Variable löschen, falls gesetzt
    fi  # DF_FREE
  elif [[ $MINFREE_BG -gt 0 ]] ; then  # Prüfung im Hintergrund
    unset -v 'SKIP_FULL'  # Löschen, falls gesetzt
    echo -e -n "$msgINF Starte Hintergrundüberwachung…"
    f_monitor_free_space &  # Prüfen, ob auf dem Ziel genug Platz ist (Hintergrundprozess)
    MFS_PID=$! ; echo " PID: $MFS_PID"  # PID merken
  fi  # MINFREE -gt 0
}

f_monitor_free_space() {  # Prüfen ob auf dem Ziel genug Platz ist (Hintergrundprozess [&])
  local DF_LINE DF_FREE
  while true ; do
    mapfile -t < <(df -B M "$TARGET")  # Ausgabe von df (in Megabyte) in Array (Zwei Zeilen)
    DF_LINE=(${MAPFILE[1]}) ; DF_FREE="${DF_LINE[3]%M}"  # Drittes Element ist der freie Platz (M)
    # echo "-> Auf dem Ziel (${TARGET}) sind $DF_FREE MegaByte frei! (MINFREE_BG=${MINFREE_BG})"
    if [[ $DF_FREE -lt $MINFREE_BG ]] ; then
      touch "${TMPDIR}/.stopflag"  # Für den Multi-rsync-Modus benötigt
      echo -e "$msgWRN Auf dem Ziel (${TARGET}) sind nur $DF_FREE MegaByte frei! (MINFREE_BG=${MINFREE_BG})"
      { echo "Auf dem Ziel (${TARGET}) sind nur $DF_FREE MegaByte frei! (MINFREE_BG=${MINFREE_BG})"
        echo -e "\n\n => Die Sicherung (${TITLE}) wird abgebrochen!" ;} >> "$ERRLOG"
      killall --exact rsync >/dev/null 2>> "$ERRLOG"  # Alle rsync-Prozesse beenden
      if pgrep --exact rsync ; then
        echo 'FEHLER! Es laufen immer noch rsync-Prozesse! Versuche zu beenden…'
        killall --exact --verbose rsync 2>> "$ERRLOG"
      fi
      break  # Beenden der while-Schleife
    fi
    sleep "${MFS_TIMEOUT:-300}"  # Wenn nicht gesetzt, dann 300 Sekunden (5 Min.)
  done
  unset -v 'MFS_PID'  # Hintergrundüberwachung ist beendet
}

f_source_config() {  # Konfiguration laden
  [[ -n "$1" ]] && { source "$1" || f_exit 5 $? ;}
}

# --- START ---
[[ -e "/tmp/${SELF_NAME%.*}.log" ]] && rm --force "/tmp/${SELF_NAME%.*}.log" &>/dev/null
[[ -e "/tmp/${SELF_NAME%.*}.env" ]] && rm --force "/tmp/${SELF_NAME%.*}.env" &>/dev/null
f_errtrap OFF  # Err-Trap deaktivieren und nur loggen
SCRIPT_TIMING[0]=$SECONDS  # Startzeit merken (Sekunden)

# --- AUSFÜHRBAR? ---
if [[ ! -x "$SELF" ]] ; then
  echo -e "$msgWRN Das Skript ist nicht ausführbar!"
  echo 'Bitte folgendes ausführen: chmod +x' "$SELF" ; f_exit 1
fi

# --- LOCKING ---
PIDFILE="/var/run/${SELF_NAME%.*}.pid"
if [[ -f "$PIDFILE" ]] ; then  # PID-Datei existiert
  PID="$(< "$PIDFILE")"        # PID einlesen
  if ps --pid "$PID" &>/dev/null ; then  # Skript läuft schon!
    echo -e "$msgERR Das Skript läuft bereits!\e[0m (PID: $PID)" >&2
    f_exit 4                   # Beenden aber PID-Datei nicht löschen
  else  # Prozess nicht gefunden. PID-Datei überschreiben
    echo "$$" > "$PIDFILE" \
      || { echo -e "$msgWRN Die PID-Datei konnte nicht überschrieben werden!\e[0m" >&2 ;}
  fi
else                           # PID-Datei existiert nicht. Neu anlegen
  echo "$$" > "$PIDFILE" \
    || { echo -e "$msgWRN Die PID-Datei konnte nicht erzeugt werden!\e[0m" >&2 ;}
fi

# --- KONFIGURATION LADEN ---
# Testen, ob Konfiguration angegeben wurde (-c …)
while getopts ":c:" opt ; do
  case "$opt" in
    c) CONFIG="$OPTARG"
       if [[ -f "$CONFIG" ]] ; then  # Konfig wurde angegeben und existiert
         f_source_config "$CONFIG" ; CONFLOADED='Angegebene' ; break
       else
         echo -e "$msgERR Die angegebene Konfigurationsdatei fehlt!\e[0m (\"${CONFIG}\")" >&2
         f_exit 1
       fi
    ;;
    ?) ;;
  esac
done

# Konfigurationsdatei laden [Wenn Skript=MV_Backup.sh Konfig=MV_Backup.conf]
if [[ -z "$CONFLOADED" ]] ; then  # Konfiguration wurde noch nicht geladen
  # Suche Konfig im aktuellen Verzeichnis, im Verzeichnis des Skripts und im eigenen etc
  CONFIG_DIRS=('.' "${SELF%/*}" "${HOME}/etc") ; CONFIG_NAME="${SELF_NAME%.*}.conf"
  for dir in "${CONFIG_DIRS[@]}" ; do
    CONFIG="${dir}/${CONFIG_NAME}"
    if [[ -f "$CONFIG" ]] ; then
      f_source_config "$CONFIG" ; CONFLOADED='Gefundene'
      break  # Die erste gefundene Konfiguration wird verwendet
    fi
  done
  if [[ -z "$CONFLOADED" ]] ; then  # Konfiguration wurde nicht gefunden
    echo -e "$msgERR Keine Konfigurationsdatei gefunden!\e[0m (\"${CONFIG_DIRS[*]}\")" >&2
    f_help
  fi
fi

# Wenn eine grafische Oberfläche vorhanden ist, wird u.a. "notify-send" für Benachrichtigungen verwendet, ansonsten immer "echo"
if [[ -n "$DISPLAY" ]] ; then
  type notify-send-all &>/dev/null && NOTIFY='notify-send-all' || NOTIFY='notify-send'
  WALL='wall'
else
  NOTIFY='echo'
fi

tty --silent && clear
echo -e "\e[44m \e[0;1m MV_Backup (rsync)\e[0m\e[0;32m => Version: ${VERSION}\e[0m by MegaV0lt, http://j.mp/1TblNNj"
echo -e '\e[44m \e[0m Original: 2011 by JaiBee, http://www.321tux.de/'
# Anzeigen, welche Konfiguration geladen wurde!
echo -e "\e[46m \e[0m $CONFLOADED Konfiguration:\e[1m\t${CONFIG}\e[0m\n"
[[ $EUID -ne 0 ]] && echo -e "$msgWRN Skript ohne root-Rechte gestartet!"

# Symlink /dev/fd fehlt bei manchen Systemen (BSD, OpenWRT, ...). http://j.mp/2zwYkoG
if [[ ! -L /dev/fd ]] ; then
  echo -e "$msgWRN Der Symbolische Link \"/dev/fd -> /proc/self/fd\" fehlt!"
  echo -e "$msgINF Erstelle Symbolischen Link \"/dev/fd\"…"
  ln -sf /proc/self/fd /dev/fd || { echo -e "$msgERR Fehler beim erstellen des Symbolischen Links!\e[0m" >&2
    exit 1; }
fi

OPTIND=1  # Wird benötigt, weil getops ein weiteres mal verwendet wird!
optspec=':p:ac:m:sd:e:fh-:'
while getopts "$optspec" opt ; do
  case "$opt" in
    p) for i in $OPTARG ; do        # Bestimmte(s) Profil(e)
         P+=("$i")                  # Profil anhängen
       done
    ;;
    a) P=("${arg[@]}") ;;           # Alle Profile
    c) ;;                           # Wurde beim Start ausgewertet
    m) # Eigene Verzeichnisse an das Skript übergeben
      for i in "$@" ; do            # Letzter Pfad als Zielverzeichnis
        [[ -d "$i" ]] && TARGET="$i"
      done
      for i in "$@" ; do            # Alle übergebenen Verzeichnisse außer $TARGET als Quelle
        if [[ -d "$i" && "$i" != "$TARGET" ]] ; then
          f_remove_slash i          # "/" am Ende entfernen
          MAN_SOURCE+=("$i")        # Verzeichnis anhängen
        fi
      done
      f_remove_slash TARGET         # "/" am Ende entfernen
      P='customBak' ; TITLE='Benutzerdefinierte Sicherung'
      LOG="${TARGET}/${TITLE}_log.txt"
      MOUNT='' ; MODE='N' ; MODE_TXT='Benutzerdefiniert'
    ;;
    s) SHUTDOWN='true' ;;           # Herunterfahren gewählt
    d) DEL_OLD_BACKUP="$OPTARG" ;;  # "Gelöschte Dateien" entfernen (Zahl entspricht Tage, die erhalten bleiben)
    e) MAILADRESS="$OPTARG" ;;      # eMail-Adresse verwenden um Logs zu senden
    f) MAILONLYERRORS='true' ;;     # eMail nur bei Fehlern senden
    h) f_help ;;                    # Hilfe anzeigen
    -) case "$OPTARG" in            # Lange Option (--)
         del-old-source)            # Parameter nach Leerzeichen
           DEL_OLD_SOURCE="${!OPTIND}"; ((OPTIND+=1))
           # echo "Option: --${OPTARG}, Wert: ${DEL_OLD_SOURCE}" >&2;
         ;;
         del-old-source=*)          # Parameter nach "="
           val="${OPTARG#*=}" ; DEL_OLD_SOURCE="${OPTARG%=$val}"
           # echo "Option: --${opt}, Wert: ${DEL_OLD_SOURCE}" >&2
         ;;
         *) if [[ "$OPTERR" == 1 ]] ; then
              echo -e "$msgERR Unbekannte Option: --${OPTARG}\e[0m\n" >&2
              f_help
            fi
         ;;
       esac
       ;;
    *) if [[ "$OPTERR" != 1 || "${optspec:0:1}" == ':' ]] ; then
         echo -e "$msgERR Unbekannte Option: -${OPTARG}\e[0m\n" && f_help
       fi
    ;;
  esac
done

# Wenn $P leer ist, wurde die Option -p oder -a nicht angegeben
if [[ -z "${P[*]}" ]] ; then
  if [[ "${#arg[@]}" -eq 1 ]] ; then  # Wenn nur ein Profil definiert ist, dieses automatisch auswählen
    P=("${arg[@]}")  # Profil zuweisen
    msgAUTO='(auto)'  # Text zur Anzeige
  else
    echo -e "$msgERR Es wurde kein Profil angegeben!\e[0m\n" >&2 ; f_help
  fi
  [[ -z "${arg[*]}" ]] && { echo -e "$msgERR arg[nr] darf nicht leer sein!\e[0m" >&2 ; f_exit 1 ;}
fi

# Prüfen ob alle Profile eindeutige Buchstaben haben (arg[])
for parameter in "${arg[@]}" ; do
  [[ -z "${_arg[$parameter]+_}" ]] && { _arg[$parameter]=1 ;} \
    || { echo -e "$msgERR Profilkonfiguration ist fehlerhaft! (Keine eindeutigen Buchstaben)\n\t\t => arg[nr]=\"$parameter\" <= wird mehrfach verwendet\e[0m\n" >&2 ; f_exit 1 ;}
done

# Prüfen ob alle Profile eindeutige Sicherungsziele verwenden (target[])
for parameter in "${target[@]}" "${extra_target[@]}" ; do
  [[ -z "${_target[$parameter]+_}" ]] && { _target[$parameter]=1 ;} \
    || { echo -e "$msgERR Profilkonfiguration ist fehlerhaft! (Keine eindeutigen Sicherungsziele)\n  => \"$parameter\" <= wird mehrfach verwendet (target[nr] oder extra_target[nr])\e[0m\n" >&2 ; f_exit 1 ;}
done

# Prüfen ob alle Profile POSIX-Kompatible Namen haben
for parameter in "${title[@]}" ; do
  LEN=$((${#parameter}-1)) ; i=0
  while [[ $i -le $LEN ]] ; do
    case "${parameter:$i:1}" in  # Zeichenweises Suchen
      [A-Za-z0-9]|[._-]) ;;  # OK (A-Za-z0-9._-)
        *) NOT_POSIX+=("$parameter") ; continue 2 ;;
    esac ; ((i+=1))
  done  # while
done  # title[@]

[[ -n "${NOT_POSIX[*]}" ]] && { echo -e "$msgWRN Profilnamen mit Sonderzeichen gefunden!" >&2
    echo "Profil(e) mit POSIX-Inkompatiblen Zeichen: \"${NOT_POSIX[*]}\" <=" >&2
    echo 'Bitte nur folgende POSIX-Kompatible Zeichenverwenden: A–Z a–z 0–9 . _ -' ; sleep 10 ;}

# Folgende Zeile auskommentieren, falls zum Herunterfahren des Computers Root-Rechte erforderlich sind
# [[ -n "$SHUTDOWN" && "$(whoami)" != "root" ]] && echo -e "$msgERR Zum automatischen Herunterfahren sind Root-Rechte erforderlich!\e[0m\n" && f_help

[[ -n "$SHUTDOWN" ]] && echo -e '  \e[1;31mDer Computer wird nach Durchführung der Sicherung(en) automatisch heruntergefahren!\e[0m'

for PROFIL in "${P[@]}" ; do  # Anzeige der Einstellungen
  f_settings

  # Wurden der Option -p gültige Argument zugewiesen?
  [[ "$PROFIL" != "$ARG" && "$PROFIL" != 'customBak' ]] && { echo -e "$msgERR Option -p wurde nicht korrekt definiert!\e[0m\n" >&2 ; f_help ;}

  # Konfiguration zu allen gewählten Profilen anzeigen
  # Länge des Strings [80] plus alle Steuerzeichen [14] (ohne \)
  printf '%-94b' "\n\e[30;46m  Konfiguration von:    \e[97m${TITLE} $msgAUTO" ; printf '%b\n' '\e[0m'
  echo -e "\e[46m \e[0m Sicherungsmodus:\e[1m\t${MODE_TXT}\e[0m"
  echo -e "\e[46m \e[0m Quellverzeichnis(se):\e[1m\t${SOURCE:=${MAN_SOURCE[*]}}\e[0m"
  echo -e "\e[46m \e[0m Zielverzeichnis:\e[1m\t${TARGET}\e[0m"
  echo -e "\e[46m \e[0m Log-Datei:\e[1m\t\t${LOG}\e[0m"
  if [[ "$PROFIL" != 'customBak' ]] ; then
    echo -e '\e[46m \e[0m Ausschluss:'
    while read -r ; do
      echo -e "\e[46m \e[0m\t\t\t${REPLY}"
    done < "$EXFROM"
  fi
  if [[ -n "$MAILADRESS" ]] ; then  # eMail-Adresse ist angegeben
    echo -e -n "\e[46m \e[0m eMail-Versand an:\e[1m\t${MAILADRESS}\e[0m"
    [[ "$MAILONLYERRORS" == 'true' ]] && { echo ' [NUR bei Fehler(n)]' ;} || echo ''
  elif [[ "$MAILONLYERRORS" == 'true' ]] ; then
    echo -e '\e[1;43m \e[0m Es wurde \e[1mkeine eMail-Adresse\e[0m für den Versand bei Fehler(n) angegeben!\e[0m\n'
  fi
  if [[ -n "$DEL_OLD_BACKUP" ]] ; then
    case $MODE in
      [NM]) if [[ $DEL_OLD_BACKUP =~ ^[0-9]+$ ]] ; then  # Prüfen, ob eine Zahl angegeben wurde
              echo -e "$msgWRN Gelöschte Dateien:\e[1m\tLÖSCHEN wenn älter als $DEL_OLD_BACKUP Tage\e[0m"
            else
              echo -e "$msgERR Keine gültige Zahl!\e[0m (-d $DEL_OLD_BACKUP)" >&2 ; f_exit 1
            fi
         ;;
         S) echo -e "$msgWRN Löschen von alten Dateien wird im Snapshot-Modus \e[1mnicht\e[0m unterstützt (-d $DEL_OLD_BACKUP)\e[0m" ;;
    esac
  fi
  if [[ -n "$DEL_OLD_SOURCE" ]] ; then
    case $MODE in
      [NM]) if [[ $DEL_OLD_SOURCE =~ ^[0-9]+$ ]] ; then  # Prüfen, ob eine Zahl angegeben wurde
              echo -e "$msgWRN \e[93mQuelldateien:\e[0m\e[1m\t\tLÖSCHEN wenn älter als $DEL_OLD_SOURCE Tage\e[0m"
            else
              echo -e "$msgERR Keine gültige Zahl!\e[0m (--del-old-source $DEL_OLD_SOURCE)" >&2 ; f_exit 1
            fi
         ;;
         S) echo -e "$msgWRN Löschen von Quelldateien wird im Snapshot-Modus \e[1mnicht\e[0m unterstützt (--del-old-source)\e[0m" ;;
    esac
  fi
  if [[ -n "$EXTRA_TARGET" ]] ; then
    echo -e "\e[46m \e[0m Extra Sicherung nach:\e[1m\t${EXTRA_TARGET}\e[0m"
    echo -e "\e[46m \e[0m Archivformat:\e[1m\t\t${EXTRA_ARCHIV}\e[0m"
  fi
  [[ -n "$SAVE_ACL" ]] && echo -e "\e[46m \e[0m Datei-Zugriffskontrollisten:\e[1m ${SAVE_ACL}\e[0m"
done

# Sind die benötigen Programme installiert?
NEEDPROGS=(find mktemp rsync)
[[ -n "$FTPSRC" ]] && NEEDPROGS+=(curlftpfs)
if [[ -n "$MAILADRESS" ]] ; then
  [[ "${MAILPROG^^}" == 'CUSTOMMAIL' ]] && { NEEDPROGS+=("${CUSTOM_MAIL[0]}") ;} || NEEDPROGS+=("$MAILPROG")
  [[ "$MAILPROG" == 'sendmail' ]] && NEEDPROGS+=(uuencode)
  NEEDPROGS+=(tar)
fi
for prog in "${NEEDPROGS[@]}" ; do
  type "$prog" &>/dev/null || MISSING+=("$prog")
done
if [[ -n "${MISSING[*]}" ]] ; then  # Fehlende Programme anzeigen
  echo "Sie benötigen \"${MISSING[*]}\" zur Ausführung dieses Skriptes!" >&2
  f_exit 1
fi

# --- PRE_ACTION ---
if [[ -n "$PRE_ACTION" ]] ; then
  echo -e "$msgINF Führe PRE_ACTION-Befehl(e) aus…"
  eval "$PRE_ACTION" || { echo "Fehler beim Ausführen von \"${PRE_ACTION}\"!" ; sleep 10 ;}
fi

for PROFIL in "${P[@]}" ; do
  f_settings ; f_bak_dir

  if [[ "$PROFIL" != 'customBak' ]] ; then  # Nicht bei benutzerdefinierter Sicherung
    # "/" am Ende entfernen
    f_remove_slash SOURCE ; f_remove_slash TARGET ; f_remove_slash BAK_DIR

    # Festplatte (Ziel) eingebunden?  //TODO: Bessere Methode für grep finden
    # if [[ -n "$MOUNT" && "$TARGET" == "$MOUNT"* && ! $(grep "$MOUNT" /proc/mounts &>/dev/null) ]] ; then
    if [[ -n "$MOUNT" && "$TARGET" == "$MOUNT"* ]] ; then
      if ! mountpoint -q "$MOUNT" ; then
        echo -e -n "$msgINF Versuche Sicherungsziel (${MOUNT}) einzuhängen…"
        mount "$MOUNT" &>/dev/null \
          || { echo -e "\n$msgERR Das Sicherungsziel konnte nicht eingebunden werden! (RC: $?)\e[0m (\"${MOUNT}\")" >&2 ; f_exit 1 ;}
        echo -e "OK.\nDas Sicherungsziel (\"${MOUNT}\") wurde erfolgreich eingehängt."
        UNMOUNT+=("$MOUNT")  # Nach Sicherung wieder aushängen (Einhängepunkt merken)
      fi  # ! mountpoint
    fi
    # Ist die Quelle ein FTP und eingebunden?
    if [[ -n "$FTPSRC" ]] ; then
      if ! mountpoint "$FTPMNT" ; then
        echo -e -n "$msgINF Versuche FTP-Quelle (${FTPSRC}) unter \"${FTPMNT}\" einzuhängen…"
        curlftpfs "$FTPSRC" "$FTPMNT" &>/dev/null    # FTP einhängen
        grep -q "$FTPMNT" /proc/mounts \
          || { echo -e "\n$msgERR Die FTP-Quelle konnte nicht eingebunden werden! (RC: $?)\e[0m (\"${FTPMNT}\")" >&2 ; f_exit 1 ;}
        echo -e "OK.\nDie FTP-Quelle (${FTPSRC}) wurde erfolgreich unter (\"${FTPMNT}\") eingehängt."
        UMOUNT_FTP=1  # Nach Sicherung wieder aushängen
      fi  # ! mountpoint
    fi
    # Festplatte (Ziel) für zusätzliche Sicherung eingebunden?
    if [[ -n "$EXTRA_MOUNT" && "$EXTRA_TARGET" == "$EXTRA_MOUNT"* ]] ; then
      if ! mountpoint -q "$EXTRA_MOUNT" ; then
        echo -e -n "$msgINF Versuche zusätzliches Sicherungsziel (${EXTRA_MOUNT}) einzuhängen…"
        mount "$EXTRA_MOUNT" &>/dev/null \
          || { echo -e "\n$msgERR Das zusätzliche Sicherungsziel konnte nicht eingebunden werden! (RC: $?)\e[0m (\"${EXTRA_MOUNT}\")" >&2
               f_exit 1 ;}
        echo -e "OK.\nDas zusätzliche Sicherungsziel (\"${EXTRA_MOUNT}\") wurde erfolgreich eingehängt."
        UNMOUNT+=("$MOUNT")  # Nach Sicherung wieder aushängen (Einhängepunkt merken)
      fi  # ! mountpoint
    fi
  fi  # ! customBak

  ERRLOG="${LOG%.*}.err.log"  # Fehlerlog im Logverzeichnis der Sicherung
  # Ggf. Zielverzeichnis erstellen
  [[ ! -d "$TARGET" ]] && { mkdir --parents --verbose "$TARGET" >/dev/null || f_exit 1 ;}
  [[ -e "${TMPDIR}/.stopflag" ]] && rm --force "${TMPDIR}/.stopflag" &>/dev/null
  unset -v 'FINISHEDTEXT' 'MFS_PID'
  printf -v dt '%(%F %R)T' || dt="$(date +'%F %R')"  # Datum für die erste Zeile im Log

  case $MODE in
    N) # Normale Sicherung (inkl. customBak)
      # Ggf. Verzeichnis für gelöschte Dateien erstellen
      [[ ! -d "$BAK_DIR" ]] && { mkdir --parents "$BAK_DIR" >/dev/null || f_exit 1 ;}
      R_TARGET="${TARGET}/${FILES_DIR}"  # Ordner für die gesicherten Dateien

      f_countdown_wait  # Countdown vor dem Start anzeigen
      if [[ -n "$DRY_RUN" || $MINFREE -gt 0 || $MINFREE_BG -gt 0 ]] ; then
        f_check_free_space  # Platz auf dem Ziel überprüfen (DRY_RUN, MINFREE oder MINFREE_BG)
      fi

      # Keine Sicherung, wenn zu wenig Platz und "SKIP_FULL" gesetzt ist
      if [[ -z "$SKIP_FULL" ]] ; then
        # Sicherung mit rsync starten
        echo "==> $dt - $SELF_NAME [#${VERSION}] - Start:" >> "$LOG"  # Sicher stellen, dass ein Log existiert
        echo "rsync ${RSYNC_OPT[*]} --log-file=$LOG --exclude-from=$EXFROM --backup-dir=$BAK_DIR $SOURCE $R_TARGET" >> "$LOG"
        echo -e "$msgINF Starte Sicherung (rsync)…"
        if [[ "$PROFIL" == 'customBak' ]] ; then  # Verzeichnisse wurden manuell übergeben
          rsync "${RSYNC_OPT[@]}" --log-file="$LOG" --exclude-from="$EXFROM" \
            --backup-dir="$BAK_DIR" "${MAN_SOURCE[@]}" "$R_TARGET" >/dev/null 2>> "$ERRLOG"
        else
          rsync "${RSYNC_OPT[@]}" --log-file="$LOG" --exclude-from="$EXFROM" \
            --backup-dir="$BAK_DIR" "${SOURCE}/" "$R_TARGET" >/dev/null 2>> "$ERRLOG"
        fi
        RC=$? ; [[ $RC -ne 0 ]] && { RSYNCRC+=("$RC") ; RSYNCPROF+=("$TITLE") ;}  # Profilname und Fehlercode merken
        [[ -n "$MFS_PID" ]] && f_mfs_kill  # Hintergrundüberwachung beenden!
        if [[ -e "${TMPDIR}/.stopflag" ]] ; then
          FINISHEDTEXT='abgebrochen!'  # Platte voll!
        else  # Alte Daten nur löschen wenn nicht abgebrochen wurde!
          # Funktion zum Löschen alter Sicherungen aufrufen
          [[ -n "$DEL_OLD_BACKUP" ]] && f_del_old_backup "${BAK_DIR%/*}"
          # Funktion zum Löschen alter Dateien auf der Quelle ($1=Quelle $2=Ziel)
          [[ -n "$DEL_OLD_SOURCE" ]] && f_del_old_source "$SOURCE" "$R_TARGET"
        fi  # -e .stopflag
      fi  # SKIP_FULL
    ;;
    S) # Snapshot Sicherung
      # Temporäre Verzeichnisse, die von fehlgeschlagenen Sicherungen noch vorhanden sind löschen
      rm --recursive --force "${TARGET}/tmp_????-??-??*" &>/dev/null

      # Zielverzeichnis ermitteln: Wenn erste Sicherung des Tages, dann ohne Uhrzeit
      printf -v dt2 '%(%Y-%m-%d)T %(%Y-%m-%d_%H-%M)T' \
        || dt2="$(date +'%Y-%m-%d') $(date +'%Y-%m-%d_%H-%M')"
      for TODAY in $dt2 ; do
        [[ ! -e "${TARGET}/${TODAY}" ]] && break
      done
      BACKUPDIR="${TARGET}/${TODAY}" ; TMPBAKDIR="${TARGET}/tmp_${TODAY}"

      # Verzeichnis der letzten Sicherung ermitteln
      LASTBACKUP=$(find "${TARGET}/????-??-??*" -maxdepth 0 -type d 2>/dev/null | tail -1)

      if [[ -n "$LASTBACKUP" ]] ; then
        # Mittels dryRun überprüfen, ob sich etwas geändert hat
        echo "Prüfe, ob es Änderungen zu $LASTBACKUP gibt…"
        TFL="$(mktemp "${TMPDIR}/tmp.rsync.XXXX")"
        rsync "${RSYNC_OPT_SNAPSHOT[@]}" --dry-run --exclude-from="$EXFROM" \
          --link-dest="$LASTBACKUP" "$SOURCE" "$TMPBAKDIR" &> "$TFL"
        # Wenn es keine Unterschiede gibt, ist die 4. Zeile immer diese:
        # sent nn bytes  received nn bytes  n.nn bytes/sec
        mapfile -n 4 -t < "$TFL"  # Einlesen in Array (4 Zeilen)
        if [[ ${MAPFILE[3]} =~ sent.*bytes.*received.*bytes.* ]] ; then
          echo '==> Keine Änderung! Keine Sicherung erforderlich!'
          echo "==> Aktuelle Sicherung: $LASTBACKUP"
          NOT_CHANGED=1  # Keine Sicherung nötig. Merken für später
        fi
        rm "$TFL" &>/dev/null
      fi

      if [[ -z "$NOT_CHANGED" ]] ; then  # Keine Sicherung nötig?
        f_countdown_wait                 # Countdown vor dem Start anzeigen
        # Sicherung mit rsync starten
        echo "==> $dt - $SELF_NAME [#${VERSION}] - Start:" >> "$LOG"  # Sicherstellen, dass ein Log existiert
        echo "rsync ${RSYNC_OPT_SNAPSHOT[*]} --log-file=$LOG --exclude-from=$EXFROM --link-dest=$LASTBACKUP $SOURCE $TMPBAKDIR" >> "$LOG"
        echo -e "$msgINF Starte Sicherung (rsync)…"
        rsync "${RSYNC_OPT_SNAPSHOT[@]}" --log-file="$LOG" --exclude-from="$EXFROM" \
          --link-dest="$LASTBACKUP" "$SOURCE" "$TMPBAKDIR" >/dev/null 2>> "$ERRLOG"
        RC=$? ; if [[ $RC -ne 0 ]] ; then
          RSYNCRC+=("$RC") ; RSYNCPROF+=("$TITLE")  # Profilname und Fehlercode merken
        else                                        # Wenn Sicherung erfolgreich, Verzeichnis umbenennen
          echo "Verschiebe $TMPBAKDIR nach $BACKUPDIR" >> "$LOG"
          mv "$TMPBAKDIR" "$BACKUPDIR" >/dev/null 2>> "$ERRLOG"
        fi
      fi
      unset -v 'NOT_CHANGED'  # Zurücksetzen für den Fall dass mehrere Profile vorhanden sind
    ;;
    M) # Multi rsync (Experimentell)! Quelle: www.krazyworks.com/making-rsync-faster
      # Ggf. Verzeichnis für gelöschte Dateien erstellen
      [[ ! -d "$BAK_DIR" ]] && { mkdir --parents "$BAK_DIR" >/dev/null || f_exit 1 ;}

      # Variablen depth, TARGET, maxdthreads und sleeptime definieren
      depth=1 ; cnt=0 ; sleeptime=5  # Wartezeit zum prüfen der gleichzeitig laufenden rsync-Prozesse
      cd "$SOURCE" || f_exit 1       # In das Quellverzeichnis wechseln
      R_TARGET="${TARGET}/${FILES_DIR}"  # Ordner für die gesicherten Dateien
      # nproc ist im Paket coreutils. Sollte auf allen Linux installationen verfügbar sein
      # Maximale Anzahl gleichzeitig laufender rsync-Prozesse (2 pro Kern)
      maxthreads=$(($(nproc)*2)) || maxthreads=2  # Fallback

      f_countdown_wait  # Countdown vor dem Start anzeigen
      if [[ -n "$DRY_RUN" || $MINFREE -gt 0 || $MINFREE_BG -gt 0 ]] ; then
        f_check_free_space  # Platz auf dem Ziel überprüfen (DRY_RUN, MINFREE oder MINFREE_BG)
      fi

      # Keine Sicherung, wenn zu wenig Platz und "SKIP_FULL" gesetzt ist
      if [[ -z "$SKIP_FULL" ]] ; then
        mapfile -t < "$EXFROM"  # Ausschlussliste einlesen
        mv --force "$EXFROM" "${_EXFROM:=${EXFROM}.$RANDOM}" >/dev/null  # Ausschlussliste für ./
        for i in "${!MAPFILE[@]}" ; do
          [[ "${MAPFILE[i]:0:1}" != '/' ]] && echo "${MAPFILE[i]}" >> "$EXFROM"  # Beginnt nicht mit "/"
        done
        echo "==> $dt - $SELF_NAME [#${VERSION}] - Start:" >> "${LOG%.log}_${cnt}.log"  # Sicherstellen, dass ein Log existiert
        while read -r dir ; do  # Alle Ordner in der Quelle bis zur $maxdepth tiefe
          [[ -e "${TMPDIR}/.stopflag" ]] && break  # Platte voll!
          DIR_C="${dir//[^\/]}"  # Alle Zeichen außer "/" löschen
          if [[ ${#DIR_C} -ge $depth ]] ; then  # Min. ${depth} "/"
            subfolder="${dir/.\/}"              # Führendes "./" entfernen

            for i in "${!MAPFILE[@]}" ; do  # Ausschlussliste verarbeiten
              # Ordner auslassen, wenn "foo" oder "foo/"
              [[ "${MAPFILE[i]}" == "$subfolder" || "${MAPFILE[i]}" == "${subfolder}/" ]] && continue 2
              if [[ "${MAPFILE[i]:0:1}" == '/' ]] ; then  # Beginnt mit "/"
                ONTOP=${MAPFILE[i]:1}  # Ohne führenden "/"
                if [[ "$ONTOP" == "$subfolder" || "$ONTOP" == "${subfolder}/" ]] ; then
                  continue 2  # Ordner auslassen, wenn "/foo" oder "/foo/"
                else  # "/foo/bar"
                  exdir="${ONTOP%%/*}"  # ; echo "ONTOP aber mit Unterordner: /$ONTOP"
                  if [[ "$exdir" == "$subfolder" ]] ; then
                    newex="/${ONTOP#*/}"  # "foo/bar" -> "/bar"
                    EXTRAEXCLUDE+=("--exclude=$newex")
                    # echo "Eintrag: ${MAPFILE[i]} ->EXDIR: /$exdir ->EXCLUDE: $newex"
                  fi
                fi
              fi  # Beginnt mit "/"
            done

            if [[ ! -d "${R_TARGET}/${subfolder}" ]] ; then
              # Zielordner erstellen und Rechte/Eigentümer von Quelle übernehmen
              mkdir --parents "${R_TARGET}/${subfolder}" >/dev/null
              chown --reference="${SOURCE}/${subfolder}" "${R_TARGET}/${subfolder}"
              chmod --reference="${SOURCE}/${subfolder}" "${R_TARGET}/${subfolder}"
            fi

            # rsync-Prozesse auf $maxthreads begrenzen. Warten, wenn Anzahl erreicht ist
            while [[ $(pgrep --exact --count rsync) -ge $maxthreads ]] ; do
              echo -e "$msgINF Es laufen bereits $maxthreads rsync-Processe. Warte $sleeptime sekunden…"
              sleep "$sleeptime"
            done

            ((cnt+=1)) ; echo -e -n "$msgINF Starte rsync-Prozess Nr. $cnt ["
            # rsync für den aktuellen Unterordner im Hintergrund starten
            echo "rsync ${RSYNC_OPT[*]} --log-file=${LOG%.log}_$cnt.log --exclude-from=$EXFROM ${EXTRAEXCLUDE[*]} --backup-dir=${BAK_DIR}/${subfolder} ${SOURCE}/${subfolder}/ ${R_TARGET}/${subfolder}/" >> "${LOG%.log}_$cnt.log"
            nohup rsync "${RSYNC_OPT[@]}" --log-file="${LOG%.log}_$cnt.log" --exclude-from="$EXFROM" "${EXTRAEXCLUDE[@]}" --backup-dir="${BAK_DIR}/${subfolder}" \
                    "${SOURCE}/${subfolder}/" "${R_TARGET}/${subfolder}/" </dev/null >/dev/null 2>> "$ERRLOG" &
            _JOBS[$!]="${TITLE}_$cnt"  # Array-Element=PID; Inhalt=Profilname mit Zähler
            echo "$!]" ; sleep 0.1     # Kleine Wartezeit, damit nicht alle rsyncs auf einmal starten
            unset -v 'EXTRAEXCLUDE'    # Zurücksetzen für den nächsten Durchlauf
          fi
        done < <(find . -maxdepth $depth -type d)  # Die < <(commands) Syntax verarbeitet alles im gleichen Prozess. Änderungen von globalen Variablen sind so möglich

        if [[ ! -e "${TMPDIR}/.stopflag" ]] ; then  # Platte nicht voll!
          # Dateien in "./" werden im Ziel nicht gelöscht! (Vergleichen und manuell nach BAK_DIR verschieben)
          while IFS= read -r -d '' ; do
            if [[ ! -e "$REPLY" ]] ; then  # Datei ist im Ziel aber nicht (mehr) auf der Quelle
              echo -e "$msgINF Datei \"${REPLY}\" nicht im Quellverzeichnis.\nVerschiebe nach $BAK_DIR"
              mv --force --verbose "${R_TARGET}/${REPLY}" "$BAK_DIR" >> "${LOG%.log}_mv.log" 2>> "$ERRLOG"
            fi
          done < <(find "$R_TARGET" -maxdepth 1 -type f -printf '%P\0')  # %P = Datei ohne führendes "./" und ohne Pfad

          ((cnt+=1)) ; echo -e "$msgINF Starte rsync für Dateien im Stammordner"
          # Dateien über maxdepth Tiefe ebenfalls mit rsync sichern
          echo "find . -maxdepth $depth -type f -print0 | rsync ${RSYNC_OPT[*]} --log-file=${LOG%.log}_$cnt.log --exclude-from=$_EXFROM --backup-dir=$BAK_DIR --files-from=- --from0 ./ ${R_TARGET}/" >> "${LOG%.log}_$cnt.log"
          rsync "${RSYNC_OPT[@]}" --log-file="${LOG%.log}_$cnt.log" --exclude-from="$_EXFROM" \
            --backup-dir="$BAK_DIR" --files-from=<(find . -maxdepth $depth -type f -print0) \
            --from0 ./ "${R_TARGET}/" >/dev/null 2>> "$ERRLOG"
          RC=$? ; [[ $RC -ne 0 ]] && { RSYNCRC+=("$RC") ; RSYNCPROF+=("${TITLE}_$cnt") ;}  # Profilname und Fehlercode merken
        else
          FINISHEDTEXT='abgebrochen!'
        fi  # .stopflag

        # Warten bis alle rsync-Prozesse beendet sind!
        for pid in "${!_JOBS[@]}" ; do
          wait "$pid" ; RC=$?  # wait liefert $? auch für bereits beendete Prozesse
          if [[ $RC -ne 0 ]] ; then
            echo -e "[${pid}] Beendet mit Fehler: ${RC}\n${_JOBS[$pid]}"
            RSYNCRC+=("$RC") ; RSYNCPROF+=("${_JOBS[$pid]}")  # Profilname und Fehlercode merken
          fi
        done
        # Logs zusammenfassen (Jeder rsync-Prozess hat ein eigenes Log erstellt)
        [[ -f "$LOG" ]] && mv --force "$LOG" "${LOG}.old" >/dev/null  # Log schon vorhanden
        shopt -s nullglob  # Nichts tun, wenn nichts gefunden wird
        for log in "${LOG%.log}"_*.log ; do
          { echo "== Logfile: $log ==" ; cat "$log" ;} >> "$LOG"
          rm "$log" &>/dev/null
        done ; shopt -u nullglob

        [[ -n "$MFS_PID" ]] && f_mfs_kill  # Hintergrundüberwachung beenden!
        if [[ -z "$FINISHEDTEXT" ]] ; then  # Alte Daten nur löschen wenn nicht abgebrochen wurde!
          # Funktion zum Löschen alter Sicherungen aufrufen
          [[ -n "$DEL_OLD_BACKUP" ]] && f_del_old_backup "${BAK_DIR%/*}"
          # Funktion zum Löschen alter Dateien auf der Quelle ($1=Quelle $2=Ziel)
          [[ -n "$DEL_OLD_SOURCE" ]] && f_del_old_source "$SOURCE" "$R_TARGET"
        fi  # FINISHEDTEXT
      fi  # SKIP_FULL
    ;;
    *) # Üngültiger Modus
      echo -e "$msgERR Unbekannter Sicherungsmodus!\e[0m (\"${MODE}\")" >&2
      f_exit 1
    ;;
  esac

  ### Sicherung der Datei-Zugriffskontrollisten (ACLs) ###
  if [[ -n "$SAVE_ACL" ]] ; then
  echo "Starte Sicherung der Datei-Zugriffskontrollisten (ACLs) nach: ${SAVE_ACL}" >> "$LOG"
  echo -e "$msgINF Starte Sicherung der Datei-Zugriffskontrollisten (ACLs) nach:\n  \"${SAVE_ACL}\""
    if type getfacl &>/dev/null ; then
      getfacl --recursive --absolute-names "$SOURCE" > "$SAVE_ACL" 2>> "$ERRLOG"
    else
      echo -e "$msgERR \"getfacl\" zum Sichern der Datei-Zugriffskontrollisten nicht gefunden!\e[0m" >&2
    fi
  fi

  ### Zusätzliche Sicherung mit tar ###
  if [[ -n "$EXTRA_TARGET" ]] ; then
    if [[ "$MODE" == 'S' ]] ; then  # Nicht in Snapshot-Modus
      echo "$msgERR Zusätzliche Sicherung wird im Snapshot-Modus nicht unterstützt!\e[0m" >&2
      sleep 10
    else
      printf -v dt '%(%Y%m%d_%H%M%S)T'  # Datum und Zeit (20171017_131601)
      [[ "${SOURCE:0:1}" == '/' ]] && EXTRA_SOURCE="${SOURCE#\/}"  # Führendes "/" entfernen
      echo "Starte zusätzliche Sicherung nach ${EXTRA_TARGET}…" >> "$LOG"
      echo -e "$msgINF Starte zusätzliche Sicherung nach:\n  \"${EXTRA_TARGET}\""
      # Zielordner suchen und erstellen
      [[ ! -d "$EXTRA_TARGET" ]] && { mkdir --parents "$EXTRA_TARGET" >/dev/null || f_exit 1 ;}

      # Prüfen, ob maximale inkrementelle Sicherungen vorhanden sind
      cd "$EXTRA_TARGET" || f_exit 1
      mapfile -t < <(ls -1 --sort=time ./*"$EXTRA_ARCHIV" 2>/dev/null || :)  # "|| :" Fehlercode unterdrücken
      if [[ "${#MAPFILE[@]}" -gt $EXTRA_MAXINC ]] ; then
        echo "Anzahl max. inkrementelle Sicherungen erreicht! (${EXTRA_MAXINC})" >> "$LOG"
        echo -e "$msgINF Anzahl max. inkrementelle Sicherungen erreicht! (${EXTRA_MAXINC})"
        if [[ $EXTRA_MAXBAK -gt 0 ]] ; then  # Sicherung in Ordner verschieben
          PREVDIR="${MAPFILE[0]%.$EXTRA_ARCHIV}"  # Archiverweiterung entfernen
          if [[ ! -d "$PREVDIR" ]] ; then
            mkdir --parents "$PREVDIR" >/dev/null  # Ordner erstellen
            echo -e "$msgINF Verschiebe Sicherung nach $PREVDIR"
            { echo "Verschiebe Sicherung nach ${EXTRA_TARGET}/${PREVDIR}"
              mv --force --verbose ./*".$EXTRA_ARCHIV" "$PREVDIR"  # Alle Archive verschieben
              rm --force --verbose './.snapshot.file'  # Löschen, um eine Vollsicherung zu erhalten
            } >> "$LOG"
          else
            echo "$msgWRN Verzeichnis $PREVDIR existiert bereits!" >&2
          fi  # ! -d $PREVDIR
        else  # EXTRA_MAXBAK -gt 0
          echo -e "$msgINF Lösche letzte Sicherung! (EXTRA_MAXBAK=0)"
          { echo 'Lösche letzte Sicherung! (EXTRA_MAXBAK=0)'
            rm --force --verbose ./*".$EXTRA_ARCHIV"  # Alle Archive löschen
            rm --force --verbose './.snapshot.file'  # Löschen, um eine Vollsicherung zu erhalten
          }  >> "$LOG"
        fi
        # Prüfen, ob max. Sicherungen vorhanden sind
        if [[ $EXTRA_MAXBAK -gt 0 ]] ; then
          mapfile -t < <(ls -1 --directory --reverse --sort=time ./*/ 2>/dev/null || :)  # "|| :" Fehlercode unterdrücken
          if [[ "${#MAPFILE[@]}" -gt $EXTRA_MAXBAK ]] ; then
            echo -e "$msgINF Anzahl max. Sicherungen erreicht! (${EXTRA_MAXBAK})"
            echo -e "$msgINF Lösche älteste Sicherung ${MAPFILE[0]}"
            { echo "Anzahl max. Sicherungen erreicht! (${EXTRA_MAXBAK})"
              echo "Lösche älteste Sicherung ${MAPFILE[0]}"
              rm --recursive --force --verbose "${MAPFILE[0]}"
            } >> "$LOG"
          fi
        fi # EXTRA_MAXBAK -gt 0
      fi

      ### Zusätzliche Sicherung mit tar ###
      [[ -e "${EXTRA_TARGET}/.snapshot.file" ]] && _INC='inkrementelle '
      echo -e "$msgINF Erstelle zusätzliche ${_INC}Sicherung…"
      { echo "Erstelle zusätzliche ${_INC}Sicherung…"
        tar --create --auto-compress --absolute-names --preserve-permissions \
          --listed-incremental="${EXTRA_TARGET}/.snapshot.file" \
          --transform="s,^\.,${EXTRA_SOURCE:-$SOURCE}," \
          --file="${EXTRA_TARGET}/${TITLE}_${dt}.${EXTRA_ARCHIV}" \
          --directory="$R_TARGET" .
      } >> "$LOG"
      unset -v '_INC' 'EXTRA_SOURCE'  # Zurücksetzen für den Fall dass mehrere Profile vorhanden sind
    fi  # MODE == S
  fi  # -n EXTRA_TARGET

  # Log-Datei und Ziel merken für Mail-Versand
  [[ -n "$MAILADRESS" ]] && { LOGFILES+=("$LOG") ; TARGETS+=("$TARGET") ;}

  # Zuvor eingehängte FTP-Quelle wieder aushängen
  [[ -n "$UMOUNT_FTP" ]] && { umount "$FTPMNT" ; unset -v 'UMOUNT_FTP' ;}

  [[ ${RC:-0} -ne 0 ]] && ERRTEXT="\e[91mmit Fehler ($RC) \e[0;1m"
  echo -e -n "\a\n\n${msgINF} \e[1mProfil \"${TITLE}\" wurde ${ERRTEXT}${FINISHEDTEXT:=abgeschlossen}\e[0m"
  printf ' (%(%x %X)T)\n'  # Datum und Zeit
  echo -e "  Weitere Informationen sind in der Datei:\n  \"${LOG}\" gespeichert.\n"
  if [[ -s "$ERRLOG" ]] ; then  # Existiert und ist nicht Leer
    if [[ $(stat -c %Y "$ERRLOG") -gt $(stat -c %Y "$TMPDIR") ]] ; then  # Fehler-Log merken, wenn neuer als "$TMPDIR"
      ERRLOGS+=("$ERRLOG")
      echo -e "$msgINF Fehlermeldungen wurden in der Datei:\n  \"${ERRLOG}\" gespeichert.\n"
    fi
  else
    rm "$ERRLOG" &>/dev/null  # Leeres Log löschen
  fi
  unset -v 'RC' 'ERRTEXT'  # $RC und $ERRTEXT zurücksetzen
done # for PROFILE
SCRIPT_TIMING[1]=$SECONDS  # Zeit nach der Sicherung mit rsync/tar/getfacl (Sekunden)

# --- eMail senden ---
if [[ -n "$MAILADRESS" ]] ; then
  # Variablen
  printf -v ARCH 'Logs_%(%F-%H%M)T.tar.xz' \
    || ARCH="Logs_$(date +'%F-%H%M').tar.xz"  # Archiv mit Datum und Zeit (kein :)
  ARCHIV="${TMPDIR}/${ARCH}"              # Archiv mit Pfad
  MAILFILE="${TMPDIR}/~Mail.txt"          # Text für die eMail
  SUBJECT="Sicherungs-Bericht von $SELF_NAME auf ${HOSTNAME^^}"  # Betreff der Mail

  if [[ ${MAXLOGSIZE:=$((1024*1024))} -gt 0 ]] ; then  # Wenn leer dann Vorgabe 1 MB. 0 = deaktiviert
    # Log(s) packen
    echo -e "$msgINF Erstelle Archiv mit $((${#LOGFILES[@]}+${#ERRLOGS[@]})) Logdatei(en):\n  \"${ARCHIV}\" "
    tar --create --absolute-names --auto-compress --file="$ARCHIV" "${LOGFILES[@]}" "${ERRLOGS[@]}"
    FILESIZE="$(stat -c %s "$ARCHIV")"    # Größe des Archivs
    if [[ $FILESIZE -gt $MAXLOGSIZE ]] ; then
      rm "$ARCHIV" &>/dev/null            # Archiv ist zu groß für den eMail-Versand
      ARCHIV="${ARCHIV%%.*}.txt"          # Info-Datei als Ersatz
      { echo 'Das Archiv mit den Logdateien ist zu groß für den Versand per eMail.'
        echo "Der eingestellte Wert für die Maximalgröße ist $MAXLOGSIZE Bytes."
        echo -e '\n==> Liste der lokal angelegten Log-Datei(en):'
        for file in "${LOGFILES[@]}" "${ERRLOGS[@]}" ; do
          echo "$file"
        done
      } > "$ARCHIV"
    fi
  else  # MAXLOGSIZE=0
    ARCHIV="${ARCHIV%%.*}.txt"  # Info-Datei
    { echo 'Das Senden von Logdateien ist deaktiviert (MAXLOGSZE=0).'
      echo -e '\n==> Liste der lokal angelegten Log-Datei(en):'
      for file in "${LOGFILES[@]}" "${ERRLOGS[@]}" ; do
        echo "$file"
      done
    } > "$ARCHIV"
  fi

    echo -e "$msgINF Erzeuge eMail-Bericht…"  # Text der eMail erzeugen
  { echo -e "Sicherungs-Bericht von $SELF_NAME [#${VERSION}] auf ${HOSTNAME^^}.\n"
    echo -n 'Die letzte Sicherung wurde beendet. '
    [[ ${#LOGFILES[@]} -ge 1 ]] && echo "Es wurde(n) ${#LOGFILES[@]} Log-Datei(en) erstellt."
  } > "$MAILFILE"

  if [[ ${#ERRLOGS[@]} -ge 1 ]] ; then
    echo -e "\n==> Zusätzlich wurde(n) ${#ERRLOGS[@]} Fehler-Log(s) erstellt!" >> "$MAILFILE"
    SUBJECT="FEHLER bei Sicherung von $SELF_NAME auf ${HOSTNAME^^}"  # Neuer Betreff der Mail bei Fehlern
  fi

  if [[ ${#RSYNCRC[@]} -ge 1 && "$SHOWERRORS" == 'true' ]] ; then  # Profile mit Fehlern anzeigen
    echo -e '\n==> Profil(e) mit Fehler(n):' >> "$MAILFILE"
    for i in "${!RSYNCRC[@]}" ; do
      echo "${RSYNCPROF[i]} (Rückgabecode ${RSYNCRC[i]})" >> "$MAILFILE"
    done
  fi  # SHOWERRORS

  if [[ "$SHOWOS" == 'true' && -f '/etc/os-release' ]] ; then
    while read -r ; do
      [[ ${REPLY^^} =~ PRETTY_NAME ]] && { OSNAME="${REPLY/*=}"
        OSNAME="${OSNAME//\"/}" ; break ;}
    done < /etc/os-release
    echo -e "\n==> Auf ${HOSTNAME^^} verwendetes Betriebssystem:\n${OSNAME:-'Unbekannt'}" >> "$MAILFILE"
  fi  # SHOWOS

  [[ "$SHOWOPTIONS" == 'true' ]] && echo -e "\n==> Folgende Optionen wurden verwendet:\n$*" >> "$MAILFILE"

  # //TODO Profile anzeigen

  for i in "${!TARGETS[@]}" ; do
    if [[ "$SHOWUSAGE" == 'true' ]] ; then  # Anzeige ist abschaltbar in der *.conf
      mapfile -t < <(df -Ph "${TARGETS[i]}")  # Ausgabe von df in Array (Zwei Zeilen)
      TARGETLINE=(${MAPFILE[1]}) ; TARGETDEV=${TARGETLINE[0]}  # Erstes Element ist das Device
      if [[ ! "${TARGETDEVS[@]}" =~ $TARGETDEV ]] ; then
        TARGETDEVS+=("$TARGETDEV")
        echo -e "\n==> Status des Sicherungsziels (${TARGETDEV}):" >> "$MAILFILE"
        echo -e "${MAPFILE[0]}\n${MAPFILE[1]}" >> "$MAILFILE"
      fi
    fi  # SHOWUSAGE
    if [[ "$SHOWCONTENT" == 'true' ]] ; then  # Auflistung ist abschaltbar in der *.conf
      LOGDIR="${LOGFILES[i]%/*}" ; [[ "${LOGDIRS[@]}" =~ $LOGDIR ]] && continue
      LOGDIRS+=("$LOGDIR")
      { echo -e "\n==> Inhalt von ${LOGDIR}:"
        ls -l --human-readable "$LOGDIR"
        # Anzeige der Belegung des Sicherungsverzeichnisses und Unterordner
        echo -e "\n==> Belegung von ${LOGDIR}:"
        du --human-readable --summarize "$LOGDIR"
        for dir in "${LOGDIR}"/*/ ; do
          du --human-readable --summarize "$dir"
        done
      } >> "$MAILFILE"
    fi  # SHOWCONTENT
  done

  if [[ "$SHOWDURATION" == 'true' ]] ; then  # Auflistung ist abschaltbar in der *.conf
    SCRIPT_TIMING[2]=$SECONDS  # Zeit nach der Statistik
    SCRIPT_TIMING[10]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[0]))  # Gesamt
    SCRIPT_TIMING[11]=$((SCRIPT_TIMING[1] - SCRIPT_TIMING[0]))  # rsync/tar
    SCRIPT_TIMING[12]=$((SCRIPT_TIMING[2] - SCRIPT_TIMING[1]))  # Statistik
    { echo -e '\n==> Ausführungszeiten:'
      echo "Skriptlaufzeit: $((SCRIPT_TIMING[10] / 60)) Minute(n) und $((SCRIPT_TIMING[10] % 60)) Sekunde(n)"
      echo "  Sicherung: $((SCRIPT_TIMING[11] / 60)) Minute(n) und $((SCRIPT_TIMING[11] % 60)) Sekunde(n)"
      echo "  Erstellen des Mailberichts: $((SCRIPT_TIMING[12] / 60)) Minute(n) und $((SCRIPT_TIMING[12] % 60)) Sekunde(n)"
    } >> "$MAILFILE"
  fi  # SHOWDURATION

  # eMail nur, wenn (a) MAILONLYERRORS=true und Fehler vorhanden sind oder (b) MAILONLYERRORS nicht true
  if [[ ${#ERRLOGS[@]} -ge 1 && "$MAILONLYERRORS" == 'true' || "$MAILONLYERRORS" != 'true' ]] ; then
    # eMail versenden
    echo -e "$msgINF Sende eMail an ${MAILADRESS}…"
    case "$MAILPROG" in
      mpack)  # Sende Mail mit mpack via ssmtp
        iconv --from-code=UTF-8 --to-code=iso-8859-1 --output="${MAILFILE}.x" "$MAILFILE"  #  Damit Umlaute richtig angezeigt werden
        mpack -s "$SUBJECT" -d "${MAILFILE}.x" "$ARCHIV" "$MAILADRESS"  # Kann "root" sein, wenn in sSMTP konfiguriert
      ;;
      sendmail)  # Variante mit sendmail und uuencode
        mail_to_send="${TMPDIR}/~mail_to_send"
        { echo "Subject: $SUBJECT" ; cat "$MAILFILE" ; uuencode "$ARCHIV" "$ARCH" ;} > "$mail_to_send"
        sendmail "$MAILADRESS" < "$mail_to_send"
      ;;
      send[Ee]mail)  # Variante mit "sendEmail". Keine " für die Variable $USETLS verwenden!
        sendEmail -f "$MAILSENDER" -t "$MAILADRESS" -u "$SUBJECT" -o message-file="$MAILFILE" -a "$ARCHIV" \
          -o message-charset=utf-8 -s "${MAILSERVER}:${MAILPORT}" -xu "$MAILUSER" -xp "$MAILPASS" $USETLS
      ;;
      e[Mm]ail)  # Sende Mail mit eMail (https://github.com/deanproxy/eMail)
        email -s "$SUBJECT" -attach "$ARCHIV" "$MAILADRESS" < "$MAILFILE"  # Die ausführbare Datei ist 'email'
      ;;
      mail)  # Sende Mail mit mail (http://j.mp/2kZlJdk)
        mail -s "$SUBJECT" -a "$ARCHIV" "$MAILADRESS" < "$MAILFILE"
      ;;
      custom[Mm]ail)  # Eigenes Mailprogramm verwenden. Siehe auch *.conf -> CUSTOM_MAIL
        for var in MAILADRESS SUBJECT MAILFILE ARCHIV ; do
          CUSTOM_MAIL=("${CUSTOM_MAIL[@]/$var/${!var}}")  # Platzhalter ersetzen
        done
        eval "${CUSTOM_MAIL[@]}"  # Gesamte Zeile ausführen
      ;;
      *) echo -e "\nUnbekanntes Mailprogramm: \"${MAILPROG}\"" ;;
    esac
    RC=$? ; [[ ${RC:-0} -eq 0 ]] && echo -e "\n${msgINF} Sicherungs-Bericht wurde mit \"${MAILPROG}\" an $MAILADRESS versendet.\n    Es wurde(n) ${#LOGFILES[@]} Logdatei(en) angelegt."
  fi  # MAILONLYERRORS
  unset -v 'MAILADRESS'
fi

# Zuvor eingehängte(s) Sicherungsziel(e) wieder aushängen
if [[ ${#UNMOUNT[@]} -ge 1 ]] ; then
  echo -e "$msgINF Manuell eingehängte Sicherungsziele werden wieder ausgehängt…"
  for volume in "${UNMOUNT[@]}" ; do
    umount --force "$volume"
  done
fi

# --- POST_ACTION ---
if [[ -n "$POST_ACTION" ]] ; then
  echo -e "$msgINF Führe POST_ACTION-Befehl(e) aus…"
  eval "$POST_ACTION" || { echo "Fehler beim Ausführen von \"${POST_ACTION}\"!" ; sleep 10 ;}
  unset -v 'POST_ACTION'
fi

# Ggf. Herunterfahren
if [[ -n "$SHUTDOWN" ]] ; then
  # Möglichkeit, das automatische Herunterfahren noch abzubrechen
  "$NOTIFY" "Sicherung(en) abgeschlossen. ACHTUNG: Der Computer wird in 5 Minuten heruntergefahren. Führen Sie \"kill -9 $(pgrep "${0##*/}")\" aus, um das Herunterfahren abzubrechen."
  sleep 1
  echo "This System is going DOWN for System halt in 5 minutes! Run \"kill -9 $(pgrep "${0##*/}")\" to cancel shutdown." | $WALL
  echo -e '\a\e[1;41m ACHTUNG \e[0m Der Computer wird in 5 Minuten heruntergefahren.\n'
  echo -e 'Bitte speichern Sie jetzt alle geöffneten Dokumente oder drücken Sie \e[1m[Strg] + [C]\e[0m,\nfalls der Computer nicht heruntergefahren werden soll.\n'
  sleep 5m
  # Verschiedene Befehle zum Herunterfahren mit Benutzerrechten [muss evtl. an das eigene System angepasst werden!]
  # Alle Systeme mit HAL || GNOME DBUS || KDE DBUS || GNOME || KDE
  # Root-Rechte i. d. R. erforderlich für "halt" und "shutdown"!
  dbus-send --print-reply --system --dest=org.freedesktop.Hal /org/freedesktop/Hal/devices/computer org.freedesktop.Hal.Device.SystemPowerManagement.Shutdown \
    || dbus-send --print-reply --dest=org.gnome.SessionManager /org/gnome/SessionManager org.gnome.SessionManager.RequestShutdown \
    || dbus-send --print-reply --dest=org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 2 2 \
    || gnome-power-cmd shutdown || dcop ksmserver ksmserver logout 0 2 2 \
    || halt || shutdown -h now
else
  echo -e '\n' ; "$NOTIFY" "Sicherung(en) abgeschlossen."
fi

f_exit  # Aufräumen und beenden
