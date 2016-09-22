#!/bin/bash
# = = = = = = = = = = = = = = = = = = RSYNC BACKUP  = = = = = = = = = = = = = = = = = = #
#                                                                                       #
#  MV_Backup.sh                                                                         #
VERSION=160528ß                                                                         #
# Author: MegaV0lt, http://j.mp/cQIazU                                                  #
# Forum und neueste Version: http://j.mp/1TblNNj                                        #
# Basiert auf dem RSYNC-BACKUP-Skript von JaiBee (Siehe unten)                          #
#                                                                                       #
# Alle Anpassungen zum Skript, kann man hier und in der .conf nachlesen.                #
# Wer sich erkenntlich zeigen möchte, kann mir gerne einen kleinen Betrag zukommen      #
# lassen: => http://paypal.me/SteBlo                                                    #
# Der Betrag kann frei gewählt werden. Vorschlag: 2 EUR                                 #
#                                                                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#                                                                                       #
# Author:   JaiBee, http://www.321tux.de                                                #
# Date:     2011-01-02                                                                  #
# Version:  0.98                                                                        #
# License:  Creative Commons "Namensnennung-Nicht-kommerziell-                          #
#           Weitergabe unter gleichen Bedingungen 3.0 Unported "                        #
#           [ http://creativecommons.org/licenses/by-nc-sa/3.0/deed.de ]                #
#                                                                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#                                                                                       #
# Neu:  Automatisches Ein- und Aushängen des Sicherungs-Ziels                           #
#       Das Sicherungsziel wir automatisch Ein- und Ausgehängt, wenn in der fstab       #
#       vorhanden (noauto)                                                              #
# Neu:  Entfernen von alten Sicherungen und Log-Dateien nach einstellbarer Zeit (Tage)  #
#       Beispiel (Backups und Logs älter als 90 Tage löschen): -d 90                    #
#       Wird im Snapshot-Modus nicht verwendet!                                         #
# Neu:  Konfiguration ausgelagert, um den Einsatz auf mehreren Systemen zu vereinfachen #
#       Wird automatisch geladen, wenn im selben Verzeichnis, Verzeichnid des Skripts   #
#       oder im eigenen etc. Datei kann mit "-c mybkp.conf" angegeben werden            #
# Neu:  Konfiguration vereinfacht. Profilnummer muss nicht mehr von Hand geändert werden#
# Neu:  Quelle als FTP definierbar. Zum Einhängen wird curlftpfs benötigt.              #
# Neu:  Versand der Logs per eMail. Verschiedene Mailer werden unterstützt. Aufruf mit  #
#       Parameter -e my@email.de (oder -e root)                                         #
# Neu:  eMail-Bericht mit Angaben zu Fehlern, Belegung der Sicherungen und der          #
#       Sicherungsziele (Auflistung abschaltbar)                                        #
# Neu:  Versand von Logs per Mail abschalt- und begrenzbar (MAXLOGSIZE) [Vorgabe 1 MB]  #
# Neu:  Sicherungsziel kann Profilabhängig definiert werden (mount[]). Automatisches    #
#       Ein- und Aushängen wird unterstützt, wenn in der fstab vorhanden (noauto)       #
# Neu:  Option für "Snapshot"-Backup eingebaut. Konfiguration mittels mode[] im Profil  #
# Neu:  eMail nur im Fehlerfall senden. Konfiguration mittels Variable MAILONLYERRORS   #
#       im Profil oder mit Parameter -f beim Aufruf                                     #
# Neu:  Globale (.conf) Pre- und Post Befehle können definiert werden. Variablen müssen #
#       in der .conf definiert werden. Fehler werden (noch) nicht geloggt, da die       #
#       Ausführung vor bzw. nach der Sicherung statt findet                             #
# Neu:  Experimenteller "Multi-rsync-Modus" kann im .conf aktivert werden. Es werden    #
#       für jeden Ordner im Stammverzeichnis einzelne rsync-Prozesse gestartet.         #
#       ACHTUNG: Noch nicht ausreichend getestet. Auf eigene Gefahr zu verwenden!       #
#       (So wie das ganze Skript)                                                       #
# Neu:  Parameter --del-old-source[=]<Wert> zum löschen von alten Dateien in der Quelle #
#       Beispiel: "--del-old-source 40" löscht Dateien älter als 40 Tage in der Quelle, #
#       wenn die Datei auch im Ziel gefunden wird. Funktioniert nur mit einem Profil!   #
#       Wird im Snapshot-Modus nicht verwendet!                                         #
#                                                                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Dieses Skript sichert / synchronisiert Verzeichnisse mit rsync.
# Dabei können beliebig viele Profile konfiguriert oder die Pfade direkt an das Skript übergeben werden.
# Eine kurze Anleitung kann mit der Option -h aufgerufen werden.

if ((BASH_VERSINFO[0] < 4)) ; then  # Test, ob min. Bash Version 4.0
  echo "Sorry, dieses Skript benötigt Bash Version 4.0 oder neuer!" 2>/dev/null
  exit 1
fi

# Skriptausgaben zusätzlich in Datei speichern.
#exec > >(tee -a /var/log/MV_Backup.log) 2>&1

################################## INTERNE VARIABLEN ####################################

#_DEBUG="on" # Aktivieren für Debugausgaben! Im Skript dann z.B. DEBUG set -x
             # Normalerweise sollte _DEBUG auskommentiert sein (#_DEBUG="on")
SELF="$(readlink /proc/$$/fd/255)" || SELF="$0"  # Eigener Pfad (besseres $0)
SELF_NAME="${SELF##*/}"                          # skript.sh
TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/${SELF_NAME%.*}.XXXX") # Ordner für temporäre Dateien
declare -a _RSYNC_OPT ERRLOGS LOGFILES RSYNCRC RSYNCPROF UNMOUNT # Array's
declare -A _arg JOBS   # Array JOBS wird für den Multi rsync-Modus benötigt

###################################### FUNKTIONEN #######################################

trap 'f_exit 3' SIGHUP SIGINT SIGQUIT SIGABRT  # Bei unerwarteten Ende aufräumen

DEBUG() { [[ "$_DEBUG" == "on" ]] && "$@" || : ;} # Verwenden mit "DEBUG echo $VAR; DEBUG set -x"

f_exit() {                             # Beenden und aufräumen $1 = ExitCode
  local EXIT="${1:-0}"                 # Wenn leer, dann 0
  [[ "$EXIT" -eq 3 ]] && echo -e "\n=> Aufräumen und beenden [$$]"
  [[ -n "${exfrom[*]}" ]] && rm "${exfrom[*]}" 2>/dev/null
  [[ -d "$TMPDIR" ]] && rm --recursive --force "$TMPDIR"  # Ordner für temporäre Dateien
  [[ "$EXIT" -ne 4 ]] && rm --force "$PIDFILE" 2>/dev/null  # PID-Datei entfernen
  exit "$EXIT"
}

