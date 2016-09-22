#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#                                                                                       #
# = = = = = = = = = = = = = = = = = = RSYNC BACKUP  = = = = = = = = = = = = = = = = = = #
#                                                                                       #
# Autor:    JaiBee, http://www.321tux.de                                                #
# Datum:    12.06.2011                                                                  #
# Version:  0.99                                                                        #
# Lizenz:   Creative Commons "Namensnennung-Nicht-kommerziell-                          #
#           Weitergabe unter gleichen Bedingungen 3.0 Unported "                        #
#           [ http://creativecommons.org/licenses/by-nc-sa/3.0/deed.de ]                #
#                                                                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Dieses Skript sichert / synchronisiert Verzeichnisse mit rsync.
# Dabei können beliebig viele Profile konfiguriert oder die Pfade direkt an das Skript übergeben werden.
# Eine kurze Anleitung kann mit der Option -h aufgerufen werden.


############################### ALLGEMEINE KONFIGURATION ################################

# RSYNC_OPT    Optionen für rsync; Verzeichnisse müssen und dürfen nicht angegeben werden

RSYNC_OPT_NORMAL="-savPbh --delete --numeric-ids --stats"
RSYNC_OPT_SNAPSHOT='-av'


############################### KONFIGURATION EINLESEN ################################

# Suche Konfig im aktuellen Verzeichnis, im Verzeichnis des Skripts und im eigenen etc
CDIRS=". ${0%/*} $HOME/etc"
CNAME="backup-321tux.conf"
F=0

for C in $CDIRS
do
    CONF=$C/$CNAME
    [ -r $CONF ] && {
        F=1
        break
    }
done

(( ! F )) && {
    echo >&2 "'$CNAME' konnte nicht in $CDIRS gefunden werden!"
    exit 1
}

unset C CDIRS CNAME F

# Konfiguration laden
. $CONF

function func_bak_dir(){
  [ "$BAK_DIR" = "default" -o "$BAK_DIR" = "" ] && BAK_DIR="$TARGET/Geloeschte Dateien/$(date +%F)/"
}


# Info: wenn das Skript startet, werden die Werte aus den Arrays ausgelesen und in Variablen gespeichert.
# title[n]  -> $TITLE   |   arg[n]    -> $ARG       |   rsync_opt[n] -> $RSYNC_OPT  |   log[n]    -> $LOG
# source[n] -> $SOURCE  |   target[n] -> $TARGET    |   exfrom[n]    -> $EXFROM


###################################### FUNKTIONEN #######################################

