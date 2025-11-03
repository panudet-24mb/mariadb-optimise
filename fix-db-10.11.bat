@echo off
setlocal enabledelayedexpansion

echo.
echo =========================================
echo  MariaDB 11.3 Auto Configuration Script
echo =========================================
echo.

:: Check Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please run as Administrator!
    pause
    exit /b 1
)

:: MariaDB Path - EDIT THIS LINE if different
set "MARIADB_PATH=D:\Program Files\MariaDB 11.3"
set "DATA_PATH=%MARIADB_PATH%\data"
set "CONFIG_FILE=%DATA_PATH%\my.ini"

:: Create backup timestamp
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set "BACKUP_TIMESTAMP=%mydate%_%mytime%"
set "BACKUP_SUFFIX=.old.%BACKUP_TIMESTAMP%"

echo File Locations:
echo =========================================
echo Config: %CONFIG_FILE%
echo Backup Suffix: %BACKUP_SUFFIX%
echo =========================================
echo.

:: Check config exists
if not exist "%CONFIG_FILE%" (
    echo [ERROR] Config file not found!
    pause
    exit /b 1
)

:: Backup config file
echo.
echo [1/4] Backing up config...
copy "%CONFIG_FILE%" "%CONFIG_FILE%%BACKUP_SUFFIX%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Backup failed!
    pause
    exit /b 1
)
echo [OK] Config backup: %CONFIG_FILE%%BACKUP_SUFFIX%

:: Detect RAM using PowerShell
echo.
echo [2/4] Detecting RAM...

for /f "usebackq delims=" %%i in (`powershell -command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)"`) do set RAM_GB=%%i
set /a RAM_MB=%RAM_GB% * 1024

echo [OK] RAM: %RAM_GB% GB (%RAM_MB% MB)

:: Calculate values
echo.
echo [3/4] Calculating values...
set /a BUFFER_POOL_MB=%RAM_MB% * 75 / 100
set /a BUFFER_POOL_INSTANCES=%RAM_GB% / 4
if %BUFFER_POOL_INSTANCES% lss 4 set BUFFER_POOL_INSTANCES=4
if %BUFFER_POOL_INSTANCES% gtr 32 set BUFFER_POOL_INSTANCES=32

set /a TMP_TABLE_MB=%RAM_MB% * 10 / 100
if %TMP_TABLE_MB% gtr 2048 set TMP_TABLE_MB=2048

set /a THREAD_POOL_SIZE=%NUMBER_OF_PROCESSORS% * 2
if %THREAD_POOL_SIZE% lss 8 set THREAD_POOL_SIZE=8
if %THREAD_POOL_SIZE% gtr 64 set THREAD_POOL_SIZE=64

set /a MAX_CONNECTIONS=100 + (%RAM_GB% * 10)
if %MAX_CONNECTIONS% lss 150 set MAX_CONNECTIONS=150
if %MAX_CONNECTIONS% gtr 500 set MAX_CONNECTIONS=500

:: Redo Log Capacity based on RAM (MariaDB 11.3+)
if %RAM_GB% lss 16 (
    set REDO_LOG_CAPACITY=512M
) else if %RAM_GB% lss 32 (
    set REDO_LOG_CAPACITY=1G
) else if %RAM_GB% lss 64 (
    set REDO_LOG_CAPACITY=2G
) else (
    set REDO_LOG_CAPACITY=4G
)

echo [OK] Calculation done

:: Display values
echo.
echo =========================================
echo Configuration Values:
echo =========================================
echo RAM: %RAM_GB% GB (%RAM_MB% MB)
echo Buffer Pool: %BUFFER_POOL_MB% MB
echo Buffer Instances: %BUFFER_POOL_INSTANCES%
echo Tmp Table: %TMP_TABLE_MB% MB
echo Thread Pool: %THREAD_POOL_SIZE%
echo Max Connections: %MAX_CONNECTIONS%
echo Redo Log Capacity: %REDO_LOG_CAPACITY%
echo =========================================
echo.

set /p CONFIRM="Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo Cancelled
    pause
    exit /b 0
)

:: Create config
echo.
echo [4/4] Creating config...

