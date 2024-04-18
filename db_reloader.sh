#!/bin/bash

#Services are set up as environment vars in whatever runtime you choose
SERVICE=$SERVICE_NAME_SLUG

SOURCE_HOST=$SERVICE\_DB_SOURCE
TARGET_HOST=$SERVICE\_DB_TARGET
DB_NAME=$SERVICE\_DB
USER=$SERVICE\_DB_USER
PASS=$SERVICE\_DB_PASS
SCHEMA_FILE="./tmp/schema_dump.sql"
DATA_FILE="./tmp/data_dump.sql"

MESSAGE="Beginning reload of svod-be staging db"
echo "${MESSAGE}"
python3 sns_message.py "start" "${MESSAGE}"

mysqldump -u ${!USER} -h ${!SOURCE_HOST} -p${!PASS} ${!DB_NAME} \
  --no-tablespaces \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --add-drop-database \
  --no-data > ${SCHEMA_FILE}

schemaDumpRetVal=$?
if [ $schemaDumpRetVal -ne 0 ]; then
  MESSAGE="Something when wrong with the schema mysql dump, please look at the logs at <wherever your logs are>"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit $schemaDumpRetVal
fi

echo "Dumping copy of ${!SOURCE_HOST} data to ${DATA_FILE}"

mysqldump -u ${!USER} -h ${!SOURCE_HOST} -p${!PASS} ${!DB_NAME} \
  --no-tablespaces \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --no-create-info \
  --insert-ignore \
  --ignore-table=${!DB_NAME}.versions \
  --ignore-table=${!DB_NAME}.users \
  --ignore-table=${!DB_NAME}.webhook_events > ${DATA_FILE}

dataDumpRetVal=$?
if [ $dataDumpRetVal -ne 0 ]; then
  MESSAGE="Something when wrong with the mysql dump, please look at the logs at <wherever your logs are>"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit $dataDumpRetVal
fi

#make sure we are not dropping databases in prod
if [[ ${!TARGET_HOST} =~ "prod" ]]; then
  MESSAGE="The target host contains 'prod' in the hostname, please review environment variables in db-reloader task definition  to ensure the target host is the svod staging db ${TASK_DEF_URL}"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit 1
fi

echo "Reloading schema for ${!TARGET_HOST} from ${SCHEMA_FILE}"

mysql -u ${!USER} -h ${!TARGET_HOST} -p${!PASS}  ${!DB_NAME} < ${SCHEMA_FILE}

schemaLoadRetVal=$?
if [ $schemaLoadRetVal -ne 0 ]; then
  MESSAGE="Something when wrong with the new db reload, please look at the logs at <wherever your logs are>"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit $schemaLoadRetVal
fi

echo "Reloading data for ${!TARGET_HOST} from ${DATA_FILE}"

mysql -u ${!USER} -h ${!TARGET_HOST} -p${!PASS}  ${!DB_NAME} < ${DATA_FILE}

dataLoadRetVal=$?
if [ $dataLoadRetVal -ne 0 ]; then
  MESSAGE="Something when wrong with the new db reload, please look at the logs at <wherever your logs are>"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit $dataLoadRetVal
fi

#dump the staging users data into the fresh database

echo "Reloading staging users data for ${!TARGET_HOST} from ${USERS_FILE}"

mysql -f -u ${!USER} -h ${!TARGET_HOST} -p${!PASS}  ${!DB_NAME} < ${USERS_FILE}

usersLoadRetVal=$?
if [ $usersLoadRetVal -ne 0 ]; then
  MESSAGE="Something when wrong with the new db reload, please look at the logs at <wherever your logs are>"
  echo "${MESSAGE}"
  python3 sns_message.py "fail" "${MESSAGE}"
  exit $usersLoadRetVal
fi

MESSAGE="Successfully reloaded ${SERVICE} staging DB from Prod with exit codes: schema load: ${schemaLoadRetVal}, data load: ${dataLoadRetVal}, staging user load: ${usersLoadRetVal}"
echo "${MESSAGE}"
python3 sns_message.py "success" "${MESSAGE}"
exit 0
