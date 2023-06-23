#!/bin/bash
#error occured: can't drop database, and my solution was comment to row with DROP DATABASE in demo.sql, sended to docker
`mkdir -p "${PWD%/*}/sql/init_db/demo"`
`sed -e 's/DROP DATABASE demo/--DROP DATABASE demo/' -e 's/CREATE DATABASE demo/--CREATE DATABASE demo/' \
     "${PWD%/*}/sql/init_db/demo.sql" > "${PWD%/*}/sql/init_db/demo/init_db_replace.sql"`
sql_src="${PWD%/*}/sql/init_db/demo"
sql_path_rep="${PWD%/*}/sql/main"
docker run --rm -d \
        --name sde_postgres \
        -e POSTGRES_USER=test_sde \
        -e POSTGRES_PASSWORD=@sde_password012 \
        -e POSTGRES_DB=demo \
        -p 5432:5432 \
        -v $sql_src:/docker-entrypoint-initdb.d \
           postgres
