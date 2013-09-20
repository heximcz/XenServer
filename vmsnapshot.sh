#!/bin/bash

# lock file - only one script running in same time
LOCKFILE="/tmp/snapshotbh.lock"
# Input file, FORMAT: <day of week (1..7) 1 is Monday>,<vm uuid>,<time(HH:MM)>,<how much of snapshots be rotate>
# 4,2w1ahe53-3330-36tc-wce6-xf5dcee3a1c1,23:30,1
DATAFILE='/root/vps-data.txt'
# logovaci soubor na chyby
LOGFILE='/var/log/snapshots/vmsnapshot.log'
# aktualni cas pri spusteni scriptu
CURRENT=$(date +%s)
# aktualni den v tydnu, 1=Pondeli..7=Nedele
CURRENTDAY=$(date +%u)

# check lockfile - nesahat
if [ -f $LOCKFILE ]; then
 echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] Lockfile $LOCKFILE exists, process is still running! Nothing to do." >> $LOGFILE
 exit 1
fi
touch $LOCKFILE

# generuj string datum + random pro nazev snapshotu, orginalni nazev autom. sn. je : 20130904-0120
function snName(){
  rnd=$(( $RANDOM % 1000 + 1000 | bc ))
  dt=$(date +'%Y%m%d')
  echo "$dt-$rnd"
}
# uloz start do logu
echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Scheduler start ..." >> $LOGFILE

# read and parse data for snapshots
# 4,2f1abe53-7130-344c-2ce6-cf5dc9e7a1c1,23:30,1
while IFS=',' read -r snDay vmUuid snTime snCount
do
  # je spravny den v tydnu pro zalohu ?
  if [[ $CURRENTDAY -ne $snDay ]]; then
    continue
  fi
  # test delky uuid - TODO send email ?
  if [ ${#vmUuid} -ne 36 ]; then
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Warning] Bad key in datafile: $vmUuid" >> $LOGFILE
    continue
  fi
  # je spravny cas s toleranci 14 minut
  TARGET=$(date +%s -d "$(date +'%Y-%m-%d') $snTime:00")
  MINUTES=$(( ($CURRENT - $TARGET) / 60 ))
  if [ $MINUTES -le 14 ] && [ $MINUTES -ge 0 ]; then
    # proved snapshot
    snCreateOut=$(xe vm-snapshot vm=$vmUuid new-name-label=$(snName) new-name-description=auto)
    if [ ${#snCreateOut} -eq 36 ]; then
      echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Snapshot creted succesfully width uuid: $snCreateOut" >> $LOGFILE
    else
      echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] Snapshot not creted for vm uuid: $vmUuid" >> $LOGFILE
    fi
    # spocitej kolik ma vm shedule snapshotu, jestli nad limit, tak nejstarsi smaz
    snCountAll=$(xe snapshot-list snapshot-of=$vmUuid params=uuid is-a-snapshot=true name-description=auto | grep uuid | wc -l)
    if [[ $snCountAll -gt $snCount  ]]; then
      # najdi nejstarsi snapshot
      vmOldTime=$(xe snapshot-list snapshot-of=$vmUuid is-a-snapshot=true power-state=halted name-description=auto  params=snapshot-time,uuid,snapshot-of | grep snapshot-time | awk '{print $4}' | sort | head -1)
      vmUuidForDel=$(xe snapshot-list snapshot-of=$vmUuid is-a-snapshot=true power-state=halted snapshot-time=$vmOldTime params=uuid | awk '{print $5}' | head -1)
      if [ ${#vmUuidForDel} -eq 36 ]; then
        # tak ho smaz
        vmDeleteState=$(xe snapshot-uninstall snapshot-uuid=$vmUuidForDel force=true | tail -n 1)
        if [[ $vmDeleteState == "All objects destroyed" ]]; then
          echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Snapshot deleted succesfully width uuid: $vmUuidForDel, from time: $vmOldTime" >> $LOGFILE
        else
          echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] Snapshot not deleted uuid: $vmUuidForDel, from time: $vmOldTime, OUTPUT from snapshot-uninstall: $vmDeleteState" >> $LOGFILE
        fi
      else
        # nejaka chyba v uuid !
        echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] !!! Snapshot for delete find but wrong uuid: $vmUuidForDel, from time: $vmOldTime" >> $LOGFILE
      fi
    fi
  fi
done < "$DATAFILE"

# delete lock file
rm $LOCKFILE

# uloz konec do logu
echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Scheduler stop ..." >> $LOGFILE
