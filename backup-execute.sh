#!/bin/bash -l
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

### Variables ###

# Set script start time
START_TIME=`date +%s`

# Exclude is a temp file that stores dirs that we dont want to backup
EXCLUDE=$CURRENT_DIR/exclude

# Set backup archive name to current day
ARCHIVE=$(date +'%F--%H-%M')

### Start processing ###

# Dump databases to corresponding user dirs
$CURRENT_DIR/dump-databases.sh

echo
echo "$(date +'%F %T') #################### USER PROCESSING ####################"
echo

# Prepare excluded users array
IFS=', ' read -r -a EXCLUDED_USERS <<< "$EXCLUDED_USERS"

COUNT=0

for USER_DIR in $HOME_DIR/* ; do
  if [ -d "$USER_DIR" ] && [ "$BACKUP_DIR" != "$USER_DIR" ]; then
    USER=$(basename $USER_DIR)

    echo "$(date +'%F %T') ########## Processing user $USER ##########"
    echo

    # Check if the user is in the excluded users list and skip if true
    for EXCLUDED_USER in "${EXCLUDED_USERS[@]}"
    do
      if [ "$USER" == "$EXCLUDED_USER" ]; then
        echo "!! User $USER is in the excluded users list, the backup will not run"
        echo
        continue 2
      fi
    done

    # Clean exclusion list
    if [ -f "$EXCLUDE" ]; then
      rm $EXCLUDE
    fi

    # Build exclusion list
    # No need for drush backups, tmp folder and .cache dir
    echo "$USER_DIR/drush-backups" >> $EXCLUDE
    echo "$USER_DIR/backups" >> $EXCLUDE
    echo "$USER_DIR/tmp" >> $EXCLUDE
    echo "$USER_DIR/.cache" >> $EXCLUDE

    # Exclude drupal and wordpress cache dirs
    for WEB_DIR in $USER_DIR/web/* ; do
      if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME" ]; then
        find $WEB_DIR/$PUBLIC_HTML_DIR_NAME -maxdepth 2 -type d -name "cache" | grep "wp-content/cache" >> $EXCLUDE
        if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/cache" ]; then
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/cache" >> $EXCLUDE
        fi
      fi
    done
    
    # Exclude bitrix cache dirs
    for WEB_DIR in $USER_DIR/web/* ; do
      if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME" ]; then
        find $WEB_DIR/$PUBLIC_HTML_DIR_NAME -maxdepth 2 -type d -name "cache" | grep "wp-content/cache" >> $EXCLUDE
        if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/bitrix/cache" ]; then
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/bitrix/cache/*" >> $EXCLUDE
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/bitrix/managed_cache/*" >> $EXCLUDE
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/bitrix/html_pages/*/*" >> $EXCLUDE
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/bitrix/backup/*" >> $EXCLUDE
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/upload/resize_cache/*" >> $EXCLUDE
        fi
      fi
    done
    

    # Set user borg repo path
    USER_REPO=$REPO_USERS_DIR/$USER
    
    # copy crontabs in userdir
    if [ -e "/var/spool/cron/$USER" ]; then
      cp -af /var/spool/cron/$USER /home/$USER/crontabs.data 
    fi

    # Check if repo was initialized, if its not we perform borg init
#     if ! [ -d "$USER_REPO/data" ]; then
#       echo "-- No repo found. Initializing new borg repository $USER_REPO"
#       mkdir -p $USER_REPO
      borg init $OPTIONS_INIT $USER_REPO
#     fi

    echo "-- Creating new backup archive $USER_REPO::$ARCHIVE"
    borg create $OPTIONS_CREATE $USER_REPO::$ARCHIVE $USER_DIR --exclude-from=$EXCLUDE
    echo "-- Cleaning old backup archives"
    borg prune $OPTIONS_PRUNE $USER_REPO

    let COUNT++
    echo
  fi
done

echo "$(date +'%F %T') ########## $COUNT USERS PROCESSED ##########"

# We dont need exclude list anymore
if [ -f "$EXCLUDE" ]; then
  rm $EXCLUDE
fi

echo
echo
echo "$(date +'%F %T') #################### SERVER LEVEL BACKUPS #####################"

echo "$(date +'%F %T') ########## Executing scripts backup: $SCRIPTS_DIR ##########"
# if ! [ -d "$REPO_SCRIPTS/data" ]; then
#   echo "-- No repo found. Initializing new borg repository $REPO_SCRIPTS"
#   mkdir -p $REPO_SCRIPTS
  borg init $OPTIONS_INIT $REPO_SCRIPTS
# fi
echo "-- Creating new backup archive $REPO_SCRIPTS::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_SCRIPTS::$ARCHIVE $SCRIPTS_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_SCRIPTS
echo

echo "$(date +'%F %T') ########## Executing server config backup: $ETC_DIR ##########"
# if ! [ -d "$REPO_ETC/data" ]; then
#   echo "-- No repo found. Initializing new borg repository $REPO_ETC"
#   mkdir -p $REPO_ETC
  borg init $OPTIONS_INIT $REPO_ETC
# fi
echo "-- Creating new backup archive $REPO_ETC::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_ETC::$ARCHIVE $ETC_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_ETC
echo

echo "$(date +'%F %T') ########## Executing Hestia dir backup: $HESTIA_DIR ##########"
# if ! [ -d "$REPO_HESTIA/data" ]; then
#   echo "-- No repo found. Initializing new borg repository $REPO_HESTIA"
#   mkdir -p $REPO_HESTIA
  borg init $OPTIONS_INIT $REPO_HESTIA
# fi
echo "-- Creating new backup archive $REPO_HESTIA::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_HESTIA::$ARCHIVE $HESTIA_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_HESTIA
echo

# if [[ ! -z "$REMOTE_BACKUP_SERVER" && ! -z "$REMOTE_BACKUP_SERVER_DIR" ]]; then
#   echo
#   echo "$(date +'%F %T') #################### SYNC BACKUP DIR $BACKUP_DIR TO REMOTE SERVER: $REMOTE_BACKUP_SERVER:$REMOTE_BACKUP_SERVER_DIR ####################"
#   rsync -za --delete --stats $BACKUP_DIR/ $REMOTE_BACKUP_SERVER_USER@$REMOTE_BACKUP_SERVER:$REMOTE_BACKUP_SERVER_DIR/
# fi

echo
echo "$(date +'%F %T') #################### BACKUP COMPLETED ####################"

END_TIME=`date +%s`
RUN_TIME=$((END_TIME-START_TIME))

echo "-- Execution time: $(date -u -d @${RUN_TIME} +'%T')"
echo
