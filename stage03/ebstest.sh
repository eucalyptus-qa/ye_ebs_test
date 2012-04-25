#!/bin/bash

#####################################
##       Eucalyptus EBS test       ##
#####################################
SCRIPT="${0##*/}"

## Choice of command toolset. Default is euca2ools. Use "ec2" for ec2 tools.
TOOLSET=euca
#TOOLSET=ec2

#PRIVATEKEY=mykey0.priv

## The tool for running a command with a timeout, using a script from
## http://www.bashcookbook.com/bashinfo/source/bash-4.0/examples/scripts/timeout3
TIMEOUT="./timeout3 -t"

VOLSIZE=1 # GB

TRIES=200 # times
INTERVAL=2 # seconds

## Logging functions
timestamp() {
  local date=`date +"%Y-%m-%d %H:%M:%S"`
  printf "[$date]\t"
}

TESTREPORT="TEST_REPORT"

## Usage
print_usage() {
  cat <<EOF

$SCRIPT [-k]
  -k : do not clean up in failure for manual diagnosis

EOF
}

## info message($1)
info() {
  timestamp
  printf "[$TESTREPORT]\t$1\n"
}

error() {
  timestamp
  printf "[$TESTREPORT]\tFAILED $1\n"
}

## Check the volume ($1) status ($2). Return 0 if status matched, 1 otherwise
check_volume_status() {
  local line=
  local stat=`$TIMEOUT 10 $TOOLSET-describe-volumes |
  while read line; do
    if [[ $line =~ VOLUME[[:blank:]]+$1.* ]]; then
      echo $line | awk '{print $(NF-1)}'
    fi
  done`
  if [[ "$stat" == "$2" ]]; then
    return 0
  fi
  return 1
}

## Check the snapshot ($1) status ($2). Return 0 if status matched, 1 otherwise
check_snapshot_status() {
  local line=
  local stat=`$TIMEOUT 10 $TOOLSET-describe-snapshots |
  while read line; do
    if [[ $line =~ SNAPSHOT[[:blank:]]+$1.* ]]; then
      echo $line | awk '{print $4}'
    fi
  done`
  if [[ "$stat" == "$2" ]]; then
    return 0
  fi
  return 1
}

## Attach a volume ($1) to an instance ($2)
attach_volume() {
  local vol=$1
  local inst=$2
  local dev=$3
  ## Attach volume to instance
  local out=`$TIMEOUT 30 $TOOLSET-attach-volume $vol -i $inst -d $dev`
  if (( $? != 0 )); then
    return 1
  fi
  ## Make sure the volume is attached
  local ret=
  for (( try=0; try < TRIES; try++ )); do
    check_volume_status $vol "in-use"
    ret=$?
    if (( ret == 0 )); then
      break
    fi
    sleep $INTERVAL
  done
  return $ret
}

## Detach volume ($1)
detach_volume() {
  local vol=$1
  ## Detach the volume
  $TIMEOUT 30 $TOOLSET-detach-volume $vol
  if (( $? != 0 )); then
    return 1
  fi
  ## Make sure the volume is ready
  local ret=
  for (( try=0; try < TRIES; try++ )); do
    check_volume_status $vol "available"
    ret=$?
    if (( ret == 0 )); then
      break
    fi
    sleep $INTERVAL
  done
  return $ret
}

## Check device status with multiple tries. Exit if fails.
try_dev_stat() {
  for (( i=0; i < 5; i++ )); do
    sleep 6 # Wait for a while before each try
    $TIMEOUT 30 ssh -i $instancekey root@$instanceip stat -f $1
    if (( $? == 0 )); then
      return 0
    fi
  done
  # Something is wrong.  Check to see which disks exist
  $TIMEOUT 30 ssh -i $instancekey root@$instanceip cat /proc/partitions
  return 1
}

