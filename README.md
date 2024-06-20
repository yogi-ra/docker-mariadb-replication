# MariaDB Replication

![Experimental](https://img.shields.io/badge/Experimental-red)

Scripts to automate the setup of MariaDB replication using docker.

## Master-Master
Deploy a master-master setup with MariaDB v10.1.48
```shell
MARIADB_VERSION=10.1.48 ./deploy.sh master-master
```

This will deploy two mutually replicated MariaDB containers `mariadb-a` and `mariadb-b`.

## Master-Slave
Deploy a master-slave setup with MariaDB v10.1.48
```shell
MARIADB_VERSION=10.1.48 ./deploy.sh master-slave
```
This will deploy two replicated MariaDB containers `mariadb-a` and `mariadb-b`, where `mariadb-b` is the slave.
