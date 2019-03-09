#!/usr/bin/env bash

docker-compose down
if [[ $1 = "--clean-db" ]]
then
rm -rf ./masters/master1/data/*
rm -rf ./masters/master2/data/*
fi

docker-compose up -d

link_db='mysql -u root -proot -e'
for container in master1 master2 ; do
until docker exec $container sh -c "$link_db ';'"
do
    echo "Waiting for $container database connection..."
    sleep 4
done

priv_stmt='STOP SLAVE; DROP USER IF EXISTS "replmy"@"%"; GRANT replication slave ON *.* TO "replmy"@"%" IDENTIFIED BY "password"; FLUSH PRIVILEGES;'
docker exec $container sh -c "$link_db '$priv_stmt'"

done

docker-ip() {
    docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}

declare -A array_cmd
for container in master1 master2 ; do

MS_STATUS=`docker exec $container sh -c "$link_db 'SHOW MASTER STATUS'"`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $5}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $6}'`

start_slave_stmt="CHANGE MASTER TO MASTER_HOST='$(docker-ip $container)',MASTER_USER='replmy',MASTER_PASSWORD='password',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd=$link_db
start_slave_cmd+=' "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
array_cmd[$container]=$start_slave_cmd
done

docker exec master1 sh -c "${array_cmd[master2]}"
docker exec master1 sh -c "mysql -u root -proot -e 'SHOW SLAVE STATUS \G'"
docker exec master2 sh -c "${array_cmd[master1]}"
docker exec master2 sh -c "mysql -u root -proot -e 'SHOW SLAVE STATUS \G'"

