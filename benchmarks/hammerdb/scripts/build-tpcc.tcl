puts "HAMMERDB SCHEMA BUILD START"
dbset db mssqls
dbset bm TPROC-C
diset connection mssqls_server 127.0.0.1
diset connection mssqls_linux_server 127.0.0.1
diset connection mssqls_tcp true
diset connection mssqls_port 1433
diset connection mssqls_authentication sql
diset connection mssqls_linux_authent sql
diset connection mssqls_uid sa
diset connection mssqls_pass $::env(MSSQL_PASSWORD)
diset connection mssqls_encrypt_connection false
diset connection mssqls_trust_server_cert true
diset tpcc mssqls_dbase DBAPULSE_HAMMERDB_TPCC
diset tpcc mssqls_count_ware 1
diset tpcc mssqls_num_vu 1
buildschema
puts "HAMMERDB SCHEMA BUILD COMPLETE"
