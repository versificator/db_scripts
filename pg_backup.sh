#!/bin/bash
 
###########################
####### LOAD CONFIG #######
###########################
 
while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        if [ -r "$2" ]; then
                                source "$2"
                                shift 2
                        else
                                ${ECHO} "Unreadable config file \"$2\"" 1>&2
                                exit 1
                        fi
                        ;;
                *)
                        ${ECHO} "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done
 
if [ $# = 0 ]; then
        SCRIPTPATH=$(cd ${0%/*} && pwd -P)
        source $SCRIPTPATH/pg_backup.config
fi;
 
###########################
#### PRE-BACKUP CHECKS ####
###########################
 
# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ]; then
	echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
	exit 1;
fi;
 
 
###########################
### INITIALISE DEFAULTS ###
###########################
 
if [ ! $HOSTNAME ]; then
	HOSTNAME="localhost"
fi;
 
if [ ! $USERNAME ]; then
	USERNAME="postgres"
fi;
 
 
###########################
#### START THE BACKUPS ####
###########################

function perform_backups()
{
        SUFFIX=$1
        FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"

        echo "Making backup directory in $FINAL_BACKUP_DIR"
 
        if ! mkdir -p $FINAL_BACKUP_DIR; then
	        echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
	        exit 1;
        fi;
 
 
        #######################
        ### GLOBALS BACKUPS ###
        #######################
 
        echo -e "\n\nPerforming globals backup"
        echo -e "--------------------------------------------\n"
 
        if [ "$ENABLE_GLOBALS_BACKUPS" = "yes" ]
        then
                echo "Globals backup"
 
                if ! pg_dumpall -g -w -h "$HOSTNAME" -U "$USERNAME" | gzip > $FINAL_BACKUP_DIR"globals".sql.gz.in_progress; then
                        echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
                else
                        mv $FINAL_BACKUP_DIR"globals".sql.gz.in_progress $FINAL_BACKUP_DIR"globals".sql.gz
                fi
        else
	        echo "None"
        fi
 
        ###########################
        ### TABLE-ONLY BACKUPS  ###
        ###########################


        echo -e "\n\nPerforming specified tables backup"
        echo -e "--------------------------------------------\n"

        IFS='|' read -ra TABLE <<<"${TABLE_ONLY_LIST}"
        #TBD check if tables exist
        for i in "${TABLE[@]}"; do
                echo "No checks if table ""${i}"" exists"
        done

        if [ "yes" = "yes" ]
        then

                if [ "$ENABLE_PLAIN_BACKUPS" = "yes" ]
                then
                        echo "Plain backup of $DATABASE . Include the following tables:  $TABLE_ONLY_LIST"

                        if ! pg_dump -Fp -w -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress; then
                               echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
                        else
                               mv $FINAL_BACKUP_DIR"$DATABASE".sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE".sql.gz
                        fi
                fi

                if [ $ENABLE_CUSTOM_BACKUPS = "yes" ]
                then
                        echo "Custom backup of $DATABASE . Include the following tables: $TABLE_ONLY_LIST"

                        if ! pg_dump -Fc -w -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" -f $FINAL_BACKUP_DIR"$DATABASE".custom.in_progress; then
                               echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE" 1>&2
                        else
                               mv $FINAL_BACKUP_DIR"$DATABASE".custom.in_progress $FINAL_BACKUP_DIR"$DATABASE".custom
                        fi
                fi

        else
                echo "None"
        fi



        echo -e "\nAll database backups complete!"
}


# MONTHLY BACKUPS

DAY_OF_MONTH=`date +%d`

if [ $DAY_OF_MONTH -eq 1 ];
then
        # Delete all expired monthly directories
        find $BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'

        perform_backups "-monthly"

        exit 0;
fi



# WEEKLY BACKUPS

if [ ! -z $WEEKS_TO_KEEP ]; then

        DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
        EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`

        if [ "$DAY_OF_WEEK" = "$DAY_OF_WEEK_TO_KEEP" ];
        then
                # Delete all expired weekly directories
                find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'

                perform_backups "-weekly"

                exit 0;
        fi
fi;

# DAILY BACKUPS

# Delete daily backups 7 days old or more
find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'

perform_backups "-daily"

