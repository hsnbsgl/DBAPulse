puts "HAMMERDB TPROC-C TEST START"
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
puts "BUILDING ISOLATED TPROC-C SCHEMA"
buildschema
clearscript
diset tpcc mssqls_driver timed
diset tpcc mssqls_rampup 0
diset tpcc mssqls_duration 10
diset tpcc mssqls_timeprofile true
diset tpcc mssqls_total_iterations 10000000
# Use five users for the timed workload after the one-user schema build.
diset tpcc mssqls_num_vu 5
loadscript
vuset logtotemp 1
vuset vu 5
puts "RUNNING 5 VIRTUAL USERS FOR 10 MINUTES"
vucreate
set jobid [vurun]
vudestroy
puts "HAMMERDB JOB ID: $jobid"
puts "HAMMERDB TPROC-C TEST COMPLETE"