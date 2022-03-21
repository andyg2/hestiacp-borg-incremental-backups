#!/bin/bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

# This script dump all databases to the corresponding user dir.

DB_COUNT=0

echo "$(date +'%F %T') #################### DUMP MYSQL DATABASES TO CORRESPONDING USER DIR ####################"
# Get user list
while read USER ; do
  # Create dir where the user databases will be stored
  DESTINATION=$HOME_DIR/$USER/$DB_DUMP_DIR_NAME
  # Clean destination
  rm -rf $DESTINATION
  mkdir -p $DESTINATION
  
  # Get databases
  while read DATABASE ; do
    if [ ! -z "$DATABASE" ] ; then
      if [ -e "/usr/local/bin/mydumper" ] || [ -e "/usr/bin/mydumper" ]; 
        then
          mkdir -p $DESTINATION/$DATABASE
          mydumper -v 1 --triggers --events --routines  --rows=1000 --threads=1 --compress --database=$DATABASE --outputdir=$DESTINATION/$DATABASE
        else
          # Clean destination
          mysqldump $DATABASE --opt --routines | gzip > $DESTINATION/$DATABASE.sql.gz
          echo "$(date +'%F %T') -- $DATABASE > $DESTINATION/$DATABASE.sql.gz"
      fi
      # Fix permissions
      chown -R $USER:$USER $DESTINATION
      let DB_COUNT++
    fi
  done < <(v-list-databases $USER | cut -d " " -f1 | awk '{if(NR>2)print}')
done < <(v-list-users | cut -d " " -f1 | awk '{if(NR>2)print}')

echo "$(date +'%F %T') ########## $DB_COUNT DATABASES SAVED ##########"
echo
