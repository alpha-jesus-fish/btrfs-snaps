#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 99
fi

#+++++++++++++++++++++++++++++++++ GLOBALS +++++++++++++++++++++++++++++++++
reboot=3
monthly=2
weekly=4
daily=6
hourly=10
#+++++++++++++++++++++++++++++++ END-GLOBALS +++++++++++++++++++++++++++++++

#gather options
#+++++++++++++++++++++++++++++++++ OPTIONS +++++++++++++++++++++++++++++++++
while :
do
   if [ $# -eq 0 ]; then
      break
   fi
   case "$1" in
#     directory where to look for snapshot directory and subvolumes
      -d | --dir)
         dir="$2"
         shift 2
         ;;
#     minimum time buffer before a new backup is created
      -b | --buffer)
         create_buffer=$2
         shift 2
         ;;
#     force the creation of a new snapshot
      -c)
         create="override"
         shift
         ;;
#     prevent creation of a new snapshot
      --no-create)
         create="no"
         shift
         ;;
#     how many copies to keep
      -k)
         keep=$2
         shift 2
         ;;
      -s | --sub)
         subvol="$2"
         shift 2
         ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Error: Unknown option: $1" >&2
        exit 1
        ;;
#     type of backups to process
      *) #no more options
        type="$1"
        break
        ;;
   esac
done
#+++++++++++++++++++++++++++++++ END-OPTIONS +++++++++++++++++++++++++++++++

#+++++++++++++++++++++++++++++ VAR ASSIGNMENTS +++++++++++++++++++++++++++++
#type
#keep
#create
#dir

#type of snapshot
if [ -z $type ]
then
   echo No type specified
   exit 98
fi
#how many copies to keep
if [ -z $keep ]; then keep=${!type};fi
#whether to create a new backup
if [ -z $create ]; then create=yes;fi

#if no directory is specified, exit
if [ -z $dir ]
then
   echo No directory specified
   exit 99
fi

#finds the name of the subvolumes in the directory
if [ $subvol ]; then
   for sub in $subvol
   do
      if [ -z "$(btrfs subvolume list $dir | grep $sub | grep -v snapshots)" ]; then
         echo Couldn\'t find specified subvolume in given directory
         exit 102
      fi
   done
else
   subvol=$(btrfs subvolume list $dir | awk '{print $9}' | grep -v snapshots)
   if [ -z $subvol ]; then
      echo Couldn\' find a subvolume in given directory
      exit 101
   fi
fi

x=$subvol
subvol=""
for sub in $x
do
   if [ $sub == $(dir $dir | grep -o $sub) ]; then
      subvol="$subvol $sub"
   fi
done

for sub in $subvol
do
   dates=$(ls -l $dir/snapshots | grep $sub-$type)

#+++++++++++++++++++++++++++ END VAR ASSIGNMENTS +++++++++++++++++++++++++++

#++++++++++++++++++++++++++++++ TYPE SPECIFIC ++++++++++++++++++++++++++++++
#///////////////////////////////// REBOOT /////////////////////////////////
   if [ $type == 'reboot' ]; then
      echo 'reboot'
      new_date=$(date +"%Y-%m-%d_%H:%M:%S")
      count=$(ls -l $dir/snapshots | grep reboot | wc -l)
      (( keep -= 1 ))
      echo removing reboot snaps
      for i in $(dir $dir/snapshots | egrep -o "$sub-reboot-[0-9]{4}-[0-9]{2}-[0-9]{2}_([0-9]{2}:){2}[0-9]{2}");
      do
         if (( $count <= $keep )); then break;fi
         echo $i
         btrfs subvolume delete $dir/snapshots/$i
         (( count -= 1 ))
      done
#/////////////////////////////// END REBOOT ///////////////////////////////

   else
      case $type in
#///////////////////////////////// REBOOT /////////////////////////////////
         'monthly')
            new_date=$(date +"%Y-%m-%d")
            if [ -z $create_buffer ]; then create_buffer="1 week";fi
            echo $dates
            dates=$(echo $dates | grep -o 201[0-9]-[01][0-9]-[0-3][0-9])
            echo $dates

            date=$(date -d "$keep months ago" +"%Y-%m-%d")
            echo compared date: $date
            ;;
#/////////////////////////////// END REBOOT ///////////////////////////////
#///////////////////////////////// WEEKLY /////////////////////////////////
         'weekly')
            new_date=$(date +"%Y-%m-%d_%H")
            if [ -z $create_buffer ]; then create_buffer="3 days";fi
            dates=$(echo $dates | grep -o 201[0-9]-[01][0-9]-[0-3][0-9]_[0-9][0-9])
            echo $dates
            dates2=""
            for i in $dates;do
               dates2="$dates2 $i:00"
            done
            dates=$dates2
            echo $dates

            date=$(date -d "$keep weeks ago" +"%Y-%m-%d")
            echo compared date: $date
            ;;
#///////////////////////////////// DAILY /////////////////////////////////
         'daily')
            new_date=$(date +"%Y-%m-%d_%H")
            if [ -z $create_buffer ]; then create_buffer="6 hours";fi
            dates=$(echo $dates | grep -o 201[0-9]-[01][0-9]-[0-3][0-9]_[0-9][0-9])
            echo $dates
            dates2=""
            for i in $dates;do
               dates2="$dates2 $i:00"
            done
            dates=$dates2
            echo $dates

            date=$(date -d "$keep days ago" +"%Y-%m-%d")
            echo compared date: $date
            ;;
#//////////////////////////////// END DAILY ///////////////////////////////
#///////////////////////////////// HOURLY /////////////////////////////////
         'hourly')
            new_date=$(date +"%Y-%m-%d_%H:%M")
            if [ -z $create_buffer ]; then create_buffer="45 minutes";fi
            dates=$(echo $dates | grep -o 201[0-9]-[01][0-9]-[0-3][0-9]_[0-2][0-9])

            date=$(date -d "$keep hours ago" +"%Y-%m-%d %H:00")
            echo compared date: $date
            ;;
         *)
            echo type \'$type\' not recognized
            exit 100
            ;;
#/////////////////////////////// END HOURLY ///////////////////////////////
      esac

#     generate date for comparison
      date=$(date -d "$date" +"%s")
#     generate date for new snapshot creation buffer check
      create_date=$(date -d "$create_buffer ago" +"%s")

#////////////////////////////// DATE REMOVAL //////////////////////////////
      echo
      for i in $dates
      do
         ii=$(echo $i | sed 's/_/ /')
         ii=$(date -d "$ii" +"%s")
         if (( $ii < $date ))
         then
            echo $i
            btrfs subvolume delete $dir/snapshots/$sub-$type-${i:0:13}*
         fi

         if [ "$create_date" -le "$ii" -a $create != "override" ]
         then
            echo create=="no"
            create="no"
         fi
      done
   fi
#//////////////////////////// END DATE REMOVAL ////////////////////////////
#++++++++++++++++++++++++++++ END TYPE SPECIFIC ++++++++++++++++++++++++++++

#+++++++++++++++++++++++++++++ CREATE SNAPSHOT +++++++++++++++++++++++++++++
#  create new snapshot
   if [ $create == "yes" -o $create == "override" ]; then
      echo creating new snapshot $type-$new_date
      #touch $dir/snapshots/$sub-$type-$new_date
      name="$sub-$type-$new_date"
      if [ -z "$(dir $dir/snapshots | grep $name)" ]; then
         btrfs subvolume snapshot $dir/$sub $dir/snapshots/$name
      fi
   fi
#+++++++++++++++++++++++++++ END CREATE SNAPSHOT +++++++++++++++++++++++++++
done
