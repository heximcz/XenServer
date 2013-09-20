#!/bin/bash

# datafile
DATAFILE="/root/vps-data.txt"
# log file
LOGFILE='/var/log/snapshots/vmsnapshot.log'
# lock file
LOCKFILE="/tmp/snapshotbh.lock"
# json data
JSONDATA="/root/vps-snapshot-list.json"
# test file
TESTFILE="/root/testdata.txt"

# download and parse json to test file
curl -s -X GET -k -u <login>:<password> <URL> > $JSONDATA
sed 's/"//g' $JSONDATA | sed 's/hour://g' | sed 's/uuid://g' | sed 's/day://g' | sed 's/id://g' | sed 's/\[{//g' | sed 's/}\]//g' | sed 's/count://g' | sed 's/},{/\n/g' > $TESTFILE
rm -f $JSONDATA

# test data in test file
while IFS=',' read -r snDay vmUuid snTime snCount
do
  # test uuid lenght and sum of strings "snDay vmUuid snTime", "snCount" is variable lenght
  inDataLen=$snDay$vmUuid$snTime
  if [ ${#vmUuid} -ne 36 ] || [ ${#inDataLen} -ne 42 ]; then
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] !! Sync datafile error:" >> $LOGFILE
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] Bad string lenght in datafile ater CURL download: $vmUuid , $snDay$vmUuid$snTime" >> $LOGFILE
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Error] !! Sync interrupted" >> $LOGFILE
    rm -f $TESTFILE
    exit 1
  fi
done < "$TESTFILE"

# check lockfile of vmsnapshot.sh script
if [ -f $LOCKFILE ]; then
  echo $(date +%Y-%m-%d' '%H:%M:%S) "[Warning] snapshoting run now, skip datasync to the next time." >> $LOGFILE
  rm -f $TESTFILE
  exit 1
else
  # create new data file if no exist
  if ! [ -f $DATAFILE ]; then
    mv -f $TESTFILE $DATAFILE
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Datafile synchronized." >> $LOGFILE
  # compare old and new data files, new data ?
  elif ! diff $TESTFILE $DATAFILE >/dev/null; then
    mv -f $TESTFILE $DATAFILE
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] Datafile synchronized." >> $LOGFILE
  else
    echo $(date +%Y-%m-%d' '%H:%M:%S) "[Info] NoSync: Data are the same, nothing to sync" >> $LOGFILE
  fi
fi

rm -f $TESTFILE