# Wird in der Konsole angezeigt, wenn eine Option nicht angegeben oder definiert wurde
function func_help(){
    echo -e "Aufruf: \033[1m$0 \033[34m-p\033[0m \033[1;36mARGUMENT\033[0m [\033[1;34m-p\033[0m \033[1;36mARGUMENT\033[0m]"
    echo -e "        \033[1m$0 \033[34m-m\033[0m \033[1;36mQUELLE(n)\033[0m \033[1;36mZIEL\033[0m"
    echo
    echo -e "\033[4merforderlich\033[0m"
    for i in $(seq ${#arg[*]}); do echo -e "  \033[1;34m-p\033[0m \033[1;36m${arg[$i]}\033[0m   Profil \"${title[$i]}\""; done
    echo -e "oder\n  \033[1;34m-a\033[0m    alle Backup-Profile"
    echo -e "oder\n  \033[1;34m-m\033[0m    Verzeichnisse manuell angeben"
    echo
    echo -e "\033[4moptional\033[0m"
    echo -e "  \033[1;34m-s\033[0m  PC nach Beendigung automatisch herunterfahren (benötigt u.U. Root-Rechte)"
    echo -e "  \033[1;34m-h\033[0m  Hilfe anzeigen"
    echo
    echo -e "\033[4mBeispiele\033[0m"
    echo -e "  \033[32mProfil \"${title[2]}\"\033[0m starten und den Computer anschließend \033[31mherunterfahren\033[0m:"
    echo -e "   $0 \033[32m-p${arg[2]}\033[0m \033[31m-s\033[0m\n"
    echo -e "  \033[33m\"/tmp/Quelle1/\"\033[0m und \033[35m\"/Leer zeichen2/\"\033[0m mit \033[36m\"/media/extern\"\033[0m synchronisieren; anschließend \033[31mherunterfahren\033[0m:"
    echo -e "   $0 \033[31m-s\033[0;4mm\033[0m \033[33m/tmp/Quelle1\033[0m \033[4m\"\033[0;35m/Leer zeichen2\033[0;4m\"\033[0m \033[36m/media/extern\033[0m"
    echo

    func_exit
}

function func_exit(){
    rm ${exfrom[*]} 2>/dev/null
    exit 1
}


function func_settings(){
    if [[ "$PROFIL" != "customBak" ]]; then
        # Benötigten Werte aus dem Array holen
        for i in $(seq ${#arg[*]}); do                              # Anzahl der vorhandenen Profile ermitteln
            if [[ "${arg[$i]}" == "$PROFIL" ]]; then                # wenn das gewünschte Profil gefunden wurde
                TITLE="${title[$i]}";       ARG="${arg[$i]}"
                SOURCE="${source[$i]}";     TARGET="${target[$i]}"
                LOG="${log[$i]}";           EXFROM="${exfrom[$i]}"
                MODE="${mode[$i]}"          DELDIR="${deldir[$i]}"
                MOUNT="${mount[$i]}"
                [[ "${rsync_opt[$i]}" != "" ]] && RSYNC_OPT="${rsync_opt[$i]}" || {
                    case $MODE in
                        [Ss][Nn][Aa][Pp]*)
                            MODE=S
                            RSYNC_OPT="$RSYNC_OPT_SNAPSHOT";;
                        *)  MODE=N
                            RSYNC_OPT="$RSYNC_OPT_NORMAL";;
                    esac
                }

                touch "$LOG" || {
                    echo >&2 "'$LOG' kann nicht geschrieben werden!"
                    func_exit;
                }
            fi
        done
    fi
    [ "$SOURCE" == "/" ] && TARGET="${TARGET}/ROOTFS"               # Workaround für "/"
}

######################################### START #########################################

# Wenn eine grafische Oberfläche vorhanden ist, wird u.a. "notify-send" für Benachrichtigungen verwendet, ansonsten immer "echo"
NOTIFY="echo"
[ -n "$DISPLAY" ] && NOTIFY="notify-send"

tty -s && clear
echo -e "\033[44m \033[0m\033[1m RSYNC BACKUP\033[0m\n\033[44m \033[0m 2011 by JaiBee, http://www.321tux.de/\n";

while getopts ":p:am:sh" opt
do
    case $opt in
        p) for i in "$OPTARG"; do P="$P $i"; done ;;    # bestimmte(s) Profil(e)
        a) P=${arg[*]} ;;                               # alle Profile
        m) # eigene Verzeichnisse an das Skript übergeben
            for i in "$@"; do                           # letzte Pfad als Zielverzeichnis
                [ -d "$i" ] && TARGET="$i";
            done
            for i in "$@"; do                           # alle übergebenen Verzeichnisse außer $TARGET als Quelle
                [[ -d "$i" && "$i" != "$TARGET" ]] && SOURCE="$SOURCE \"$i\""
            done
            TARGET="$(echo $TARGET | sed -e 's/\/$//')" # Slash am Ende entfernen
            P="customBak";                  TITLE="Custom Backup"
            LOG="$TARGET/$TITLE-log.txt";   MOUNT="" ;;
        s) SHUTDOWN=0 ;;                                # Herunterfahren gewählt
        h) func_help ;;                                 # Hilfe anzeigen
        ?) echo -e "\033[1;41m FEHLER \033[0;1m Option ungültig.\033[0m\n" && func_help ;;
    esac
done

# Sind die benötigen Programme installiert?
which rsync mktemp wall sed $NOTIFY > /dev/null || { echo "Sie benötigen die Programme rsync, mktemp, wall, sed und $NOTIFY zur Ausführung dieses Skriptes."; func_exit; }

