-- What is SQL Server actually waiting on? Two snapshots 60s apart, diffed.
--
-- Does NOT require catching a slow query in the act, unlike sys.dm_exec_requests.
-- Read-only except for two temp tables. Safe on production.
--
-- Investigation Round 6: blocking_session_id = 0 ruled out H5 (lock blocking).
-- This distinguishes what remains.

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#w1') IS NOT NULL DROP TABLE #w1;
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #w1 FROM sys.dm_os_wait_stats;

PRINT 'Sampling for 60 seconds... exercise the app now (load the feed).';
WAITFOR DELAY '00:01:00';

IF OBJECT_ID('tempdb..#w2') IS NOT NULL DROP TABLE #w2;
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #w2 FROM sys.dm_os_wait_stats;

SELECT TOP 15
    w2.wait_type,
    w2.waiting_tasks_count - w1.waiting_tasks_count      AS waits,
    w2.wait_time_ms        - w1.wait_time_ms             AS total_wait_ms,
    (w2.wait_time_ms - w1.wait_time_ms)
        - (w2.signal_wait_time_ms - w1.signal_wait_time_ms) AS resource_wait_ms,
    w2.signal_wait_time_ms - w1.signal_wait_time_ms      AS signal_wait_ms,
    CASE WHEN (w2.waiting_tasks_count - w1.waiting_tasks_count) > 0
         THEN (w2.wait_time_ms - w1.wait_time_ms)
              / (w2.waiting_tasks_count - w1.waiting_tasks_count)
         ELSE 0 END                                      AS avg_ms_per_wait
FROM #w2 w2
JOIN #w1 w1 ON w1.wait_type = w2.wait_type
WHERE w2.wait_time_ms - w1.wait_time_ms > 0
  AND w2.wait_type NOT IN (   -- benign idle/background waits
      'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK',
      'SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE',
      'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
      'BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT','CLR_AUTO_EVENT',
      'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT',
      'XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP','ONDEMAND_TASK_QUEUE',
      'BROKER_EVENTHANDLER','SLEEP_BPOOL_FLUSH','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
      'SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE',
      'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','QDS_SHUTDOWN_QUEUE',
      'PREEMPTIVE_XE_GETTARGETSTATE','PWAIT_ALL_COMPONENTS_INITIALIZED')
ORDER BY total_wait_ms DESC;

-- HOW TO READ IT
--
-- SOS_SCHEDULER_YIELD high, with signal_wait_ms a large share
--     -> CPU starvation. Round 4's db.t3.small sizing is the fix.
--        (signal wait = time runnable-but-waiting-for-a-CPU.)
--
-- RESOURCE_SEMAPHORE
--     -> Memory grant starvation. Queries queue for a memory grant before
--        they can even start. Fits SQL Express's 1410 MB buffer-pool cap on
--        a 2 GB instance. A ~25s constant would be the grant timeout queue.
--
-- PAGEIOLATCH_SH / PAGEIOLATCH_EX
--     -> Reading data pages from disk. Would contradict physical reads = 0.
--
-- LCK_M_*
--     -> Lock waits after all. Would contradict blocking_session_id = 0,
--        unless the earlier sample simply missed the window.
--
-- ASYNC_NETWORK_IO
--     -> SQL Server is waiting on the CLIENT to consume rows. That would move
--        the problem into the app or the network, not the database.
