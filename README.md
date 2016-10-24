# MV_Backup
RSYNC Backup Skript

Auf der Suche nach einer einfachen Backup-Lösung für meine Linux PC's (VDR und Debian-Server) bin ich irgendwann auch das Backup-Skript von 321tux.de gestoßen. Nach dem mit Hilfe des Betreibers ein kleineres Problem mit dem Skript gelöst wurde, habe ich begonnen einige Erweiterungen einzubauen.

![Hilfe](help.png)

Das Skript benötigt "Bash" ab Version 4. Ich versuche wenn möglich auf exteren Programme wie sed oder awk zu verzichten. Trotzdem benötigt das Skript Programme wie z. B. find oder df. Konfigurationsabhängig werden noch mount oder curlftpfs benötigt.
Die verwendung geschieht wie immer auf eigene Gefahr. Wer Fehler findet, kann hier ein Ticket eröffnen oder im DEB eine Anfrage stellen. Auch neue Funktionen baue ich gerne ein, so sie mir denn als sinnvoll erscheinen.

Die Konfiguration erfolgt über die .conf welche viele (hoffentlich) aussagekräftige Kommentare enthält.