# wenn $P leer ist, wurde die Option -p oder -a nicht angegeben
[[ -z "$P" ]] && echo -e "\033[1;41m FEHLER \033[0;1m es wurde kein Profil gewählt\033[0m\n" && func_help

# folgende Zeile auskommentieren, falls zum Herunterfahren des Computers Root-Rechte erforderlich sind
#[[ "$SHUTDOWN" == "0" && "$(whoami)" != "root" ]] && echo -e "\033[1;41m FEHLER \033[0;1m Zum automatischen Herunterfahren sind Root-Rechte erforderlich.\033[0m\n" && func_help

[ "$SHUTDOWN" == "0" ] && echo -e "  \033[1;31mDer Computer wird nach Durchführung des Backups automatisch heruntergefahren!\033[0m"

for PROFIL in $P; do
    func_settings
    func_bak_dir

    # /ROOTFS aus $BAK_DIR entfernen
    BAK_DIR="${BAK_DIR//\/ROOTFS/}"

    # wurden der Option -b gültige Argument zugewiesen?
    [[ "$PROFIL" != "$ARG" && "$PROFIL" != "customBak" ]] && echo -e "\033[1;41m FEHLER \033[0;1m -p wurde nicht korrekt definiert.\033[0m\n" && func_help

    # Konfiguration zu allen gewählten Profilen anzeigen
    echo -e "  \033[4m\nKonfiguration von \033[1m$TITLE\033[0m"
    echo -e "\033[46m \033[0m Quellverzeichnis(se):\033[1m\t$SOURCE\033[0m\n\033[46m \033[0m Zielverzeichnis:\033[1m\t$TARGET\033[0m"
    echo -e "\033[46m \033[0m Log-Datei:\033[1m\t\t$LOG\033[0m"
    if [[ "$PROFIL" != "customBak" ]]; then echo -e "\033[46m \033[0m Exclude:"; sed 's/^/\t\t\t/' $EXFROM ; fi
done

for PROFIL in $P; do
    func_settings

    # ist die Festplatte eingebunden?
    [[ "$TARGET" == "$MOUNT"* && ! $(mount | grep "$MOUNT") ]] && echo -e "\033[1;41m FEHLER \033[0;1m Die Festplatte ist nicht eingebunden.\033[0m (\"$MOUNT\")" && func_exit

    # div. Variablenvorbelegungen...
    EF="--exclude-from=$EXFROM"

    # je nach MODE Backup durchfuehren
    case $MODE in
        # Snapshot Backup
        S)
            # temporaere Verzeichnisse, die von fehlgeschlagenen Backups noch vorhanden sind loeschen
            rm -rf $TARGET/tmp_????-??-??* 2>/dev/null

            # Zielverzeichnis ermitteln: wenn erstes Backup des Tages, dann ohne Uhrzeit
            for TODAY in `date +%Y-%m-%d` `date +%Y-%m-%d_%H-%M`; do [ ! -e $TARGET/$TODAY ] && break; done
            BACKUPDIR=$TARGET/$TODAY
            TMPBAKDIR=$TARGET/tmp_$TODAY

            # Verzeichnis des letzten Backups ermitteln
            LASTBACKUP=`ls -1d $TARGET/????-??-??* 2>/dev/null | tail -1`

            [ "$LASTBACKUP" != "" ] && {
                # mittels dryRun ueberpruefen, ob sich etwas geaendert hat
                echo "Pruefe, ob es Aenderungen zu $LASTBACKUP gibt..."
                TFL="$(mktemp -t "tmp.rsync.XXXX")"
                rsync $RSYNC_OPT -n $EF --link-dest="$LASTBACKUP" $SOURCE "$TMPBAKDIR" >$TFL 2>&1

                # wenn es keine Unterschiede gibt, ist die 4. Zeile immer diese:
                # sent nn bytes  received nn bytes  n.nn bytes/sec
                head -4 $TFL | tail -1 | grep -q "sent.*bytes.*received.*bytes.*" && {
                     rm $TFL 2>/dev/null
                     echo "Keine Aenderung! Kein Backup erforderlich!"
                     echo "Aktuelles Backup: $LASTBACKUP"
                     continue
                } || rm $TFL 2>/dev/null
            }

            echo -e "\n\033[1m$TITLE wird in 5 Sekunden gestartet.\033[0m"
            echo -e "\033[46m \033[0m Zum Abbrechen [Strg] + [C] drücken\n\033[46m \033[0m Zum Pausieren [Strg] + [Z] drücken (Fortsetzen mit \"fg\")\n"
            sleep 5
            $NOTIFY "Backup startet (Profil: \"$TITLE\")"

            rsync $RSYNC_OPT --log-file="$LOG" $EF --link-dest="$LASTBACKUP" $SOURCE "$TMPBAKDIR" && {
                 # wenn Backup erfolgreich, Verzeichnis umbenennen
                 mv $TMPBAKDIR $BACKUPDIR
            } || echo "Fehler - rsync return code = $?"
            ;;

        # Normales Backup
        N)  # ggf. Zielverzeichnisse erstellen
            [ ! -d "$TARGET" ]  && { mkdir -vp "$TARGET" || func_exit ;}
            [ ! -d "$BAK_DIR" ] && { mkdir -p "$BAK_DIR" || func_exit ;}

            echo -e "\n\033[1m$TITLE wird in 5 Sekunden gestartet.\033[0m"
            echo -e "\033[46m \033[0m Zum Abbrechen [Strg] + [C] drücken\n\033[46m \033[0m Zum Pausieren [Strg] + [Z] drücken (Fortsetzen mit \"fg\")\n"
            sleep 5
            $NOTIFY "Backup startet (Profil: \"$TITLE\")"

            # Backup mit rsync starten
            eval rsync $RSYNC_OPT --log-file=\"$LOG\" $EF --backup-dir=\"$BAK_DIR\" $SOURCE \"$TARGET\"
            ;;

        *)  echo >&2 "???"
            func_exit
            ;;
    esac

    echo -e "\a\n\n\033[1m$TITLE wurde abgeschlossen\033[0m\nWeitere Informationen sowie Fehlermeldungen sind in der Datei \"$LOG\" gespeichert.\n"
