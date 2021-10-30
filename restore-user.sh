#!/bin/bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

# This script will restore the given user from incremental backup.
USAGE="restore-user.sh 2018-03-25 user"

# Assign arguments
TIME=$1
USER=$2

# Set script start time
START_TIME=`date +%s`

# Temp dir setup
TEMP_DIR=$CURRENT_DIR/tmp
mkdir -p $TEMP_DIR

# Set user repository
USER_REPO=$REPO_USERS_DIR/$USER

##### Validations #####

if [[ -z $1 || -z $2 ]]; then
  echo "!!!!! This script needs 2 arguments. Backup date and user name"
  echo "---"
  echo "Usage example:"
  echo $USAGE
  exit 1
fi



# Check if backup archive date exist in user repo
if ! borg list $USER_REPO | grep -q $TIME; then
  echo "!!!!! Backup archive $TIME not found, the following are available:"
  borg list $USER_REPO
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

# Check if hestia repo exist
if [ ! -d "$REPO_HESTIA/data" ]; then
  echo "!!!!! Hestia has no backup repository or no backup has been executed yet. Aborting..."
  exit 1
fi

# Check if backup archive date exist in hestia repo
if ! borg list $REPO_HESTIA | grep -q $TIME; then
  echo "!!!!! Backup archive $TIME not found in Hestia repo, the following are available:"
  borg list $REPO_HESTIA
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

echo "########## BACKUP ARCHIVE $TIME FOR USER $USER FOUND, PROCEEDING WITH RESTORE ##########"

read -p "Are you sure you want to restore user $USER with $TIME backup version? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  [[ "$0" = "$BASH_SOURCE" ]]
  echo
  echo "########## PROCESS CANCELED ##########"
  exit 1
fi

# Set dir paths
USER_DIR=$HOME_DIR/$USER
HESTIA_USER_DIR=$HESTIA_DIR/data/users/$USER
BACKUP_USER_DIR="${USER_DIR:1}"
BACKUP_HESTIA_USER_DIR="${HESTIA_USER_DIR:1}"

cd $TEMP_DIR

echo "----- Restoring Hestia user files from backup $REPO_HESTIA::$TIME to temp dir"
borg extract --list $REPO_HESTIA::$TIME $BACKUP_HESTIA_USER_DIR

# Check that the files have been restored correctly
if [ ! -d "$BACKUP_HESTIA_USER_DIR" ]; then
  echo "!!!!! Hestia user config files for $USER are not present in backup archive $TIME. Aborting..."
  exit 1
fi
if [ -z "$(ls -A $BACKUP_HESTIA_USER_DIR)" ]; then
  echo "!!!!! Hestia user config files restored directory for $USER is empty, Aborting..."
  exit 1
fi

echo "-- Restoring hestia config files for user $USER from temp dir to $HESTIA_USER_DIR"
mkdir -p $HESTIA_USER_DIR
rsync -za --delete $BACKUP_HESTIA_USER_DIR/ $HESTIA_USER_DIR/

echo "-- Hestia rebuild user"
v-rebuild-user $USER

echo "----- Restoring user files from backup $USER_REPO::$TIME to temp dir"
borg extract --list $USER_REPO::$TIME $BACKUP_USER_DIR

# Check that the files have been restored correctly
if [ ! -d "$BACKUP_USER_DIR" ]; then
  echo "!!!!! User $USER files are not present in backup archive $TIME. Aborting..."
  exit 1
fi
if [ -z "$(ls -A $BACKUP_USER_DIR)" ]; then
  echo "!!!!! User $USER restored directory is empty, Aborting..."
  exit 1
fi

echo "-- Restoring user files from temp dir to $USER_DIR"
rsync -za --delete --omit-dir-times $BACKUP_USER_DIR/ $USER_DIR/

echo "-- Fixing web permissions"
chown -R $USER:$USER $USER_DIR/web

echo "----- Crontabs restore"
crontab -u /home/$USER/conf/crontabs.data

echo "----- Checking if there are databases to restore"
v-list-databases $USER | cut -d " " -f1 | awk '{if(NR>2)print}' | while read DB ; do
  # Check if there is a backup for the db
  DB_DIR=$HOME_DIR/$USER/$DB_DUMP_DIR_NAME
  DB_FILE=$DB_DIR/$DB.sql.gz
  if test -f "$DB_FILE"
    then
    echo "-- $DB found in backup"
    $CURRENT_DIR/inc/db-restore.sh $DB $DB_FILE
  else
    echo "$DB_FILE not found in $DB_DIR"
  fi
done

echo "-- Hestia rebuild user"
v-rebuild-user $USER

echo "----- Cleaning temp dir"
if [ -d "$TEMP_DIR" ]; then
  rm -rf $TEMP_DIR/*
fi

echo
echo "$(date +'%F %T') #################### USER $USER RESTORE COMPLETED ####################"

END_TIME=`date +%s`
RUN_TIME=$((END_TIME-START_TIME))

echo "-- Execution time: $(date -u -d @${RUN_TIME} +'%T')"
echo
