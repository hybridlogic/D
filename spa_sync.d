#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option defaultargs
#pragma D option bufsize=80m

inline uint64_t TXG_MASK = 3;


struct spa_info {
	spa_t *spa;
	uint64_t start_time;
	uint64_t prev_time;
	uint64_t deferred;
	int zio_wait;
	uint64_t txg;
	uint64_t tx;
	uint64_t misc_ts;
	uint64_t tx_commit;
	uint64_t free;
	uint64_t free_time;
	uint64_t dsl_dataset_sync;
	uint64_t dsl_dataset_sync_time;
	uint64_t converged;
	uint64_t dsl_pool_sync_count;
	uint64_t dsl_pool_sync_time;
	uint64_t dsl_pool_sync;
	uint64_t dsl_dataset_sync2_time;
	uint64_t dsl_dataset_sync2;
	uint64_t dsl_sync_task_group_sync_time;
	uint64_t dsl_sync_task_group_sync;
	uint64_t dmu_objset_sync_time;
	uint64_t dmu_objset_sync;
	uint64_t dsl_dir_sync_time;
	uint64_t dsl_dir_sync;
	uint64_t ddt_sync_time;
	uint64_t ddt_sync;
	uint64_t dsl_scan_sync_time;
	uint64_t dsl_scan_sync;
	uint64_t stage;
};


struct spa_info spas[struct thread *];



fbt::spa_sync:entry
{
	this->ts = timestamp;
	this->thr = curthread;
	spas[this->thr].spa = args[0];
	spas[this->thr].txg = args[1];
	spas[this->thr].start_time = this->ts;
/*
	@times[this->spa->spa_name, "idle"] = sum(this->ts - spas[this->thr].prev_time);
 */
/*
 	spas[this->thr].prev_time ? printf("idle time:\t%u\n", this->ts - spas[this->thr].prev_time) : (void)1;
 */
}

fbt::spa_sync:return
/spas[curthread].spa != 0/
{
	this->ts = timestamp;
	this->thr = curthread;
	spas[this->thr].prev_time = this->ts;
	this->spa = spas[this->thr].spa;
/*
	@counts[this->spa->spa_name, "runs"] = count();
	@times[this->spa->spa_name, "running"] = sum(this->ts - spas[this->thr].start_time);
 */
 	this->s = spas[this->thr].start_time;
 	this->total = this->ts - this->s;
 	printf("total running time:\t\t%u\n", this->total);
	printf("\n");
 	printf("misc1 time:\t\t\t%u\n", spas[curthread].misc_ts - this->s);
	printf("\n");
 	printf("deferred freeing time:\t\t%u\n", spas[curthread].deferred);
	printf("\n");
	printf("convergance passes:\t\t%u\n", spas[curthread].dsl_pool_sync_count);
	printf("total dsl_pool_sync time:\t%u\n", spas[curthread].dsl_pool_sync_time);
	printf("\tdatasets sync time:\t%u\n", spas[curthread].dsl_dataset_sync2_time + spas[curthread].dsl_dataset_sync_time);
	printf("\tsynctask time:\t\t%u\n", spas[curthread].dsl_sync_task_group_sync_time);
	printf("\tmos time:\t\t%u\n", spas[curthread].dmu_objset_sync_time);
	printf("\tdsl dir time:\t\t%u\n",  spas[curthread].dsl_dir_sync_time);
	printf("ddt sync time:\t\t\t%u\n", spas[curthread].ddt_sync_time);
	printf("block freeing time:\t\t%u\n", spas[curthread].free_time);
	printf("dsl scan time:\t\t\t%u\n", spas[curthread].dsl_scan_sync_time);
	printf("\t(includes async destroy and deadlist processing time)\n");
	printf("\n");
	printf("total time to convergance:\t%u\n", spas[curthread].converged - this->s);
	printf("misc2 time:\t\t\t%u\n", this->ts - spas[curthread].converged);
	exit(0);
}

fbt::dmu_tx_create_assigned:return
/spas[curthread].spa != 0 && spas[curthread].tx == 0/
{
	spas[curthread].misc_ts = timestamp;
	spas[curthread].tx = arg1;
}

fbt::dmu_tx_commit:entry
/spas[curthread].tx == arg1/
{
	spas[curthread].tx_commit = timestamp;
}

fbt::bpobj_iterate_impl:entry
/spas[curthread].spa != 0 &&
    args[0] == &(spas[curthread].spa->spa_deferred_bpobj)/
{
	spas[curthread].deferred = timestamp;
}

