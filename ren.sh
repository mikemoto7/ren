#!/bin/bash

# set -x

scriptName=`basename $0`
scriptDir=`dirname $0`
if [ "$(echo $scriptDir | cut -c1)" != '/' ]; then
   scriptDir=`pwd`/$scriptDir  # Make an absolute path.
fi

# previewMode=no
# if [ "$1" == '-p' ]; then
#    previewMode=yes
#    shift
# fi

if [ -z "$1" ]; then
   echo "Use your text editor \$EDITOR to rename multiple files/directories at the same time."
   echo "Runstring:  $scriptName file1 [file2 ...]"
   # echo "Runstring:  $scriptName [-p] file1 [file2 ...]"
   # echo "-p = preview mode"
   exit 1
fi

if [ -z "$EDITOR" ]; then
   echo "ERROR: You must set your EDITOR variable before calling this script."
   exit 1
fi

# filesToRename=$@

# while true; do
#    echo $1
#    shift
#    if [ -z "$1" ]; then
#       exit 1
#    fi
# done
# 
# exit

tempfile=${scriptName}_temp
rm -fr $tempfile

logfile=$scriptDir/${scriptName}.log

redo_script=${scriptName}_redo.sh
rm -f $redo_script

# if [ -z "$1" ]; then
#    \ls | while read entry; do
#       echo "$entry    Original: $entry" >> $tempfile
#    done
#    # Initial position of cursor
#    filesToRenameHalfSize=1
# else
#   for file in $filesToRename; do
#   for file in $@; do
echo "# Do not add or delete lines." >> $tempfile
while true; do
   file="$1"
   echo "Preparing filename: $file"
   # Trim trailing forward slash if any.
   file=`echo "$file" | sed 's%/$%%'`
   if [ ! -f "$file" -a ! -d "$file" ]; then
      echo "File/directory $file does not exist."
      rm -f $tempfile
      exit 1
   fi
   # Put double quotes around original filename to see any trailing whitespace.
   # echo "$file | Original: \"$file\"" >> $tempfile
   echo "$file" >> $tempfile
   # Initial position of cursor
   filesToRenameHalfSize=`expr ${#file} / 2` 
   shift
   if [ -z "$1" ]; then
      break
   fi
done
   # done
# fi
# tempfile3=${scriptName}_temp3
# column -t $tempfile -s \| > $tempfile3
# cp $tempfile3 $tempfile

tempfile2=${scriptName}_temp2
cp $tempfile $tempfile2
rc=0
stopflag='no'
while [ $stopflag == 'no' ]; do
   # $EDITOR +${filesToRenameHalfSize}go $tempfile
   # $EDITOR $tempfile
   $EDITOR +2 $tempfile
   cmp $tempfile $tempfile2
   if [ $? -eq 0 ]; then
         echo "No changes performed.  Aborting."
         break
   fi
   orig_size=$(wc -l $tempfile2 | cut -f1 -d' ')
   edited_size=$(wc -l $tempfile | cut -f1 -d' ')
   if [ $edited_size -gt $orig_size ]; then
      while true; do
         echo -n "ERROR: An extra line was added which will confuse our filename mapping.  Please remove the extra line. (e=edit, a=abort)  "
         read answer
         if [ "$answer" == 'a' ]; then
            stopflag=yes
            break
         fi
      done
      continue
   fi
   if [ $edited_size -lt $orig_size ]; then
      while true; do
         echo -n "ERROR: A line was deleted which will confuse our filename mapping.  Please add back the line.  (e=edit, a=abort)  "
         read answer
         if [ "$answer" == 'a' ]; then
            stopflag=yes
            break
         fi
      done
      continue
   fi

   orig_filenames=()
   readarray -t orig_filenames < $tempfile2

   tempfile4=${scriptName}_temp4
   rm -f $tempfile4
   echo "rc=0" >> $tempfile4
   echo "return_rc=0" >> $tempfile4
   index=0
   while read newFileName; do
        if [ $index -eq 0 ]; then
           skip=   # Always skip first line
        elif [ "$(echo $newFileName | cut -c1)" == '#' ]; then
         # echo "$entry" >> $tempfile4
           # continue
           skip=
        # fi
      # origFileName=`echo "$entry" | sed 's/^.*  *Original:  *\"\(.*\)\"$/\1/'`
      # if [ "$origFileName" == "$entry" ]; then
        #       echo "ERROR: sed pattern returned whole entry instead of just origFileName."
        #       continue
        # fi
      # newFileName=`echo "$entry" | sed 's/^\(.*\)\([^ ]\)  *Original:.*$/\1\2/'`
      elif [ "$newFileName" == "${orig_filenames[$index]}" ]; then
         echo "# No_change: ${orig_filenames[$index]}" >> $tempfile4
      else
         cat >> $tempfile4 <<EOH
if [ \( ! -f ${orig_filenames[$index]} -a -f "$newFileName" \) -o \( ! -d ${orig_filenames[$index]} -a -d "$newFileName" \) ]; then
   echo "# ${orig_filenames[$index]} has already been renamed to $newFileName."

elif [ \( -f ${orig_filenames[$index]} -a -f "$newFileName" \) -o \( -d ${orig_filenames[$index]} -a -d "$newFileName" \) ]; then
   echo "# Cannot rename ${orig_filenames[$index]}.  $newFileName already exists.  Cannot overwrite existing files/dirs."
   return_rc=1

elif [ \( ! -f ${orig_filenames[$index]} -a ! -f "$newFileName" \) -a \( ! -d ${orig_filenames[$index]} -a ! -d "$newFileName" \) ]; then
   echo "# File with old filename ${orig_filenames[$index]} does not exist."
   return_rc=1

else
   echo "Renaming ${orig_filenames[$index]} to $newFileName"
   mv ${orig_filenames[$index]} $newFileName
   rc=\$?
   if [ \$rc -ne 0 ]; then
      return_rc=\$rc
   fi
fi
EOH
        fi
        index=$(expr $index + 1)
   done < $tempfile
   echo "exit \$return_rc" >> $tempfile4
   
   echo
   echo "To be performed:"
   grep mv $tempfile4
   echo
   while true; do
      echo -n "Continue? (y/n/e=reedit) "
      read answer
      if [ "$answer" == 'e' ]; then
         break
      fi
      if [ "$answer" == 'n' ]; then
         stopflag=yes
         break
      fi
      if [ "$answer" == 'y' ]; then
         # sh -x $tempfile4
         $tempfile4
         rc=$?
         stopflag=yes
         break
      fi
   done
done

rm -f $tempfile
rm -f $tempfile2

if [ -n "$tempfile4" -a -f "$tempfile4" ]; then
   date >> $logfile
   grep mv $tempfile4 >> $logfile

   if [ $rc -eq 0 ]; then
      rm -f $tempfile4
   else
      mv $tempfile4 $redo_script
      chmod +x $redo_script
      echo "ERROR: Problem occurred during the renaming.  Fix the problem and then run  $redo_script  to redo the renaming.  Files and directories that were successfully renamed the first time will not be redone."
   fi
fi