(
echo [mysqld]
echo datadir=%MARIADB_PATH:\=/%/data
echo port=3306
echo.
echo # Auto-generated: %date% %time%
echo # RAM: %RAM_GB% GB ^(%RAM_MB% MB^)
echo # MariaDB 11.3 Configuration
echo.
echo # InnoDB Buffer Pool ^(75%% of RAM^)
echo innodb_buffer_pool_size=%BUFFER_POOL_MB%M
echo innodb_buffer_pool_instances=%BUFFER_POOL_INSTANCES%
echo innodb_redo_log_capacity=%REDO_LOG_CAPACITY%
echo innodb_log_buffer_size=128M
echo innodb_flush_log_at_trx_commit=1
echo innodb_flush_method=unbuffered
echo innodb_file_per_table=1
echo innodb_stats_on_metadata=0
echo.
echo # Connection Settings
echo max_connections=%MAX_CONNECTIONS%
echo max_allowed_packet=500M
echo connect_timeout=15
echo wait_timeout=120
echo interactive_timeout=120
echo.
echo # Thread Pool
echo thread_handling=pool-of-threads
echo thread_pool_size=%THREAD_POOL_SIZE%
echo thread_pool_max_threads=1000
echo thread_cache_size=32
echo.
echo # Buffer Settings
echo key_buffer_size=256M
echo read_buffer_size=8M
echo read_rnd_buffer_size=16M
echo sort_buffer_size=16M
echo join_buffer_size=8M
echo myisam_sort_buffer_size=64M
echo.
echo # Temporary Tables ^(10%% of RAM^)
echo tmp_table_size=%TMP_TABLE_MB%M
echo max_heap_table_size=%TMP_TABLE_MB%M
echo.
echo # Table Cache
echo table_open_cache=4096
echo table_definition_cache=2048
echo.
echo # Query Cache ^(Disabled by default in MariaDB 10.5+^)
echo query_cache_type=0
echo query_cache_size=0
echo.
echo # Character Set
echo character-set-server=utf8mb4
echo collation-server=utf8mb4_unicode_ci
echo.
echo # Logging
echo log-bin=%MARIADB_PATH:\=/%/data/mysql-bin.log
echo general-log=0
echo general-log-file=%MARIADB_PATH:\=/%/data/mysql.log
echo log-error=%MARIADB_PATH:\=/%/data/mysql-error.log
echo slow-query-log=1
echo slow-query-log-file=%MARIADB_PATH:\=/%/data/mysql-slow.log
echo long_query_time=2
echo.
echo # Binary Log
echo binlog_format=MIXED
echo max_binlog_size=200M
echo binlog_expire_logs_seconds=432000
echo sync_binlog=1
echo.
echo # Replication
echo server-id=8888
echo relay_log_purge=1
echo.
echo [client]
echo port=3306
echo plugin-dir=%MARIADB_PATH:\=/%/lib/plugin
echo.
echo [mysqldump]
echo quick
echo max_allowed_packet=500M
echo.
echo [myisamchk]
echo key_buffer_size=128M
echo sort_buffer_size=128M
echo read_buffer=2M
echo write_buffer=2M
) > "%CONFIG_FILE%"

if errorlevel 1 (
    echo [ERROR] Failed to create config!
    copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%" >nul 2>&1
    pause
    exit /b 1
)
echo [OK] Config created

:: Service restart
echo.
echo =========================================
echo Service Management
echo =========================================
echo.
echo MariaDB 11.3 can change redo log capacity dynamically.
echo A restart is recommended to apply all settings.
echo.

set /p RESTART="Restart MariaDB? (Y/N): "
if /i "!RESTART!"=="Y" (
    echo.
    echo Restarting MariaDB...
    net stop MariaDB 2>nul
    timeout /t 3 /nobreak >nul
    net start MariaDB
    
    timeout /t 3 /nobreak >nul
    
    sc query MariaDB | find "RUNNING" >nul
    if errorlevel 1 (
        echo [ERROR] MariaDB failed to start!
        echo Check: %DATA_PATH%\mysql-error.log
        echo.
        echo To restore:
        echo   copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%"
        echo   net start MariaDB
        pause
        exit /b 1
    )
    echo [OK] MariaDB restarted successfully
) else (
    echo.
    echo Remember to restart MariaDB:
    echo   net stop MariaDB
    echo   net start MariaDB
)

echo.
echo =========================================
echo COMPLETED!
echo =========================================
echo.
echo [Config File]
echo %CONFIG_FILE%
echo.
echo [Config Backup]
echo %CONFIG_FILE%%BACKUP_SUFFIX%
echo.
echo Verify with SQL:
echo   SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
echo   SHOW VARIABLES LIKE 'max_connections';
echo   SHOW VARIABLES LIKE 'innodb_redo_log_capacity';
echo.
echo To restore config:
echo   copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%"
echo   net stop MariaDB
echo   net start MariaDB
echo.
echo =========================================
echo.

pause