f_remove_slash() {                     # "/" am Ende entfernen
  local tmp="$1"
  [[ ${#tmp} -gt 2 && "${tmp: -1}" == "/" ]] && tmp="${tmp%/}"
  echo "$tmp"
}

f_echo() {  # Escape-Sequenzen auch, wenn von echo nicht unterstützt!
  local msg nl="\n"            # Zeilenvorschub
  [[ "$1" == "-n" ]] && { nl="" ; shift ;}
  msg="${1//\\e/\\033}"        # \e durch \033 ersetzen
  printf "%b" "${msg}${nl}"    # Ausgabe am Bildschirm
}

# Wird in der Konsole angezeigt, wenn eine Option nicht angegeben oder definiert wurde
f_help() {
  echo -e "Aufruf: \e[1m$0 \e[34m-p\e[0m \e[1;36mARGUMENT\e[0m [\e[1;34m-p\e[0m \e[1;36mARGUMENT\e[0m]"
  echo -e "        \e[1m$0 \e[34m-m\e[0m \e[1;36mQUELLE(n)\e[0m \e[1;36mZIEL\e[0m"
  echo
  echo -e "\e[37;100m Erforderlich \e[0m"
  for i in "${!arg[@]}" ; do
    echo -e "  \e[1;34m-p\e[0m \e[1;36m${arg[$i]}\e[0m\tProfil \"${title[$i]}\""
  done
  echo -e " oder\n  \e[1;34m-a\e[0m\tAlle Sicherungs-Profile"
  echo -e " oder\n  \e[1;34m-m\e[0m\tVerzeichnisse manuell angeben"
  echo
  echo -e "\e[37;100m Optional \e[0m"
  echo -e "  \e[1;34m-c\e[0m \e[1;36mBeispiel.conf\e[0m Konfigurationsdatei angeben (Pfad und Name)"
  echo -e "  \e[1;34m-e\e[0m \e[1;36mmy@email.de\e[0m   Sendet eMail inkl. angehängten Log(s)"
  echo -e "  \e[1;34m-f\e[0m    eMail nur senden, wenn Fehler auftreten (-e muss angegeben werden)"
  echo -e "  \e[1;34m-d\e[0m \e[1;36mx\e[0m  Alte Sicherungs-Dateien die älter als x Tage sind löschen"
  echo -e "  \e[1;34m-s\e[0m    PC nach Beendigung automatisch herunterfahren (benötigt u. U. Root-Rechte)"
  echo -e "  \e[1;34m-h\e[0m    Hilfe anzeigen"
  echo
  echo -e "\e[37;100m Optional \e[37;1m[Achtung] \e[0m"
  echo -e "  \e[1;34m--del-old-source\e[0m \e[1;36mx\e[0m  Alte Dateien in der \e[1mQuelle\e[0m die älter als x Tage sind löschen"
  echo
  echo -e "\e[37;100m Beispiele \e[0m"
  echo -e "  \e[32mProfil \"${title[2]}\"\e[0m starten und den Computer anschließend \e[31mherunterfahren\e[0m:"
  echo -e "\t$0 \e[32m-p${arg[2]}\e[0m \e[31m-s\e[0m\n"
  echo -e "  \e[33m\"/tmp/Quelle1/\"\e[0m und \e[35m\"/Leer zeichen2/\"\e[0m mit \e[36m\"/media/extern\"\e[0m synchronisieren; anschließend \e[31mherunterfahren\e[0m:"
  echo -e "\t$0 \e[31m-s\e[0;4mm\e[0m \e[33m/tmp/Quelle1\e[0m \e[4m\"\e[0;35m/Leer zeichen2\e[0;4m\"\e[0m \e[36m/media/extern\e[0m"
  f_exit 1
}

f_settings() {
  if [[ "$PROFIL" != "customBak" ]] ; then
    # Benötigte Werte aus dem Array (.conf) holen
    for i in "${!arg[@]}" ; do  # Anzahl der vorhandenen Profile ermitteln
      if [[ "${arg[$i]}" == "$PROFIL" ]] ; then  # Wenn das gewünschte Profil gefunden wurde
        # RSYNC_OPT, RSYNC_OPT_SNAPSHOT und MOUNT wieder herstelen
        [[ -n "$_RSYNC_OPT" ]] && { RSYNC_OPT=("${_RSYNC_OPT[@]}") ; unset -v _RSYNC_OPT ;}
        [[ -n "$_RSYNC_OPT_SNAPSHOT" ]] && { RSYNC_OPT_SNAPSHOT=("${_RSYNC_OPT_SNAPSHOT[@]}") ; unset -v _RSYNC_OPT_SNAPSHOT ;}
        [[ -n "$_MOUNT" ]] && { MOUNT="$_MOUNT" ; unset -v _MOUNT ;}
        [[ "$MOUNT" == "0" ]] && unset -v MOUNT  # MOUNT war nicht gesetzt
        TITLE="${title[$i]}"   ; ARG="${arg[$i]}"       ; MODE="${mode[$i]}"
        SOURCE="${source[$i]}" ; FTPSRC="${ftpsrc[$i]}" ; FTPMNT="${ftpmnt[$i]}"
        TARGET="${target[$i]}" ; LOG="${log[$i]}"       ; EXFROM="${exfrom[$i]}"
        # Erforderliche Werte prüfen, und ggf. Vorgaben setzen
        notset="\e[1;41m -LEER- \e[0m"  # Anzeige, wenn nicht gesetzt
        if [[ -z "$SOURCE" || -z "$TARGET" ]] ; then
          echo -e "\e[1;41m FEHLER \e[0;1m Quelle und/oder Ziel sind nicht konfiguriert!\e[0m"
          echo -e " Profil:    \"${TITLE:-$notset}\"\n  Parameter: \"${ARG:-$notset}\" (Nummer: $i)"
          echo -e " Quelle:    \"${SOURCE:-$notset}\"\n Ziel:        \"${TARGET:-$notset}\""
          f_exit 1
        fi
        if [[ -n "$FTPSRC" && -z "$FTPMNT" ]] ; then
          echo -e "\e[1;41m FEHLER \e[0;1m FTP-Quelle und Einhängepunkt falsch konfiguriert!\e[0m"
          echo -e " Profil:        \"${TITLE:-$notset}\"\n Parameter:     \"${ARG:-$notset}\" (Nummer: $i)"
          echo -e " FTP-Quelle:    \"${FTPSRC:-$notset}\"\n Einhängepunkt: \"${FTPMNT:-$notset}\""
          f_exit 1
        fi
        if [[ -n "$DEL_OLD_SOURCE" && "${#P[@]}" -ne 1 ]] ; then
          echo -e "\e[1;41m FEHLER \e[0;1m \"--del-old-source\" kann nicht mit mehreren Profilen verwendet werden!\e[0m"
          f_exit 1
        fi
        : "${TITLE:=Profil_${ARG}}"  # Wenn Leer, dann Profil_ gefolgt von Parameter
        : "${LOG:=${TMPDIR}/${SELF_NAME%.*}.log}"  # Temporäre Logdatei
        : "${FILES_DIR:=_DATEIEN}"                 # Vorgabe für Sicherungsordner
        ### Bei mehreren Profilen müssen die Werte erst gesichert und später wieder zurückgesetzt werden ###
        [[ -n "${mount[$i]}" ]] && { _MOUNT="${MOUNT:-0}" ; MOUNT="${mount[$i]}" ;} # Eigener Einhängepunkt
        case "${MODE^^}" in  # ${VAR^^} ergibt Großbuchstaben!
          SNAP*) MODE="S" ; MODE_TXT="Snapshot"
            [[ -n "${rsync_opt[$i]}" ]] && { _RSYNC_OPT_SNAPSHOT=("${RSYNC_OPT_SNAPSHOT[@]}") ; RSYNC_OPT_SNAPSHOT=(${rsync_opt[$i]}) ;}
          ;;
          M*) MODE="M" ; MODE_TXT="Multi rsync (Experimentell)" # Verwendet rsync-Optionen aus dem "normalen" Modus
            [[ -n "${rsync_opt[$i]}" ]] && { _RSYNC_OPT=("${RSYNC_OPT[@]}") ; RSYNC_OPT=(${rsync_opt[$i]}) ;}
          ;;
          *) MODE="N" ; MODE_TXT="Normal"
            [[ -n "${rsync_opt[$i]}" ]] && { _RSYNC_OPT=("${RSYNC_OPT[@]}") ; RSYNC_OPT=(${rsync_opt[$i]}) ;}
          ;;
        esac  # MODE
      fi
    done
  fi
}

