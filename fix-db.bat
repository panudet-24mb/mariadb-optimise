@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ===================================================================
:: MariaDB Auto Configuration Script
:: Automatically detect RAM and configure MariaDB for optimal performance
:: ===================================================================

echo.
echo =========================================
echo  MariaDB Auto Configuration Script
echo =========================================
echo.

:: ตรวจสอบสิทธิ์ Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please run as Administrator!
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

:: กำหนด path ของ MariaDB (ปรับตามเครื่องของคุณ)
set MARIADB_PATH=D:\Program Files\MariaDB 10.6
set CONFIG_FILE=%MARIADB_PATH%\data\my.ini
set BACKUP_TIMESTAMP=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set BACKUP_TIMESTAMP=%BACKUP_TIMESTAMP: =0%
set BACKUP_FILE=%MARIADB_PATH%\data\my.ini.backup.%BACKUP_TIMESTAMP%

:: แสดง path ที่จะใช้งาน
echo File Locations:
echo =========================================
echo Config File: %CONFIG_FILE%
echo Backup File: %BACKUP_FILE%
echo =========================================
echo.

:: ตรวจสอบว่า config file มีอยู่จริง
if not exist "%CONFIG_FILE%" (
    echo [ERROR] Config file not found: %CONFIG_FILE%
    echo Please check MariaDB path
    pause
    exit /b 1
)

:: Backup config เดิม
echo [1/5] Backing up original config...
copy "%CONFIG_FILE%" "%BACKUP_FILE%" >nul
if %errorLevel% equ 0 (
    echo [OK] Backup successful
    echo      Location: %BACKUP_FILE%
) else (
    echo [ERROR] Backup failed!
    pause
    exit /b 1
)

:: ตรวจสอบ RAM (MB)
echo.
echo [2/5] Detecting RAM...
for /f "tokens=2 delims==" %%a in ('wmic computersystem get TotalPhysicalMemory /value ^| find "="') do set RAM_BYTES=%%a
set /a RAM_MB=%RAM_BYTES:~0,-6%
set /a RAM_GB=%RAM_MB% / 1024
echo [OK] Detected RAM: %RAM_GB% GB (%RAM_MB% MB)

:: คำนวณค่า config ตาม RAM
echo.
echo [3/5] Calculating configuration values...

:: InnoDB Buffer Pool (75% of RAM)
set /a BUFFER_POOL_MB=%RAM_MB% * 75 / 100
set /a BUFFER_POOL_INSTANCES=%RAM_GB% / 4
if %BUFFER_POOL_INSTANCES% lss 4 set BUFFER_POOL_INSTANCES=4
if %BUFFER_POOL_INSTANCES% gtr 32 set BUFFER_POOL_INSTANCES=32

:: Temporary Tables (10% of RAM)
set /a TMP_TABLE_MB=%RAM_MB% * 10 / 100
if %TMP_TABLE_MB% gtr 2048 set TMP_TABLE_MB=2048

:: Thread Pool
set /a THREAD_POOL_SIZE=%NUMBER_OF_PROCESSORS% * 2
if %THREAD_POOL_SIZE% lss 8 set THREAD_POOL_SIZE=8
if %THREAD_POOL_SIZE% gtr 64 set THREAD_POOL_SIZE=64

:: Max Connections
set /a MAX_CONNECTIONS=100 + (%RAM_GB% * 10)
if %MAX_CONNECTIONS% lss 150 set MAX_CONNECTIONS=150
if %MAX_CONNECTIONS% gtr 500 set MAX_CONNECTIONS=500

:: InnoDB Log File Size (ขึ้นกับ RAM)
if %RAM_GB% lss 16 (
    set LOG_FILE_SIZE=512M
) else if %RAM_GB% lss 32 (
    set LOG_FILE_SIZE=1G
) else if %RAM_GB% lss 64 (
    set LOG_FILE_SIZE=1536M
) else (
    set LOG_FILE_SIZE=2G
)

echo [OK] Calculation completed

