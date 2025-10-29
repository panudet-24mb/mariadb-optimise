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

:: Read OLD log_file_size from current config
set OLD_LOG_SIZE=unknown
for /f "tokens=2 delims==" %%a in ('findstr /i "innodb_log_file_size" "%CONFIG_FILE%" 2^>nul') do (
    set OLD_LOG_SIZE=%%a
)
set OLD_LOG_SIZE=%OLD_LOG_SIZE: =%
echo [INFO] Current log file size: %OLD_LOG_SIZE%

:: Backup config file (rename)
echo.
echo [1/5] Backing up config...
copy "%CONFIG_FILE%" "%CONFIG_FILE%%BACKUP_SUFFIX%" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Backup failed!
    pause
    exit /b 1
)
echo [OK] Config backup: %CONFIG_FILE%%BACKUP_SUFFIX%

:: Detect RAM using PowerShell
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

:: Check if log file size changed
set LOG_SIZE_CHANGED=NO
if /i not "%OLD_LOG_SIZE%"=="%LOG_FILE_SIZE%" (
    set LOG_SIZE_CHANGED=YES
)

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
echo.
echo Log File Size:
echo   Old: %OLD_LOG_SIZE%
echo   New: %LOG_FILE_SIZE% (%LOG_FILE_SIZE_NUM% MB)
echo   Changed: %LOG_SIZE_CHANGED%
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
    copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%" >nul 2>&1
    pause
    exit /b 1
)
echo [OK] Config created

:: Service restart
echo.
echo [5/5] Service Management
echo =========================================

