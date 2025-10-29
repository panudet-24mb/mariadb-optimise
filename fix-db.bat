@echo off
setlocal enabledelayedexpansion

echo.
echo =========================================
echo  MariaDB Auto Configuration Script
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
set "MARIADB_PATH=D:\Program Files\MariaDB 10.6"
set "DATA_PATH=%MARIADB_PATH%\data"
set "CONFIG_FILE=%DATA_PATH%\my.ini"

:: Create backup filename
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
set "BACKUP_FILE=%DATA_PATH%\my.ini.backup.%mydate%_%mytime%"

echo File Locations:
echo =========================================
echo Config: %CONFIG_FILE%
echo Backup: %BACKUP_FILE%
echo =========================================
echo.

:: Check config exists
if not exist "%CONFIG_FILE%" (
    echo [ERROR] Config file not found!
    pause
    exit /b 1
)

:: Backup
echo [1/5] Backing up config...
copy "%CONFIG_FILE%" "%BACKUP_FILE%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Backup failed!
    pause
    exit /b 1
)
echo [OK] Backup successful

:: Detect RAM using PowerShell - MORE ACCURATE
echo.
echo [2/5] Detecting RAM...

for /f "usebackq delims=" %%i in (`powershell -command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)"`) do set RAM_GB=%%i
set /a RAM_MB=%RAM_GB% * 1024

echo [OK] RAM: %RAM_GB% GB (%RAM_MB% MB)

:: Calculate values
echo.
echo [3/5] Calculating values...
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

:: Log File Size based on RAM
if %RAM_GB% lss 16 (
    set LOG_FILE_SIZE=512M
    set LOG_FILE_SIZE_NUM=512
) else if %RAM_GB% lss 32 (
    set LOG_FILE_SIZE=1G
    set LOG_FILE_SIZE_NUM=1024
) else if %RAM_GB% lss 64 (
    set LOG_FILE_SIZE=1536M
    set LOG_FILE_SIZE_NUM=1536
) else (
    set LOG_FILE_SIZE=2G
    set LOG_FILE_SIZE_NUM=2048
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
echo Log File Size: %LOG_FILE_SIZE% (%LOG_FILE_SIZE_NUM% MB)
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
echo [4/5] Creating config...

(
echo [mysqld]
echo datadir=%MARIADB_PATH:\=/%/data
echo port=3306
echo.
echo # Auto-generated: %date% %time%
echo # RAM: %RAM_GB% GB ^(%RAM_MB% MB^)
echo.
echo # InnoDB Buffer Pool ^(75%% of RAM^)
echo innodb_buffer_pool_size=%BUFFER_POOL_MB%M
echo innodb_buffer_pool_instances=%BUFFER_POOL_INSTANCES%
echo innodb_log_file_size=%LOG_FILE_SIZE%
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
echo # Query Cache Disabled
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
echo expire_logs_days=5
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
    copy "%BACKUP_FILE%" "%CONFIG_FILE%" >nul 2>&1
    pause
    exit /b 1
)
echo [OK] Config created

:: Service restart
echo.
echo [5/5] Service Management
echo =========================================
echo WARNING: Log file size changed
echo Old: 50M
echo New: %LOG_FILE_SIZE% (%LOG_FILE_SIZE_NUM% MB)
echo Must delete old ib_logfile files
echo =========================================
echo.

set SERVICE_NAME=MariaDB

set /p RESTART="Restart MariaDB automatically? (Y/N): "
if /i "%RESTART%"=="Y" (
    echo.
    echo Stopping MariaDB...
    net stop %SERVICE_NAME% 2>nul
    
    timeout /t 3 /nobreak >nul
    
    echo Deleting old log files...
    del "%DATA_PATH%\ib_logfile*" 2>nul
    
    echo Starting MariaDB...
    net start %SERVICE_NAME%
    
    timeout /t 3 /nobreak >nul
    
    if errorlevel 1 (
        echo [ERROR] Failed to start!
        echo Check: %DATA_PATH%\mysql-error.log
        pause
        exit /b 1
    )
    echo [OK] MariaDB restarted successfully
) else (
    echo.
    echo Manual restart steps:
    echo 1. Run: net stop MariaDB
    echo 2. Delete: %DATA_PATH%\ib_logfile*
    echo 3. Run: net start MariaDB
)

echo.
echo =========================================
echo COMPLETED!
echo =========================================
echo.
echo [Config File]
echo %CONFIG_FILE%
echo.
echo [Backup File]
echo %BACKUP_FILE%
echo.
echo Verify with SQL:
echo   SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
echo   SHOW VARIABLES LIKE 'max_connections';
echo   SHOW VARIABLES LIKE 'innodb_log_file_size';
echo.
echo To restore backup:
echo   copy "%BACKUP_FILE%" "%CONFIG_FILE%"
echo   net stop MariaDB
echo   net start MariaDB
echo =========================================
echo.

pause