:: แสดงค่าที่จะใช้
echo.
echo =========================================
echo  Configuration Values:
echo =========================================
echo RAM: %RAM_GB% GB
echo Buffer Pool: %BUFFER_POOL_MB% MB
echo Buffer Pool Instances: %BUFFER_POOL_INSTANCES%
echo Tmp Table: %TMP_TABLE_MB% MB
echo Thread Pool Size: %THREAD_POOL_SIZE%
echo Max Connections: %MAX_CONNECTIONS%
echo Log File Size: %LOG_FILE_SIZE%
echo =========================================
echo.

:: ยืนยันก่อนดำเนินการ
set /p CONFIRM="Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo Operation cancelled
    pause
    exit /b 0
)

:: สร้าง config ใหม่
echo.
echo [4/5] Creating new configuration...

(
echo [mysqld]
echo datadir=%MARIADB_PATH:\=/%/data
echo port=3306
echo.
echo # ======================================
echo # Performance Configuration
echo # Auto-generated: %date% %time%
echo # RAM Detected: %RAM_GB% GB
echo # ======================================
echo.
echo # InnoDB Buffer Pool
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
echo # Temporary Tables
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
echo # Binary Log Settings
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

if %errorLevel% equ 0 (
    echo [OK] New configuration created successfully
    echo      Location: %CONFIG_FILE%
) else (
    echo [ERROR] Configuration creation failed!
    echo Restoring from backup...
    copy "%BACKUP_FILE%" "%CONFIG_FILE%" >nul
    pause
    exit /b 1
)

:: ถามว่าจะ restart service หรือไม่
echo.
echo [5/5] Checking MariaDB Service...

:: ตรวจสอบว่า service ชื่ออะไร
set SERVICE_NAME=MariaDB

echo [OK] Service detected: %SERVICE_NAME%

echo.
echo =========================================
echo  WARNING: innodb_log_file_size
echo =========================================
echo Old value in config: 50M
echo New value: %LOG_FILE_SIZE%
echo.
echo Log file size has changed
echo Need to delete old ib_logfile files
echo =========================================
echo.

set /p RESTART="Restart MariaDB and delete log files automatically? (Y/N): "
if /i "%RESTART%"=="Y" (
    echo.
    echo Stopping MariaDB Service...
    net stop %SERVICE_NAME%
    
    echo Deleting old log files...
    del "%MARIADB_PATH%\data\ib_logfile*" 2>nul
    
    echo Starting MariaDB Service...
    net start %SERVICE_NAME%
    
    if %errorLevel% equ 0 (
        echo [OK] Restart successful
    ) else (
        echo [ERROR] Restart failed!
        echo Please check log: %MARIADB_PATH%\data\mysql-error.log
        echo.
        echo To restore old config:
        echo copy "%BACKUP_FILE%" "%CONFIG_FILE%"
        pause
        exit /b 1
    )
) else (
    echo.
    echo Please restart MariaDB manually:
    echo 1. Open Services (services.msc)
    echo 2. Find %SERVICE_NAME%
    echo 3. Stop service
    echo 4. Delete files: %MARIADB_PATH%\data\ib_logfile*
    echo 5. Start service
)

echo.
echo =========================================
echo  COMPLETED!
echo =========================================
echo.
echo Files created and modified:
echo =========================================
echo [New Config]
echo %CONFIG_FILE%
echo.
echo [Old Backup]
echo %BACKUP_FILE%
echo.
echo [Log Files]
echo %MARIADB_PATH%\data\mysql-error.log
echo %MARIADB_PATH%\data\mysql-slow.log
echo =========================================
echo.
echo Verify configuration with SQL:
echo   SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
echo   SHOW VARIABLES LIKE 'max_connections';
echo   SHOW VARIABLES LIKE 'innodb_log_file_size';
echo.
echo To restore old config:
echo   copy "%BACKUP_FILE%" "%CONFIG_FILE%"
echo   net stop MariaDB
echo   net start MariaDB
echo =========================================
echo.

pause