f_del_old_backup() {   # Verzeichnisse älter als $DEL_OLD_BACKUP Tage löschen
  echo "Lösche Sicherungs-Dateien aus ${1}, die älter als $DEL_OLD_BACKUP Tage sind..."
  { echo "$(date +"%F %R.%S"): Lösche Sicherungs-Dateien aus ${1}, die älter als $DEL_OLD_BACKUP Tage sind..."
    find "$1" -maxdepth 1 -type d -mtime +"$DEL_OLD_BACKUP" -print0 \
      | xargs --null rm --recursive --force --verbose
    # Logdatei(en) löschen (Wenn $TITLE im Namen)
    find "${LOG%/*}" -maxdepth 1 -type f -mtime +"$DEL_OLD_BACKUP" \
         -name "*${TITLE}*" ! -name "${LOG##*/}" -print0 \
      | xargs --null rm --recursive --force --verbose
  } >> "$LOG"
}

f_del_old_source() {   # Dateien älter als $DEL_OLD_SOURCE Tage löschen ($1=Quelle $2=Ziel)
  local file srcdir="$1" targetdir="$2" #; set -x
  [[ $# -ne 2 ]] && return 1  # Benötigt Quelle und Ziel als Parameter
  cd "$srcdir" || return 1    # Bei Fehler abbruch
  echo "Lösche Dateien aus ${srcdir}, die älter als $DEL_OLD_SOURCE Tage sind..."
  echo "$(date +"%F %R.%S"): Lösche Dateien aus ${srcdir}, die älter als $DEL_OLD_SOURCE Tage sind..." >> "$LOG"
  # Dateien auf Quelle die älter als $DEL_OLD_SOURCE Tage sind einlesen
  mapfile -t < <(find "./" -type f -mtime +"$DEL_OLD_SOURCE")
  # Alte Dateien, die im Ziel sind auf der Quelle löschen
  for i in "${!MAPFILE[@]}" ; do
    file="${MAPFILE[$i]/.\/}"  # Führendes "./" entfernen
    if [[ -e "${targetdir}/${file}" ]] ; then
      echo "-> Datei $file in Quelle älter als $DEL_OLD_SOURCE Tage"
    else
      echo "-> Datei $file nicht im Ziel!"  # Sollte nie passieren
      unset -v "MAPFILE[$i]"  # Datei aus der Liste entfernen!
    fi
  done #; set +x #; echo "Dateien zum löschen: ${MAPFILE[@]}"
  printf "%s\n" "${MAPFILE[@]}" #| xargs rm --verbose '{}' >> "$LOG"
  # Leere Ordner älter als $DEL_OLD_SOURCE in Quelle löschen
  find "./" -type d -empty -mtime +"$DEL_OLD_SOURCE" #-delete >> "$LOG"
}

f_countdown_wait() {
  echo -e "\n\e[1mProfil \"${TITLE}\" wird in 5 Sekunden gestartet.\e[0m"
  echo -e "\e[46m \e[0m Zum Abbrechen [Strg] + [C] drücken\n\e[46m \e[0m Zum Pausieren [Strg] + [Z] drücken (Fortsetzen mit \"fg\")\n"
  for i in {5..1} ; do  # Countdown ;)
    echo -e -n "\rStart in \e[97;44m  $i  \e[0m Sekunden"
    sleep 1
  done
  echo -e -n "\r" ; "$NOTIFY" "Sicherung startet (Profil: \"${TITLE}\")"
}

##################################### AUSFÜHRBAR? #######################################

if [[ ! -x "$SELF" ]] ; then
  echo -e "\e[30;103m WARNUNG \e[0;1m Das Skript ist nicht ausführbar!\e[0m"
  echo 'Bitte folgendes ausführen: chmod +x' "$SELF" ; f_exit 1
fi

####################################### LOCKING #########################################

PIDFILE="/var/run/${SELF_NAME%.*}.pid"
if [[ -f "$PIDFILE" ]] ; then  # PID-Datei existiert
  PID="$(< "$PIDFILE")"        # PID einlesen
  ps --pid "$PID" >/dev/null 2>&1
  if [[ $? -eq 0 ]] ; then     # Skript läuft schon!
    echo -e "\e[1;41m FEHLER \e[0;1m Skript läuft bereits!\e[0m (PID: $PID)"
    f_exit 4                   # PID-Datei nicht löschen
  else  ## Prozess nicht gefunden. PID-Datei überschreiben
    echo "$$" > "$PIDFILE" \
      || { echo -e "\e[1;41m FEHLER \e[0;1m PID-Datei konnte nicht überschrieben werden!\e[0m" ; f_exit 1 ;}
  fi
else                           # PID-Datei existiert nicht. Neu anlegen
  echo "$$" > "$PIDFILE" \
    || { echo -e "\e[1;41m FEHLER \e[0;1m PID-Datei konnte nicht erzeugt werden!\e[0m" ; f_exit 1 ;}
fi

##################################### KONFIG LADEN ######################################

# Testen, ob Konfiguration angegeben wurde (-c ...)
while getopts ":c:" opt ; do
  case "$opt" in
    c) CONFIG="$OPTARG"
       if [[ -f "$CONFIG" ]] ; then  # Konfig wurde angegeben und existiert
         source "$CONFIG" ; CONFLOADED=1
         break
       else
         echo -e "\e[1;41m FEHLER \e[0;1m Die angegebene Konfigurationsdatei fehlt!\e[0m (\"${CONFIG}\")"
         f_exit 1
       fi
    ;;
    ?) ;;
  esac
done

# Konfigurationsdatei laden [Wenn Skript=MV_Backup.sh Konfig=MV_Backup.conf]
if [[ -z "$CONFLOADED" ]] ; then     # Konfiguration wurde noch nicht geladen
  # Suche Konfig im aktuellen Verzeichnis, im Verzeichnis des Skripts und im eigenen etc
  CONFIG_DIRS=". ${SELF%/*} ${HOME}/etc" ; CONFIG_NAME="${SELF_NAME%.*}.conf"
  for dir in $CONFIG_DIRS ; do
    CONFIG="${dir}/${CONFIG_NAME}"
    if [[ -f "$CONFIG" ]] ; then
      source "$CONFIG" ; CONFLOADED=2
      break  # Die erste gefundene Konfiguration wird verwendet
    fi
  done
  if [[ -z "$CONFLOADED" ]] ; then   # Konfiguration wurde nicht gefunden
    echo -e "\e[1;41m FEHLER \e[0;1m Keine Konfigurationsdatei gefunden!\e[0m (\"${CONFIG_DIRS}\")"
    f_help
  fi
fi

######################################### START #########################################

# Wenn eine grafische Oberfläche vorhanden ist, wird u.a. "notify-send" für Benachrichtigungen verwendet, ansonsten immer "echo"
NOTIFY="echo"
if [[ -n "$DISPLAY" ]] ; then
  NOTIFY="notify-send"
  WALL="wall"
fi

tty --silent && clear
echo -e "\e[44m \e[0;1m RSYNC BACKUP\e[0m\n\e[44m \e[0m\e[0;32m => Version: ${VERSION}\e[0m by MegaV0lt, http://j.mp/1TblNNj"
echo -e "\e[44m \e[0m Original: 2011 by JaiBee, http://www.321tux.de/"
# Anzeigen, welche Konfiguration geladen wurde!
echo -e "\e[46m \e[0m Verwendete Konfiguration:\e[1m\t${CONFIG}\e[0m\n"

