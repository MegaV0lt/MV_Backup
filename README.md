# MV_Backup
RSYNC Backup Skript

Ein Backup-Skript für die Linux-Konsole (Bash/Terminal)

Auf der Suche nach einer einfachen Backup-Lösung für meine Linux PC's (VDR und Debian-Server) bin ich irgendwann auch das Backup-Skript von 321tux.de gestoßen. Nach dem mit Hilfe des Betreibers ein kleineres Problem mit dem Skript gelöst wurde, habe ich begonnen einige Erweiterungen einzubauen.

![Hilfe](help.png)

So sieht eine eMail (Abschaltbar oder nur im Fehlerfall) nach erfolger Sicherung aus:
![Sicherungs-Bericht](Sicherungs-bericht.png)

Das Skript benötigt "GNU Bash" ab Version 4. Ich versuche wenn möglich auf externe Programme wie sed oder awk zu verzichten. Trotzdem benötigt das Skript einige weitere externe Programme. Konfigurationsabhängig werden noch mount oder curlftpfs benötigt.
Die Verwendung geschieht wie immer auf eigene Gefahr. Wer Fehler findet, kann hier ein Ticket eröffnen oder im DEB eine Anfrage stellen. Auch neue Funktionen baue ich gerne ein, so sie mir denn als sinnvoll erscheinen.

Benötigt werden (U. a. Konfigurationsabhängig):
- GNU Bash ab Version 4
- rsync (Zum Syncronisieren der Dateien)
- find
- df
- grep
- curlftpfs (Sicherung von FTP)
- nproc (Im Paket coreutils; Für den Multi-rsync-Modus)
- sendmail, uuencode, mpack, sendEmail oder email (Für eMailversand; je nach Konfiguration)
- tar (Um gepackte Log-Dateien per eMail zu senden)
- ...

Die Konfiguration erfolgt über die .conf welche viele (hoffentlich) aussagekräftige Kommentare enthält.

Support im Forum (DEB): http://j.mp/1TblNNj oder hier im GIT