if "%LOG_SIZE_CHANGED%"=="YES" (
    echo WARNING: Log file size CHANGED!
    echo Old: %OLD_LOG_SIZE%
    echo New: %LOG_FILE_SIZE%
    echo.
    echo *** Will RENAME ib_logfile files ***
    echo *** No files will be deleted ***
    echo =========================================
    echo.
    
    set /p RESTART="Restart MariaDB and RENAME log files? (Y/N): "
    if /i "!RESTART!"=="Y" (
        echo.
        echo Stopping MariaDB...
        net stop MariaDB 2>nul
        
        timeout /t 3 /nobreak >nul
        
        :: Rename ib_logfile files
        echo Renaming old log files...
        set RENAME_SUCCESS=YES
        
        if exist "%DATA_PATH%\ib_logfile0" (
            ren "%DATA_PATH%\ib_logfile0" "ib_logfile0%BACKUP_SUFFIX%" 2>nul
            if errorlevel 1 (
                echo [ERROR] Failed to rename ib_logfile0
                set RENAME_SUCCESS=NO
            ) else (
                echo [OK] Renamed: ib_logfile0 -^> ib_logfile0%BACKUP_SUFFIX%
            )
        )
        
        if exist "%DATA_PATH%\ib_logfile1" (
            ren "%DATA_PATH%\ib_logfile1" "ib_logfile1%BACKUP_SUFFIX%" 2>nul
            if errorlevel 1 (
                echo [ERROR] Failed to rename ib_logfile1
                set RENAME_SUCCESS=NO
            ) else (
                echo [OK] Renamed: ib_logfile1 -^> ib_logfile1%BACKUP_SUFFIX%
            )
        )
        
        :: Check if old files still exist
        if exist "%DATA_PATH%\ib_logfile0" (
            echo [ERROR] ib_logfile0 still exists!
            echo Cannot start MariaDB with old log files
            echo.
            echo Please manually:
            echo 1. Rename: ren "%DATA_PATH%\ib_logfile0" "ib_logfile0%BACKUP_SUFFIX%"
            echo 2. Rename: ren "%DATA_PATH%\ib_logfile1" "ib_logfile1%BACKUP_SUFFIX%"
            echo 3. Start: net start MariaDB
            pause
            exit /b 1
        )
        
        if "!RENAME_SUCCESS!"=="YES" (
            echo [OK] All log files renamed successfully
        ) else (
            echo [WARNING] Some files could not be renamed
        )
        
        :: Start MariaDB
        echo.
        echo Starting MariaDB with new log file size...
        echo MariaDB will create new ib_logfile files: %LOG_FILE_SIZE%
        net start MariaDB
        
        timeout /t 5 /nobreak >nul
        
        sc query MariaDB | find "RUNNING" >nul
        if errorlevel 1 (
            echo [ERROR] MariaDB failed to start!
            echo.
            echo To restore:
            echo 1. ren "%DATA_PATH%\ib_logfile0%BACKUP_SUFFIX%" "ib_logfile0"
            echo 2. ren "%DATA_PATH%\ib_logfile1%BACKUP_SUFFIX%" "ib_logfile1"
            echo 3. copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%"
            echo 4. net start MariaDB
            echo.
            echo Check error log: %DATA_PATH%\mysql-error.log
            pause
            exit /b 1
        )
        
        echo [OK] MariaDB started successfully!
        echo.
        echo New ib_logfile files created with size: %LOG_FILE_SIZE%
        echo Old files preserved as:
        echo   - ib_logfile0%BACKUP_SUFFIX%
        echo   - ib_logfile1%BACKUP_SUFFIX%
        
        timeout /t 3 /nobreak >nul
        
        :: Check if new files created
        if exist "%DATA_PATH%\ib_logfile0" (
            echo.
            echo [INFO] New log files confirmed:
            dir "%DATA_PATH%\ib_logfile0" | find "ib_logfile0"
            dir "%DATA_PATH%\ib_logfile1" | find "ib_logfile1"
        )
        
    ) else (
        echo.
        echo Manual restart steps:
        echo 1. net stop MariaDB
        echo 2. ren "%DATA_PATH%\ib_logfile0" "ib_logfile0%BACKUP_SUFFIX%"
        echo 3. ren "%DATA_PATH%\ib_logfile1" "ib_logfile1%BACKUP_SUFFIX%"
        echo 4. net start MariaDB
    )
) else (
    echo Log file size NOT changed
    echo Old: %OLD_LOG_SIZE%
    echo New: %LOG_FILE_SIZE%
    echo.
    echo *** NO need to rename ib_logfile ***
    echo =========================================
    echo.
    
    set /p RESTART="Restart MariaDB? (Y/N): "
    if /i "!RESTART!"=="Y" (
        echo.
        echo Restarting MariaDB...
        net stop MariaDB 2>nul
        timeout /t 2 /nobreak >nul
        net start MariaDB
        
        sc query MariaDB | find "RUNNING" >nul
        if errorlevel 1 (
            echo [ERROR] MariaDB failed to start!
            echo Check: %DATA_PATH%\mysql-error.log
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
if "%LOG_SIZE_CHANGED%"=="YES" (
    echo [Old Log Files - RENAMED, NOT DELETED]
    if exist "%DATA_PATH%\ib_logfile0%BACKUP_SUFFIX%" (
        echo %DATA_PATH%\ib_logfile0%BACKUP_SUFFIX%
    )
    if exist "%DATA_PATH%\ib_logfile1%BACKUP_SUFFIX%" (
        echo %DATA_PATH%\ib_logfile1%BACKUP_SUFFIX%
    )
    echo.
    echo [New Log Files]
    if exist "%DATA_PATH%\ib_logfile0" (
        echo %DATA_PATH%\ib_logfile0
    )
    if exist "%DATA_PATH%\ib_logfile1" (
        echo %DATA_PATH%\ib_logfile1
    )
    echo.
)
echo Verify with SQL:
echo   SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
echo   SHOW VARIABLES LIKE 'max_connections';
echo   SHOW VARIABLES LIKE 'innodb_log_file_size';
echo.
echo To restore config:
echo   copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%"
echo.
if "%LOG_SIZE_CHANGED%"=="YES" (
    echo To restore old log files:
    echo   net stop MariaDB
    echo   del "%DATA_PATH%\ib_logfile*" ^(delete new files^)
    echo   ren "%DATA_PATH%\ib_logfile0%BACKUP_SUFFIX%" "ib_logfile0"
    echo   ren "%DATA_PATH%\ib_logfile1%BACKUP_SUFFIX%" "ib_logfile1"
    echo   copy "%CONFIG_FILE%%BACKUP_SUFFIX%" "%CONFIG_FILE%"
    echo   net start MariaDB
    echo.
    echo You can safely delete old files after confirming everything works:
    echo   del "%DATA_PATH%\ib_logfile0%BACKUP_SUFFIX%"
    echo   del "%DATA_PATH%\ib_logfile1%BACKUP_SUFFIX%"
    echo   del "%CONFIG_FILE%%BACKUP_SUFFIX%"
)
echo =========================================
echo.

pause