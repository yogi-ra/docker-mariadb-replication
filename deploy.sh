#!/usr/bin/env bash

wait_for_container() {
    ## depends on healthcheck
    while [[ "$(docker inspect --format "{{json .State.Health.Status }}" "$1")" != "\"healthy\"" ]]; do
        printf "."
        sleep 1
    done
    echo
}

error_notice() {
    echo '******************************************************'
    echo 'If any errors were reported, do the following.'
    echo ' * Ensure all containers have started and are healthy'
    echo ' * Run this script again'
    echo '******************************************************'
}

get_master() {
    local master
    local IFS=$'\t'
    read -r _ master _ < <(
        docker exec "$1" \
            mysql -NBu root --password="$MARIADB_ROOT_PASSWORD" '--execute=SHOW SLAVE STATUS'
    )
    echo -n "$master"
}

start_servers() {
    export MARIADB_VERSION="${MARIADB_VERSION:-latest}"
    export MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-password}"
    export MARIADB_REPLICATION_USER="${MARIADB_REPLICATION_USER:-replication-user}"
    export MARIADB_REPLICATION_PASSWORD="${MARIADB_REPLICATION_PASSWORD:-replication}"

    docker compose up -d

    echo -n 'Waiting for containers to start .'
    wait_for_container mariadb-a
    wait_for_container mariadb-b
}

master-slave() {
    start_servers

    # Create user on master database.
    docker exec -i mariadb-a \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS
    '$MARIADB_REPLICATION_USER'@'%'
    IDENTIFIED BY '$MARIADB_REPLICATION_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO '$MARIADB_REPLICATION_USER'@'%';
FLUSH PRIVILEGES;
SQL

    # Get binlog name & position
    read -r log position _ < <(
        docker exec mariadb-a \
            mysql -NBu root --password="$MARIADB_ROOT_PASSWORD" --execute="SHOW MASTER STATUS"
    )

    # Connect slave to master
    docker exec -i mariadb-b \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
STOP SLAVE;
RESET SLAVE;
CHANGE MASTER TO
    MASTER_HOST='mariadb-a',
    MASTER_USER='$MARIADB_REPLICATION_USER',
    MASTER_PASSWORD='$MARIADB_REPLICATION_PASSWORD',
    MASTER_LOG_FILE='$log',
    MASTER_LOG_POS=$position;
START SLAVE;

SHOW SLAVE STATUS \G
SQL

    if [[ "$(get_master mariadb-b)" == mariadb-a ]]; then
        echo
        echo "master-slave replication setup successfully"
    else
        error_notice
    fi
}

master-master() {
    start_servers

    # Create user on both databases
    docker exec -i mariadb-a \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS
    '$MARIADB_REPLICATION_USER'@'%'
    IDENTIFIED BY '$MARIADB_REPLICATION_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO '$MARIADB_REPLICATION_USER'@'%';
FLUSH PRIVILEGES;
SQL

    docker exec -i mariadb-b \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS
    '$MARIADB_REPLICATION_USER'@'%'
    IDENTIFIED BY '$MARIADB_REPLICATION_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO '$MARIADB_REPLICATION_USER'@'%';
FLUSH PRIVILEGES;
SQL

    # Get binlog name & position for both servers
    read -r a_log a_position _ < <(
        docker exec mariadb-a \
            mysql -NBu root --password="$MARIADB_ROOT_PASSWORD" --execute="SHOW MASTER STATUS"
    )
    read -r b_log b_position _ < <(
        docker exec mariadb-b \
            mysql -NBu root --password="$MARIADB_ROOT_PASSWORD" --execute="SHOW MASTER STATUS"
    )

    # Connect master-master
    docker exec -i mariadb-b mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
STOP SLAVE;
RESET SLAVE;
CHANGE MASTER TO
    MASTER_HOST='mariadb-a',
    MASTER_USER='$MARIADB_REPLICATION_USER',
    MASTER_PASSWORD='$MARIADB_REPLICATION_PASSWORD',
    MASTER_LOG_FILE='$a_log',
    MASTER_LOG_POS=$a_position;
START SLAVE;
SQL

    docker exec -i mariadb-a mysql -u root --password="$MARIADB_ROOT_PASSWORD" <<SQL
STOP SLAVE;
RESET SLAVE;
CHANGE MASTER TO
    MASTER_HOST='mariadb-b',
    MASTER_USER='$MARIADB_REPLICATION_USER',
    MASTER_PASSWORD='$MARIADB_REPLICATION_PASSWORD',
    MASTER_LOG_FILE='$b_log',
    MASTER_LOG_POS=$b_position;
START SLAVE;
SQL

    sleep 5

    docker exec mariadb-a \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" --execute="SHOW SLAVE STATUS \G"
    docker exec mariadb-b \
        mysql -u root --password="$MARIADB_ROOT_PASSWORD" --execute="SHOW SLAVE STATUS \G"

    if [[ "$(get_master mariadb-a)" == mariadb-b ]] && [[ "$(get_master mariadb-b)" == mariadb-a ]]; then
        echo
        echo "master-master replication setup successfully"
    else
        error_notice
    fi
}

case "$1" in
    master-master) master-master;;
    master-slave) master-slave;;
    *) usage;;
esac