## Delete a volume($1). Try detaching it first.
delete_volume() {
  local vol=$1
  if [[ "$vol" != "" ]]; then
    check_volume_status $vol "in-use"
    if (( $? == 0 )); then
      detach_volume $vol
      if (( $? != 0 )); then
        error "to detach volume $vol"
      fi
    fi
    $TIMEOUT 10 $TOOLSET-delete-volume $vol
    if (( $? != 0 )); then
      error "to delete volume $vol"
    fi
  fi
}

## Delete a snapshot($1)
delete_snapshot() {
  local ss=$1
  if [[ "$ss" != "" ]]; then
    $TIMEOUT 10 $TOOLSET-delete-snapshot $ss
    if (( $? != 0 )); then
      error "to delete snapshot $ss"
    fi
  fi
}

## Cleanup all the snapshots and volumes
cleanup() {
  if (( mounted == 1 )); then
    $TIMEOUT 30 ssh -i $instancekey root@$instanceip umount /mnt
  fi
  delete_volume $volume
  delete_snapshot $snapshot
  delete_volume $volume2
}

## Failure handling: print message($1), clean up and bail.
failure() {
  error "$1"
  if (( keepscene == 0 )); then
    cleanup
  fi
  exit 1
}

zone=
instance=
instanceip=

mounted=0
keepscene=0
device=/dev/sdc

ret=

while getopts ":k" option; do
    case "$option" in
        k) keepscene=1;;
        *) print_usage; exit 1 ;;
    esac
done

## Verify the instance is running
info "Looking for the running test instance ..."
for (( try=0; try < TRIES; try++ )); do
  instanceinfo=`$TIMEOUT 10 $TOOLSET-describe-instances | grep -v erminated | grep -v utting | 
  while read line; do
    if [[ $line =~ INSTANCE[[:blank:]]+$instance.* ]]; then
      echo $line
    fi
  done`
  echo $instanceinfo
  if [[ "$instanceinfo" == "" ]]; then
    sleep $INTERVAL
    continue
  fi
  instanceinfolist=( $instanceinfo )
  instance=${instanceinfolist[1]}
  instanceip=${instanceinfolist[3]}
  instancestat=${instanceinfolist[5]}
  instancekey=${instanceinfolist[6]}
  zone=${instanceinfolist[10]}
  if [[ "$instance" == "" || "$instancestat" != "running" || "$instanceip" == "" || "$instanceip" == "0.0.0.0" ]]; then
    sleep $INTERVAL
    continue
  fi
  break
done
if [[ "$instance" == "" || "$instancestat" != "running" || "$instanceip" == "" || "$instanceip" == "0.0.0.0" || "$instancekey" == "" ]]; then
    failure "Instance $instance is not in running state: $instancestat, ip=$instanceip, instancekey=$instancekey"
fi
instancekey="${instancekey}.priv"

## Create a test volume
info "Creating volume with size=$VOLSIZE GB in $zone ..."
volume=
output=`$TIMEOUT 30 $TOOLSET-create-volume --size $VOLSIZE --zone $zone`
if [[ "$output" =~ ^VOLUME.* ]]; then
  volume=`echo "$output" | awk '{print $2}'`
fi
if [[ "$volume" == "" ]]; then
  failure "to create volume: output=\"$output\""
fi
## Make sure the volume is ready
for (( try=0; try < TRIES; try++ )); do
  check_volume_status $volume "available"
  ret=$?
  if (( ret == 0 )); then
    break
  fi
  sleep $INTERVAL
done
if (( ret != 0 )); then
  failure "to create volume: volume not ready after $TRIES tries"
fi

## Attach volume to instance
info "Attaching volume $volume to instance $instance ..."
attach_volume $volume $instance $device
if (( $? != 0 )); then
  failure "to attach volume $volume to instance $instance ..."
fi
sleep 10
## Make sure the device is ready
try_dev_stat $device
if (( $? != 0 )); then
  failure "device $device has not appeared on instance $instance ..."
fi

mark="This is a mark."