done

rm ${exfrom[*]} 2>/dev/null

# ggf. Herunterfahren
if [ "$SHUTDOWN" == "0" ] ; then
    # Möglichkeit, das automatische Herunterfahren noch abzubrechen
    $NOTIFY "Backup(s) abgeschlossen. ACHTUNG: Der Computer wird in 5 Minuten heruntergefahren. Führen Sie \"kill -9 $(ps -A | grep -m1 "$(basename "$0")" | cut -d " " -f2)\" aus, um das Herunterfahren abzubrechen."
    sleep 1
    echo "This System is going DOWN for System halt in 5 minutes! Run \"kill -9 $(ps -A | grep -m1 "$(basename "$0")" | cut -d " " -f2)\" to  cancel shutdown." | wall
    echo -en "\a\033[1;41m ACHTUNG \033[0m Der Computer wird in 5 Minuten heruntergefahren.\n\n"
    echo -e "Bitte speichern Sie jetzt alle geöffneten Dokumente oder drücken Sie \033[1m[Strg] + [C]\033[0m,\nfalls der Computer nicht heruntergefahren werden soll.\n"
    sleep 5m
    # verschiedene Befehle zum Herunterfahren mit Benutzerrechten [muss evtl. an das eigene System angepasst werden!]
    # Alle Systeme mit HAL || GNOME DBUS || KDE DBUS || GNOME || KDE
    # Root-Rechte i.d.R. erforderlich für "halt" und "shutdown"!
    dbus-send --print-reply --system --dest=org.freedesktop.Hal /org/freedesktop/Hal/devices/computer org.freedesktop.Hal.Device.SystemPowerManagement.Shutdown || \
    dbus-send --print-reply --dest=org.gnome.SessionManager /org/gnome/SessionManager org.gnome.SessionManager.RequestShutdown || \
    dbus-send --print-reply --dest=org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 2 2 || \
    gnome-power-cmd shutdown || dcop ksmserver ksmserver logout 0 2 2 || \
    halt || shutdown -h now
else
    $NOTIFY "Backup(s) abgeschlossen."
fi