fbt::bpobj_iterate_impl:return
/spas[curthread].spa != 0 &&
    spas[curthread].deferred != 0/
{
	spas[curthread].zio_wait = 1;
}

fbt::zio_wait:return
/spas[curthread].spa != 0 &&
    spas[curthread].zio_wait != 0/
{
	spas[curthread].deferred = timestamp - spas[curthread].deferred;
}

fbt::bplist_iterate:entry
/spas[curthread].spa != 0 &&
    args[0] ==
    &(spas[curthread].spa->spa_free_bplist[spas[curthread].txg & TXG_MASK])/
{
	spas[curthread].free = timestamp;
	spas[curthread].zio_wait = 1; /* XXX */
}

/*
fbt::bplist_iterate:return
/spas[curthread].spa != 0 &&
    spas[curthread].free != 0/
{
	spas[curthread].zio_wait = 1;
}
 */

fbt::zio_wait:return
/spas[curthread].spa != 0 &&
    spas[curthread].zio_wait != 0/
{
	spas[curthread].free_time += timestamp - spas[curthread].free;
}

fbt::dsl_pool_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].dsl_pool_sync = timestamp;
}

fbt::dsl_pool_sync:return
/spas[curthread].dsl_pool_sync != 0/
{
	spas[curthread].dsl_pool_sync_time += timestamp - spas[curthread].dsl_pool_sync;
	spas[curthread].dsl_pool_sync_count++;
	spas[curthread].stage = 0;
}

fbt::ddt_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].ddt_sync = timestamp;
}

fbt::ddt_sync:return
/spas[curthread].ddt_sync != 0/
{
	spas[curthread].ddt_sync_time += timestamp - spas[curthread].ddt_sync;
}

fbt::dsl_scan_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].dsl_scan_sync = timestamp;
}

fbt::dsl_scan_sync:return
/spas[curthread].dsl_scan_sync != 0/
{
	spas[curthread].dsl_scan_sync_time += timestamp - spas[curthread].dsl_scan_sync;
}

fbt::dsl_scan_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].dsl_scan_sync = timestamp;
}

fbt::dsl_scan_sync:return
/spas[curthread].dsl_scan_sync != 0/
{
	spas[curthread].dsl_scan_sync_time += timestamp - spas[curthread].dsl_scan_sync;
}

fbt::dmu_objset_is_dirty:return
/spas[curthread].spa != 0 && arg1 == 0/
{
	spas[curthread].converged = timestamp;
}

/* ============================= */

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 0/
{
	spas[curthread].dsl_dataset_sync = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 0 && spas[curthread].dsl_dataset_sync != 0/
{
	spas[curthread].dsl_dataset_sync_time = timestamp - spas[curthread].dsl_dataset_sync;
	spas[curthread].dsl_dataset_sync = 0;
	spas[curthread].stage++;
}

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 1/
{
	spas[curthread].dsl_dataset_sync2 = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 1 && spas[curthread].dsl_dataset_sync2 != 0/
{
	spas[curthread].dsl_dataset_sync2_time = timestamp - spas[curthread].dsl_dataset_sync2;
	spas[curthread].dsl_dataset_sync2 = 0;
	spas[curthread].stage++;
}

/*
fbt::dsl_dir_sync:entry
/spas[curthread].spa != 0 && spas[curthread].stage == 2/
{
	spas[curthread].dsl_dir_sync = timestamp;
}

fbt::dsl_dir_sync:return
/spas[curthread].spa != 0 && spas[curthread].stage == 2/
{
	spas[curthread].dsl_dir_sync_time += spas[curthread].dsl_dir_sync - timestamp;
}
*/

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 2/
{
	spas[curthread].dmu_objset_sync = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 2 && spas[curthread].dmu_objset_sync != 0/
{
	spas[curthread].dmu_objset_sync_time = timestamp - spas[curthread].dmu_objset_sync;
	spas[curthread].dmu_objset_sync = 0;
	spas[curthread].stage++;
}

fbt::dsl_sync_task_group_sync:entry
/spas[curthread].spa != 0 && spas[curthread].stage == 3/
{
	spas[curthread].dsl_sync_task_group_sync = timestamp;
}

fbt::dsl_sync_task_group_sync:return
/spas[curthread].spa != 0 && spas[curthread].stage == 3/
{
	spas[curthread].dsl_sync_task_group_sync_time += spas[curthread].dsl_sync_task_group_sync - timestamp;
}

/* ============================= */

/*
profile:::tick-1sec
{
	printa(@counts);
	printa(@times);
}
 */