## Mount the volume and leave a mark
info "Creating file system on attached volume $volume ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip mkfs.ext2 -q -F $device
if (( $? != 0 )); then
  failure "to create file system on attached volume"
fi
info "Mounting the attached volume $volume ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip mount $device /mnt
if (( $? != 0 )); then
  failure "to mount attached volume"
fi
mounted=1
info "Leaving a mark on the volume $volume ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip "echo $mark > /mnt/mark"
if (( $? != 0 )); then
  failure "to mount attached volume $volume"
fi
markcopy=`$TIMEOUT 30 ssh -i $instancekey root@$instanceip cat /mnt/mark`
if [[ "$markcopy" != "$mark" ]]; then
  failure "with error in marking volume $volume: mark is different (\"$mark\" vs \"$markcopy\")"
fi
info "Unmounting the volume $volume ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip umount /mnt
mounted=0
if (( $? != 0 )); then
  failure "to umount attached volume $volume"
fi
info "Detaching the volume $volume ..."
detach_volume $volume
if (( $? != 0 )); then
  failure "to detach the volume $volume"
fi

## Create a snapshot of the volume
info "Creating snapshot of volume $volume ..."
snapshot=
output=`$TIMEOUT 30 $TOOLSET-create-snapshot $volume`
if [[ "$output" =~ ^SNAPSHOT.* ]]; then
  snapshot=`echo "$output" | awk '{print $2}'`
fi
if [[ "$snapshot" == "" ]]; then
  failure "to create snapshot: output=\"$output\""
fi
## Make sure the snapshot is completed 
for (( try=0; try < TRIES; try++ )); do
  check_snapshot_status $snapshot "completed"
  ret=$?
  if (( ret == 0 )); then
    break
  fi
  sleep $INTERVAL
done
if (( ret != 0 )); then
  failure "to create snapshot: not completed after $TRIES tries"
fi

## Create a volume of the snapshot
info "Creating volume with snapshot $snapshot in $zone ..."
volume2=
output=`$TIMEOUT 30 $TOOLSET-create-volume --snapshot $snapshot --zone $zone`
if [[ "$output" =~ ^VOLUME.* ]]; then
  volume2=`echo "$output" | awk '{print $2}'`
fi
if [[ "$volume2" == "" ]]; then
  failure "to create volume: output=\"$output\""
fi
## Make sure the new volume is ready
for (( try=0; try < TRIES; try++ )); do
  check_volume_status $volume2 "available"
  ret=$?
  if (( ret == 0 )); then
    break
  fi
  sleep $INTERVAL
done
if (( ret != 0 )); then
  failure "to create volume: volume not ready after $TRIES tries"
fi

## Attach the new volume to the instance
info "Attaching volume $volume2 to instance $instance ..."
attach_volume $volume2 $instance
if (( $? != 0 )); then
  failure "to attach volume $volume2 to instance $instance ..."
fi
sleep 10
## Make sure the device is ready
try_dev_stat $device

## Mount the snapshot and check the mark
info "Mounting the attached volume $volume2 ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip mount $device /mnt
if (( $? != 0 )); then
  failure "to mount attached volume $volume2"
fi
mounted=1
info "Checking the mark on volume $volume2 ..."
markcopy=`$TIMEOUT 30 ssh -i $instancekey root@$instanceip cat /mnt/mark`
if [[ "$markcopy" != "$mark" ]]; then
  failure "with error in snapshot volume $volume2: mark is different (\"$mark\" vs \"$markcopy\")"
fi
info "Unmounting the volume $volume2 ..."
$TIMEOUT 30 ssh -i $instancekey root@$instanceip umount /mnt
mounted=0
if (( $? != 0 )); then
  failure "to umount attached volume"
fi
info "Detaching volume $volume2 ..."
detach_volume $volume2
if (( $? != 0 )); then
  failure "to detach the volume $volume2"
fi

## Clean up
info "Cleaning volumes and snapshots ..."
cleanup

info "Done."