OPTIND=1  # Wird benötigt, wenn getops ein weiteres mal verwendet werden soll!
optspec=":p:ac:m:sd:e:fh-:"
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
          i=$(f_remove_slash "$i")  # "/" am Ende entfernen
          SOURCE+=" $i"             # Verzeichnis anhängen
        fi
      done
      TARGET=$(f_remove_slash "$TARGET") # "/" am Ende entfernen
      P="customBak" ; TITLE="Benutzerdefinierte Sicherung"
      LOG="${TARGET}/${TITLE}_log.txt"
      MOUNT="" ; MODE="N" ; MODE_TXT="Benutzerdefiniert"
    ;;
    s) SHUTDOWN="true" ;;           # Herunterfahren gewählt
    d) DEL_OLD_BACKUP="$OPTARG" ;;  # Alte Backups entfernen (Zahl entspricht Tage, die erhalten bleiben)
    e) MAILADRESS="$OPTARG" ;;      # eMail-Adresse verwenden um Logs zu senden
    f) MAILONLYERRORS="true" ;;     # eMail nur bei Fehlern senden
    h) f_help ;;                    # Hilfe anzeigen
    -) case "${OPTARG}" in          # Lange Option (--) # TEST
         del-old-source)            # Parameter nach Leerzeichen
           DEL_OLD_SOURCE="${!OPTIND}"; ((OPTIND++))
           #echo "Option: '--${OPTARG}', Wert: '${DEL_OLD_SOURCE}'" >&2;
         ;;
         del-old-source=*)          # Parameter nach "="
           val="${OPTARG#*=}" ; DEL_OLD_SOURCE="${OPTARG%=$val}"
           #echo "Option: '--${opt}', Wert: '${DEL_OLD_SOURCE}'" >&2
         ;;
         *) if [[ "$OPTERR" = 1 && "${optspec:0:1}" != ":" ]] ; then
              echo "Unbekannte Option --${OPTARG}" >&2
              f_exit
            fi
         ;;
       esac
       ;;
    #?) echo -e "\e[1;41m FEHLER \e[0;1m Option ungültig!\e[0m\n" && f_help ;;
    *) if [[ "$OPTERR" != 1 || "${optspec:0:1}" = ":" ]] ; then
         echo "Non-option argument: '-${OPTARG}'" >&2
         echo -e "\e[1;41m FEHLER \e[0;1m Option ungültig!\e[0m\n" && f_help
       fi
    ;;
  esac
done

# Wenn $P leer ist, wurde die Option -p oder -a nicht angegeben
[[ -z "${P[*]}" ]] && { echo -e "\e[1;41m FEHLER \e[0;1m Es wurde kein Profil angegeben!\e[0m\n" ; f_help ;}

# Prüfen ob alle Profile eindeutige Buchstaben haben (arg[$nr])
for parameter in "${arg[@]}" ; do
  [[ -z "${_arg[$parameter]+_}" ]] && _arg[$parameter]=1 || \
    { echo -e "\e[1;41m FEHLER \e[0;1m Profilkonfiguration ist fehlerhaft! (Keine eindeutigen Buchstaben)\n\t => arg[\$nr]=\"$parameter\" <= wird mehrfach verwendet\e[0m\n" ; f_exit ;}
done

# Folgende Zeile auskommentieren, falls zum Herunterfahren des Computers Root-Rechte erforderlich sind
#[[ -n "$SHUTDOWN" && "$(whoami)" != "root" ]] && echo -e "\e[1;41m FEHLER \e[0;1m Zum automatischen Herunterfahren sind Root-Rechte erforderlich!\e[0m\n" && f_help

[[ -n "$SHUTDOWN" ]] && echo -e "  \e[1;31mDer Computer wird nach Durchführung der Sicherung(en) automatisch heruntergefahren!\e[0m"

for PROFIL in "${P[@]}" ; do  # Anzeige der Einstellungen
  f_settings

  # Wurden der Option -p gültige Argument zugewiesen?
  [[ "$PROFIL" != "$ARG" && "$PROFIL" != "customBak" ]] && { echo -e "\e[1;41m FEHLER \e[0;1m Option -p wurde nicht korrekt definiert!\e[0m\n" ; f_help ;}

  # Konfiguration zu allen gewählten Profilen anzeigen
  echo -e "\n\e[30;46m  Konfiguration von:    \e[97m${TITLE} \e[0m"
  echo -e "\e[46m \e[0m Sicherungsmodus:\e[1m\t${MODE_TXT}\e[0m"
  echo -e "\e[46m \e[0m Quellverzeichnis(se):\e[1m\t${SOURCE}\e[0m"
  echo -e "\e[46m \e[0m Zielverzeichnis:\e[1m\t${TARGET}\e[0m"
  echo -e "\e[46m \e[0m Log-Datei:\e[1m\t\t${LOG}\e[0m"
  if [[ "$PROFIL" != "customBak" ]] ; then
    echo -e "\e[46m \e[0m Ausschluss:"
    while read -r line ; do
      echo -e "\e[46m \e[0m\t\t\t${line}"
    done < "$EXFROM"
  fi
  if [[ -n "$MAILADRESS" ]] ; then                # eMail-Adresse ist angegeben
    if [[ "$MAILONLYERRORS" == "true" ]] ; then   # eMail nur bei Fehler
      echo -e "\e[46m \e[0m eMail-Versand an:\e[1m\t${MAILADRESS}\e[0m [NUR bei Fehler(n)]"
    else                                          # eMail immer senden
      echo -e "\e[46m \e[0m eMail-Versand an:\e[1m\t${MAILADRESS}\e[0m"
    fi
  elif [[ "$MAILONLYERRORS" == "true" ]] ; then
    echo -e "\e[1;43m \e[0m Es wurde \e[1mkeine eMail-Adresse\e[0m für den Versand bei Fehler(n) angegeben!\e[0m\n"
  fi

  if [[ -n "$DEL_OLD_BACKUP" ]] ; then
    case $MODE in
      [NM]) if [[ $DEL_OLD_BACKUP =~ ^[0-9]+$ ]] ; then  # Prüfen, ob eine Zahl angegeben wurde
              echo -e "\e[103m \e[0m Sicherungen:\e[1m\t\tLÖSCHEN wenn älter als $DEL_OLD_BACKUP Tage\e[0m"
            else
              echo -e "\e[1;41m FEHLER \e[0;1m Keine gültige Zahl!\e[0m (-d $DEL_OLD_BACKUP)" ; f_exit 1
            fi
         ;;
         S) echo -e "\e[103m \e[0m Löschen von alten Dateien wird im Snapshot-Modus \e[1mnicht\e[0m unterstützt (-d $DEL_OLD_BACKUP)\e[0m" ;;
    esac
  fi
  if [[ -n "$DEL_OLD_SOURCE" ]] ; then
    case $MODE in
      [NM]) if [[ $DEL_OLD_SOURCE =~ ^[0-9]+$ ]] ; then  # Prüfen, ob eine Zahl angegeben wurde
              echo -e "\e[103m \e[0m \e[93mQuelldateien:\e[0m\e[1m\t\tLÖSCHEN wenn älter als $DEL_OLD_SOURCE Tage\e[0m"
            else
              echo -e "\e[1;41m FEHLER \e[0;1m Keine gültige Zahl!\e[0m (--del-old-source $DEL_OLD_SOURCE)" ; f_exit 1
            fi
         ;;
         S) echo -e "\e[103m \e[0m Löschen von Quelldateien wird im Snapshot-Modus \e[1mnicht\e[0m unterstützt (--del-old-source)\e[0m" ;;
    esac
  fi
done

# Sind die benötigen Programme installiert?
NEEDPROGS=(mktemp rsync "$NOTIFY" "$WALL")
[[ -n "$DEL_OLD_BACKUP" ]] && NEEDPROGS+=("find")
[[ -n "$FTPSRC" ]] && NEEDPROGS+=("curlftpfs")
if [[ -n "$MAILADRESS" ]] ; then
  NEEDPROGS+=("$MAILPROG" "tar")
  [[ "$MAILPROG" == "sendmail" ]] && NEEDPROGS+=("uuencode")
fi
for prog in "${NEEDPROGS[@]}" ; do
  #which "$prog" &>/dev/null || MISSING+=("$prog")
  type "$prog" &>/dev/null || MISSING+=("$prog")
done
if [[ -n "${MISSING[*]}" ]] ; then  # Fehlende Programme anzeigen
  echo "Sie benötigen \"${MISSING[*]}\" zur Ausführung dieses Skriptes!"
  f_exit 1
fi

### PRE_ACTION
if [[ -n "$PRE_ACTION" ]] ; then
  echo "Führe PRE_ACTION-Befehl(e) aus..."
  eval "$PRE_ACTION"
  [[ $? -gt 0 ]] && echo "Fehler beim Ausführen von \"${PRE_ACTION}\"!" && sleep 10
fi

for PROFIL in "${P[@]}" ; do
  f_settings ; f_bak_dir

  if [[ "$PROFIL" != "customBak" ]] ; then  # Nicht bei benutzerdefinierter Sicherung
    # "/" am Ende entfernen
    SOURCE="$(f_remove_slash "$SOURCE")" ; TARGET="$(f_remove_slash "$TARGET")"
    BAK_DIR="$(f_remove_slash "$BAK_DIR")"

    # Festplatte (Ziel) eingebunden?
    if [[ -n "$MOUNT" && "$TARGET" == "$MOUNT"* && ! $(grep "$MOUNT" /etc/mtab) ]] ; then
      echo -e -n "Versuche Sicherungsziel (${MOUNT}) einzuhängen..."
      mount "$MOUNT" &>/dev/null
      grep "$MOUNT" /etc/mtab >/dev/null || { echo -e "\n\e[1;41m FEHLER \e[0;1m Das Sicherungsziel konnte nicht eingebunden werden!\e[0m (\"${MOUNT}\")" ; f_exit 1 ;}
      echo -e "OK.\nDas Sicherungsziel (\"${MOUNT}\") wurde erfolgreich eingehängt."
      UNMOUNT+=("$MOUNT")  # Nach Backup wieder aushängen (Einhängepunkt merken)
    fi
    # Ist die Quelle ein FTP und eingebunden?
    if [[ -n "$FTPSRC" && ! $(grep "$FTPMNT" /etc/mtab) ]] ; then
      echo -e -n "Versuche FTP-Quelle unter \"${FTPMNT}\" einzuhängen..."
      curlftpfs "$FTPSRC" "$FTPMNT" &>/dev/null    # FTP einhängen
      grep "$FTPMNT" /etc/mtab >/dev/null || { echo -e "\n\e[1;41m FEHLER \e[0;1m Die FTP-Quelle konnte nicht eingebunden werden!\e[0m (\"${FTPMNT}\")" ; f_exit 1 ;}
      echo -e "OK.\nDie FTP-Quelle wurde erfolgreich unter (\"${FTPMNT}\") eingehängt."
      UNMOUNTFTP=1  # Nach Backup wieder aushängen
    fi
  fi  # ! customBak

  ERRLOG="${LOG%.*}.error.log"  # Fehlerlog im Logverzeichnis der Sicherung
  # Ggf. Zielverzeichnis erstellen
  [[ ! -d "$TARGET" ]] && { mkdir --parents --verbose "$TARGET" || f_exit 1 ;}

  case $MODE in
    N) ### Normales Backup (inkl. customBak)
      # Ggf. Verzeichnis für gelöschte Dateien erstellen
      [[ ! -d "$BAK_DIR" ]] && { mkdir --parents "$BAK_DIR" || f_exit 1 ;}
      R_TARGET="${TARGET}/${FILES_DIR}"  # Ordner für die gesicherten Dateien

      f_countdown_wait  # Countdown vor dem Start anzeigen
      ### Backup mit rsync starten ###
      echo "$(date +'%F %R') - $SELF_NAME [#${VERSION}] - Start:" >> "$LOG"  # Sicher stellen, dass ein Log existiert
      echo "rsync ${RSYNC_OPT[*]} --log-file=$LOG --exclude-from=$EXFROM --backup-dir=$BAK_DIR $SOURCE $R_TARGET" >> "$LOG"
      echo "-> Starte rsync..."
      rsync "${RSYNC_OPT[@]}" --log-file="$LOG" --exclude-from="$EXFROM" \
        --backup-dir="$BAK_DIR" "${SOURCE}/" "$R_TARGET" >/dev/null 2>> "$ERRLOG"
      RC=$? ; [[ $RC -ne 0 ]] && { RSYNCRC+=("$RC") ; RSYNCPROF+=("$TITLE") ;} # Profilname und Fehlercode merken

      # Funktion zum Löschen alter Backups aufrufen
      [[ -n "$DEL_OLD_BACKUP" ]] && f_del_old_backup "${BAK_DIR%/*}"

      # Funktion zum Löschen alter Dateien auf der Quelle ($1=Quelle $2=Ziel)
      [[ -n "$DEL_OLD_SOURCE" ]] && f_del_old_source "$SOURCE" "$R_TARGET"
    ;;
    S) ### Snapshot Backup
      # Temporäre Verzeichnisse, die von fehlgeschlagenen Backups noch vorhanden sind löschen
      rm --recursive --force "${TARGET}/tmp_????-??-??*" 2>/dev/null

      # Zielverzeichnis ermitteln: Wenn erstes Backup des Tages, dann ohne Uhrzeit
      for TODAY in $(date +%Y-%m-%d) $(date +%Y-%m-%d_%H-%M) ; do
        [[ ! -e ${TARGET}/${TODAY} ]] && break
      done
      BACKUPDIR="${TARGET}/${TODAY}" ; TMPBAKDIR="${TARGET}/tmp_${TODAY}"

      # Verzeichnis des letzten Backups ermitteln
      #LASTBACKUP=$(ls -1d $TARGET/????-??-??* 2>/dev/null | tail -1) # Funktioniert nicht, wenn *.log im Verzeichnis
      LASTBACKUP=$(find "${TARGET}/????-??-??*" -maxdepth 0 -type d 2>/dev/null | tail -1)

      if [[ -n "$LASTBACKUP" ]] ; then
        # Mittels dryRun überprüfen, ob sich etwas geändert hat
        echo "Prüfe, ob es Änderungen zu $LASTBACKUP gibt..."
        TFL="$(mktemp "${TMPDIR}/tmp.rsync.XXXX")"
        rsync "${RSYNC_OPT_SNAPSHOT[@]}" -n --exclude-from="$EXFROM" \
          --link-dest="$LASTBACKUP" "$SOURCE" "$TMPBAKDIR" > "$TFL" 2>&1
        # Wenn es keine Unterschiede gibt, ist die 4. Zeile immer diese:
        # sent nn bytes  received nn bytes  n.nn bytes/sec
        mapfile -n 4 -t < "$TFL"  # Einlesen in Array (4 Zeilen)
        if [[ ${MAPFILE[3]} =~ sent.*bytes.*received.*bytes.* ]] ; then
          echo "==> Keine Änderung! Kein Backup erforderlich!"
          echo "==> Aktuelles Backup: $LASTBACKUP"
          NOT_CHANGED=1  # Kein Backup nötig. Merken für später
        fi
        rm "$TFL" 2>/dev/null
      fi

      if [[ -z "$NOT_CHANGED" ]] ; then  # Kein Backup nötig?
        f_countdown_wait                 # Countdown vor dem Start anzeigen
        ### Backup mit rsync starten ###
        echo "$(date +'%F %R') - $SELF_NAME [#${VERSION}] - Start:" >> "$LOG" # Sicherstellen, dass ein Log existiert
        echo "rsync ${RSYNC_OPT_SNAPSHOT[*]} --log-file=$LOG --exclude-from=$EXFROM --link-dest=$LASTBACKUP $SOURCE $TMPBACKDIR" >> "$LOG"
        echo "-> Starte rsync..."
        rsync "${RSYNC_OPT_SNAPSHOT[@]}" --log-file="$LOG" --exclude-from="$EXFROM" \
          --link-dest="$LASTBACKUP" "$SOURCE" "$TMPBAKDIR" >/dev/null 2>> "$ERRLOG"
        RC=$? ; if [ $RC -ne 0 ] ; then
          RSYNCRC+=("$RC") ; RSYNCPROF+=("$TITLE") # Profilname und Fehlercode merken
        else                                       # Wenn Backup erfolgreich, Verzeichnis umbenennen
          echo "Verschiebe $TMPBAKDIR nach $BACKUPDIR" >> "$LOG"
          mv "$TMPBAKDIR" "$BACKUPDIR" 2>> "$ERRLOG"
        fi
      fi
      unset -v NOT_CHANGED  # Zurücksetzen für den Fall dass mehrere Profile vorhanden sind
    ;;
    M) ### Multi rsync (Experimentell)! Quelle: www.krazyworks.com/making-rsync-faster
      # Ggf. Verzeichnis für gelöschte Dateien erstellen
      [[ ! -d "$BAK_DIR" ]] && { mkdir --parents "$BAK_DIR" || f_exit 1 ;}

      # Variablen depth, TARGET, maxdthreads und sleeptime definieren
      depth=1 ; cnt=0 ; sleeptime=5  # Wartezeit zum prüfen der gleichzeitig laufenden rsync-Prozesse
      cd "$SOURCE" || f_exit 1       # In das Quellverzeichnis wechseln
      R_TARGET="${TARGET}/${FILES_DIR}"  # Ordner für die gesicherten Dateien
      # nproc ist im Paket coreutils. Sollte auf allen Linux installationen verfügbar sein
      # Maximale Anzahl gleichzeitig laufender rsync-Prozesse (2 pro Kern)
      maxthreads=$(($(nproc)*2)) || maxthreads=5  # Fallback
      #maxthreads=2 # Maximale Anzahl gleichzeitig laufender rsync-Prozesse

      mapfile -t < "$EXFROM"  # Ausschlussliste einlesen
      mv --force "$EXFROM" "${_EXFROM:=${EXFROM}.$RANDOM}"  # Ausschlussliste für ./
      for i in "${!MAPFILE[@]}" ; do
        [[ "${MAPFILE[i]:0:1}" != "/" ]] && echo "${MAPFILE[i]}" >> "$EXFROM"  # Beginnt nicht mit "/"
      done  #; cat "$EXFROM" ; exit

      f_countdown_wait  # Countdown vor dem Start anzeigen
      while read dir ; do  # Alle Ordner in der Quelle bis zur $maxdepth tiefe
        # Make sure to ignore the parent folder
        DIR_C="${dir//[^\/]}"  # Alle Zeichen außer "/" löschen
        if [[ ${#DIR_C} -ge $depth ]] ; then  # Min. ${depth} "/"
          subfolder="${dir/.\/}"              # Führendes "./" entfernen

          for i in "${!MAPFILE[@]}" ; do  # Ausschlussliste verarbeitn
            # Ordner auslassen, wenn "foo" oder "foo/"
            [[ "${MAPFILE[$i]}" == "$subfolder" || "${MAPFILE[$i]}" == "${subfolder}/" ]] && continue 2
            if [[ "${MAPFILE[$i]:0:1}" == "/" ]] ; then  # Beginnt mit "/"
              ONLYTOP=${MAPFILE[$i]:1}  # Ohne führenden "/"
              if [[ "$(f_remove_slash "$ONLYTOP")" == "$subfolder" ]] ; then
                continue 2  # Ordner auslassen, wenn "/foo" oder "/foo/"
              else  # "/foo/bar"
                exdir="${ONLYTOP%%/*}"  #; echo "ONLYTOP aber mit Unterordner: /$ONLYTOP"
                if [[ "$exdir" == "$subfolder" ]] ; then
                  newex="/${ONLYTOP#*/}"  # "foo/bar" -> "/bar"
                  EXTRAEXCLUDE+=("--exclude=${newex}")
                  #echo "Eintrag: ${MAPFILE[$i]} ->EXDIR: /$exdir ->EXCLUDE: $newex"
                fi
              fi
            fi  # Beginnt mit "/"
          done

          if [[ ! -d "${R_TARGET}/${subfolder}" ]] ; then
            # Zielordner erstellun und Rechte/Eigentümer von Quelle übernehmen
            mkdir --parents "${R_TARGET}/${subfolder}"
            chown --reference="${SOURCE}/${subfolder}" "${R_TARGET}/${subfolder}"
            chmod --reference="${SOURCE}/${subfolder}" "${R_TARGET}/${subfolder}"
          fi

          # rsync-Prozesse auf $maxthreads begrenzen. Warten, wenn Anzahl erreicht ist
          while [[ $(pgrep --exact --count rsync) -ge $maxthreads ]] ; do
            echo "Es laufen bereits ${maxthreads} rsync-Processe. Warte ${sleeptime} sekunden..."
            sleep ${sleeptime}
          done

          ((cnt++)) ; echo -e -n "-> Starte rsync-Prozess Nr. $cnt ["
          # rsync für den aktuellen Unterordner im Hintergrund starten
          echo "rsync ${RSYNC_OPT[*]} --log-file=${LOG%.log}_$cnt.log --exclude-from=$EXFROM ${EXTRAEXCLUDE[*]} --backup-dir=${BAK_DIR}/${subfolder} ${SOURCE}/${subfolder}/ ${R_TARGET}/${subfolder}/" >> "${LOG%.log}_$cnt.log"
          nohup rsync "${RSYNC_OPT[@]}" --log-file="${LOG%.log}_$cnt.log" --exclude-from="$EXFROM" "${EXTRAEXCLUDE[@]}" --backup-dir="${BAK_DIR}/${subfolder}" \
                  "${SOURCE}/${subfolder}/" "${R_TARGET}/${subfolder}/" </dev/null >/dev/null 2>> "$ERRLOG" &
          JOBS[$!]="${TITLE}_$cnt" # Array-Element=PID; Inhalt=Profilname mit Zähler
          echo "$!]" ; sleep 0.1   # Kleine Wartezeit, damit nicht alle rsyncs auf einmal starten
          unset -v EXTRAEXCLUDE    # Zurücksetzen für den nächsten Durchlauf
        fi
      done < <(find . -maxdepth $depth -type d)  # Die < <(commands) Syntax verarbeitet alles im gleichen Prozess. Änderungen von globalen Variablen sind so möglich

      # Dateien in "./" werden im Ziel nicht gelöscht! (Vergleichen und manuell nach BAK_DIR verschieben)
      while IFS= read -r -d $'\0' file ; do
        if [[ ! -e "$file" ]] ; then  # Datei ist im Ziel aber nicht (mehr) auf der Quelle
          echo -e "-> Datei \"${file}\" nicht im Quellverzeichnis.\nVerschiebe nach $BAK_DIR"
          mv --force --verbose "${R_TARGET}/${file}" "$BAK_DIR" >> "${LOG%.log}_mv.log" 2>> "$ERRLOG"
        fi
      done < <(find "$R_TARGET" -maxdepth 1 -type f -printf '%P\0')  # %P = Datei ohne führendes "./" und ohne Pfad

      ((cnt++)) ; echo -e -n "-> Starte rsync-Prozess Nr. $cnt für Dateien im Stammordner ["
      # Dateien über maxdepth Tiefe ebenfalls mit rsync sichern
      echo "find . -maxdepth $depth -type f -print0 | rsync ${RSYNC_OPT[*]} --log-file=${LOG%.log}_$cnt.log --exclude-from=$_EXFROM --backup-dir=$BAK_DIR --files-from=- --from0 ./ ${R_TARGET}/" >> "${LOG%.log}_$cnt.log"
      rsync "${RSYNC_OPT[@]}" --log-file="${LOG%.log}_$cnt.log" --exclude-from="$_EXFROM" \
        --backup-dir="$BAK_DIR" --files-from=<(find . -maxdepth $depth -type f -print0) \
        --from0 ./ "${R_TARGET}/" >/dev/null 2>> "$ERRLOG"
      echo "$!]"
      RC=$? ; [[ $RC -ne 0 ]] && { RSYNCRC+=("$RC") ; RSYNCPROF+=("${TITLE}_$cnt") ;}  # Profilname und Fehlercode merken

      # Warten bis alle rsync-Prozesse beendet sind!
      for pid in "${!JOBS[@]}" ; do
        wait "$pid" ; RC="$?"  # wait liefert $? auch für bereits beendete Prozesse
        if [[ $RC -ne 0 ]] ; then
          echo -e "[${pid}] Beendet mit Fehler: ${RC}\n${JOBS[${pid}]}"
          RSYNCRC+=("$RC") ; RSYNCPROF+=("${JOBS[${pid}]}")  # Profilname und Fehlercode merken
        fi
      done

      # Logs zusammenfassen (Jeder rsync-Prozess hat ein eigenes Log erstellt)
      [[ -f "$LOG" ]] && mv --force "$LOG" "${LOG}.old"  # Log schon vorhanden
      OLDIFS="$IFS" ; IFS=$'\n'
      for log in ${LOG%.log}_*.log ; do
        echo "== Logfile: $log ==" >> "$LOG" ; cat "$log" >> "$LOG"
        rm "$log" &>/dev/null
      done ; IFS="$OLDIFS"

      # Funktion zum Löschen alter Backups aufrufen
      [[ -n "$DEL_OLD_BACKUP" ]] && f_del_old_backup "${BAK_DIR%/*}"

      # Funktion zum Löschen alter Dateien auf der Quelle ($1=Quelle $2=Ziel)
      [[ -n "$DEL_OLD_SOURCE" ]] && f_del_old_source "$SOURCE" "$R_TARGET"
    ;;
    *) # Üngültiger Modus
      echo -e "\e[1;41m FEHLER \e[0;1m Unbekannter Sicherungsmodus!\e[0m (\"${MODE}\")"
      f_exit 1
    ;;
  esac

  if [[ -s "$ERRLOG" ]] ; then  # Existiert und ist größer als 0 Byte
    ERRLOGS+=("$ERRLOG")        # Fehler-Log merken
  else
    rm "$ERRLOG" &>/dev/null    # Leeres Log löschen
  fi

  # Log-Datei und Ziel merken für Mail-Versand
  [[ -n "$MAILADRESS" ]] && { LOGFILES+=("$LOG") ; TARGETS+=("$TARGET") ; DEBUG echo -e "\nLOGFILES: ${LOGFILES[*]}\n\nTARGETS: ${TARGETS[*]}" ;}

  # Zuvor eingehängte FTP-Quelle wieder aushängen
  [[ -n "$UNMOUNTFTP" ]] && { umount "$FTPMNT" ; unset -v UNMOUNTFTP ;}

  [[ ${RC:-0} -ne 0 ]] && ERRTEXT="\e[91mmit Fehler ($RC) \e[0;1m"
  echo -e "\a\n\n\e[1mProfil \"${TITLE}\" wurde ${ERRTEXT}abgeschlossen\e[0m\nWeitere Informationen sowie Fehlermeldungen sind in der Datei:\n\"${LOG}\" gespeichert.\n"
  [[ -s "$ERRLOG" ]] && echo -e "Fehlermeldungen von rsync wurden in der Datei:\n\"${ERRLOG}\" gespeichert.\n"
  unset -v RC ERRTEXT           # $RC und $ERRTEXT zurücksetzen
done

# eMail senden
if [[ -n "$MAILADRESS" ]] ; then
  DEBUG set -x
  # Variablen
  ARCHIV="Logs_$(date +'%F-%H%M').tar.xz" # Archiv mit Datum und Zeit (kein :)
  TMP_ARCHIV="${TMPDIR}/${ARCHIV}"        # Pfad für das Archiv
  MAILFILE="${TMPDIR}/~Mail.txt"          # Mailfile im Arbeitsspeicher oder /tmp
  SUBJECT="Sicherungs-Bericht von $SELF_NAME auf $HOSTNAME" # Betreff der Mail
  : "${MAXLOGSIZE:=$((1024*1024))}"       # Wenn leer dann default 1 MB

  if [[ $MAXLOGSIZE -gt 0 ]] ; then       # Wurde nicht deaktiviert
    # Log(s) packen
    tar --create --absolute-names --auto-compress --file="$TMP_ARCHIV" "${LOGFILES[@]}" "${ERRLOGS[@]}"
    FILESIZE=$(stat -c %s "$TMP_ARCHIV")  # Größe des Archivs
    if [[ $FILESIZE -gt $MAXLOGSIZE ]] ; then
      rm "$TMP_ARCHIV" &>/dev/null        # Archiv ist zu groß
      TMP_ARCHIV="${TMP_ARCHIV}.txt"      # Info-Datei wenn das Archiv zu groß ist
      echo "Das Archiv mit den Logdatei(en) ist zu groß für den Versand per eMail." > "$TMP_ARCHIV"
      echo "Der eingestellte Wert für die Maximalgröße ist $MAXLOGSIZE Bytes" >> "$TMP_ARCHIV"
      echo -e "\n==> Liste der lokal angelegten Log-Datei(en):" >> "$TMP_ARCHIV"
      for file in "${LOGFILES[@]}" "${ERRLOGS[@]}" ; do
        echo "$file" >> "$TMP_ARCHIV"
      done
    fi
  else # MAXLOGSIZE=0
    TMP_ARCHIV="${TMP_ARCHIV}.txt"        # Info-Datei
    echo "Das Senden von Logdateien ist deaktiviert (MAXLOGSZE=0)." > "$TMP_ARCHIV"
    echo -e "\n==> Liste der lokal angelegten Log-Datei(en):" >> "$TMP_ARCHIV"
    for file in "${LOGFILES[@]}" "${ERRLOGS[@]}" ; do
      echo "$file" >> "$TMP_ARCHIV"
    done
  fi

  # Text der eMail erzeugen
  echo -e "Sicherungs-Bericht von $SELF_NAME [#${VERSION}] auf ${HOSTNAME}\n" > "$MAILFILE"
  echo -e -n "Die letzte Sicherung wurde beendet. " >> "$MAILFILE"
  [[ ${#LOGFILES[@]} -ge 1 ]] && echo "Es wurde(n) ${#LOGFILES[@]} Log-Datei(en) erstellt." >> "$MAILFILE"

  if [[ ${#ERRLOGS[@]} -ge 1 ]] ; then
    echo -e "\n==> Zusätzlich wurde(n) ${#ERRLOGS[@]} Fehler-Log(s) erstellt!" >> "$MAILFILE"
    SUBJECT="FEHLER bei Sicherung von $SELF_NAME auf $HOSTNAME" # Neuer Betreff der Mail
  fi

  if [[ ${#RSYNCRC[@]} -ge 1 && "$SHOWERRORS" == "true" ]] ; then  # Profile mit Fehlern anzeigen
    echo -e "\n==> Profil(e) mit Fehler(n):" >> "$MAILFILE"
    for i in "${!RSYNCRC[@]}" ; do
      echo "${RSYNCPROF[$i]} (${RSYNCRC[$i]})" >> "$MAILFILE"
    done
  fi # SHOWERRORS

  if [[ "$SHOWOS" == "true" ]] ; then
    if [[ -f "/etc/os-release" ]] ; then
      while read -r line ; do
        if [[ ${line^^} =~ PRETTY_NAME ]] ; then
          OSNAME=${line/*=} ; OSNAME=${OSNAME//\"/}
          break
        fi
      done < /etc/os-release
    fi
    echo -e "\n==> Auf $HOSTNAME verwendetes Bertiebssystem:\n${OSNAME:-"Unbekannt"}" >> "$MAILFILE"
  fi  # SHOWOS

  [[ "$SHOWOPTIONS" == "true" ]] && echo -e "\n==> Folgende Optionen wurden verwendet:\n$*" >> "$MAILFILE"

  for i in "${!TARGETS[@]}" ; do
    if [[ "$SHOWUSAGE" == "true" ]] ; then  # Anzeige ist abschltbar in der *.conf
      mapfile -t < <(df -Ph "${TARGETS[$i]}")  # Ausgabe von df in Array (Zwei Zeilen)
      TARGETLINE=(${MAPFILE[1]}) ; TARGETDEV=${TARGETLINE[0]}  # Erstes Element ist das Device
      if [[ ! "${TARGETDEVS[@]}" =~ $TARGETDEV ]] ; then
        TARGETDEVS+=("$TARGETDEV")
        echo -e "\n==> Status des Sicherungsziels ($TARGETDEV):" >> "$MAILFILE"
        echo -e "${MAPFILE[0]}\n${MAPFILE[1]}" >> "$MAILFILE"
      fi
    fi  # SHOWUSAGE
    if [[ "$SHOWCONTENT" == "true" ]] ; then  # Auflistung ist abschltbar in der *.conf
      LOGDIR="${LOGFILES[$i]%/*}" ; [[ "${LOGDIRS[@]}" =~ $LOGDIR ]] && continue
      LOGDIRS+=("$LOGDIR")
      echo -e "\n==> Inhalt von ${LOGDIR}:" >> "$MAILFILE"
      ls -l --human-readable "$LOGDIR" >> "$MAILFILE"
      # Anzeige der Belegung des Sicherungsverzeichnisses und Unterordner
      echo -e "\n==> Belegung von ${LOGDIR}:" >> "$MAILFILE"
      du --human-readable --summarize "$LOGDIR" >> "$MAILFILE"
      du --human-readable --summarize "${LOGDIR}/${FILES_DIR}" >> "$MAILFILE"
      du --human-readable --summarize "${BAK_DIR%/*}" >> "$MAILFILE"
    fi  # SHOWCONTENT
  done

  # eMail nur, wenn (a) MAILONLYERRORS=true und Fehler vorhanden sind oder (b) MAILONLYERRORS nicht true
  if [[ ${#ERRLOGS[@]} -ge 1 && "$MAILONLYERRORS" == "true" || "$MAILONLYERRORS" != "true" ]] ; then
    # eMail versenden
    case $MAILPROG in
      mpack)  # Sende Mail mit mpack via ssmtp
        mpack -s "$SUBJECT" -d "$MAILFILE" "$TMP_ARCHIV" "$MAILADRESS" # Kann "root" sein, wenn in sSMTP konfiguriert
      ;;
      sendmail)  # Variante mit sendmail und uuencode
        mail_to_send="${TMPDIR}/~mail_to_send"
        echo "Subject: $SUBJECT" > "$mail_to_send" ; cat "$MAILFILE" >> "$mail_to_send"
        #cat "$TMP_ARCHIV" | uuencode "$ARCHIV" >> "$mail_to_send"
        uuencode "$TMP_ARCHIV" "$ARCHIV" >> "$mail_to_send"
        sendmail "$MAILADRESS" < "$mail_to_send"
        rm "$mail_to_send"
      ;;
      send[Ee]mail)  # Variante mit "sendEmail". Keine " für die Variable ${USETLS} verwenden!
        sendEmail -f "$MAILSENDER" -t "$MAILADRESS" -u "$SUBJECT" -o message-file="$MAILFILE" -a "$TMP_ARCHIV" \
          -o message-charset=utf-8 -s "${MAILSERVER}:${MAILPORT}" -xu "$MAILUSER" -xp "$MAILPASS" ${USETLS}
      ;;
      e[Mm]ail)  # Sende Mail mit eMail (https://github.com/deanproxy/eMail)
        email -s "$SUBJECT" -attach "$TMP_ARCHIV" "$MAILADRESS" < "$MAILFILE"  # Die auführbare Datei ist 'email'
      ;;
      *) echo -e "\nUnbekanntes Mailprogramm: \"${MAILPROG}\"" ;;
    esac
    RC=$? ; [[ ${RC:-0} -eq 0 ]] && echo -e "\n==> Sicherungs-Bericht wurde mit \"${MAILPROG}\" an $MAILADRESS versendet.\n    Es wurde(n) ${#LOGFILES[@]} Logdatei(en) angelegt."
  fi  # MAILONLYERRORS
  DEBUG set +x
fi

# Zuvor eingehängte(s) Sicherungsziel(e) wieder aushängen
if [[ ${#UNMOUNT[@]} -ge 1 ]] ; then
  for volume in "${UNMOUNT[@]}" ; do
    umount --force "$volume"
  done
fi

### POST_ACTION
if [[ -n "$POST_ACTION" ]] ; then
  echo "Führe POST_ACTION-Befehl(e) aus..."
  eval "$POST_ACTION"
  [[ $? -gt 0 ]] && echo "Fehler beim Ausführen von \"${POST_ACTION}\"!" && sleep 10
fi

# Ggf. Herunterfahren
if [[ -n "$SHUTDOWN" ]] ; then
  # Möglichkeit, das automatische Herunterfahren noch abzubrechen
  "$NOTIFY" "Sicherung(en) abgeschlossen. ACHTUNG: Der Computer wird in 5 Minuten heruntergefahren. Führen Sie \"kill -9 $(pgrep "${0##*/}")\" aus, um das Herunterfahren abzubrechen."
  sleep 1
  echo "This System is going DOWN for System halt in 5 minutes! Run \"kill -9 $(pgrep "${0##*/}")\" to cancel shutdown." | $WALL
  echo -e "\a\e[1;41m ACHTUNG \e[0m Der Computer wird in 5 Minuten heruntergefahren.\n"
  echo -e "Bitte speichern Sie jetzt alle geöffneten Dokumente oder drücken Sie \e[1m[Strg] + [C]\e[0m,\nfalls der Computer nicht heruntergefahren werden soll.\n"
  sleep 5m
  # Verschiedene Befehle zum Herunterfahren mit Benutzerrechten [muss evtl. an das eigene System angepasst werden!]
  # Alle Systeme mit HAL || GNOME DBUS || KDE DBUS || GNOME || KDE
  # Root-Rechte i. d. R. erforderlich für "halt" und "shutdown"!
  dbus-send --print-reply --system --dest=org.freedesktop.Hal /org/freedesktop/Hal/devices/computer org.freedesktop.Hal.Device.SystemPowerManagement.Shutdown || \
  dbus-send --print-reply --dest=org.gnome.SessionManager /org/gnome/SessionManager org.gnome.SessionManager.RequestShutdown || \
  dbus-send --print-reply --dest=org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 2 2 || \
  gnome-power-cmd shutdown || dcop ksmserver ksmserver logout 0 2 2 || \
  halt || shutdown -h now
else
  "$NOTIFY" "Sicherung(en) abgeschlossen."
fi

# Aufräumen und beenden
f_exit
