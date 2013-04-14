#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option defaultargs
#pragma D option bufsize=200m
#pragma D option dynvarsize=256m
#pragma D option cleanrate=5000hz

inline uint64_t TXG_MASK = 3;


struct spa_info {
	spa_t *spa;

	dmu_tx_t *tx;
	int zio_wait;
	uint64_t txg;

	uint64_t tx_commit;
	uint64_t misc_ts;
	uint64_t start_time;
	uint64_t prev_time;

	uint64_t deferred;
	uint64_t deferred_time;
	uint64_t free;
	uint64_t free_time;
	uint64_t dsl_dataset_sync;
	uint64_t dsl_dataset_sync_time;
	uint64_t converged;
	uint64_t dsl_pool_sync_count;
	uint64_t dsl_pool_sync_time;
	uint64_t dsl_pool_sync;
	uint64_t vdev_sync_time;
	uint64_t vdev_sync;
	uint64_t dsl_dataset_sync2_time;
	uint64_t dsl_dataset_sync2;
	uint64_t dsl_sync_task_sync_time;
	uint64_t dsl_sync_task_sync;
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

	spas[this->thr].spa = 0;
	spas[this->thr].start_time = 0;
	spas[this->thr].prev_time = 0;
	spas[this->thr].deferred = 0;
	spas[this->thr].deferred_time = 0;
	spas[this->thr].zio_wait = 0;
	spas[this->thr].txg = 0;
	spas[this->thr].tx = 0;
	spas[this->thr].misc_ts = 0;
	spas[this->thr].tx_commit = 0;
	spas[this->thr].free = 0;
	spas[this->thr].free_time = 0;
	spas[this->thr].dsl_dataset_sync = 0;
	spas[this->thr].dsl_dataset_sync_time = 0;
	spas[this->thr].converged = 0;
	spas[this->thr].dsl_pool_sync_count = 0;
	spas[this->thr].dsl_pool_sync_time = 0;
	spas[this->thr].dsl_pool_sync = 0;
	spas[this->thr].vdev_sync_time = 0;
	spas[this->thr].vdev_sync = 0;
	spas[this->thr].dsl_dataset_sync2_time = 0;
	spas[this->thr].dsl_dataset_sync2 = 0;
	spas[this->thr].dsl_sync_task_sync_time = 0;
	spas[this->thr].dsl_sync_task_sync = 0;
	spas[this->thr].dmu_objset_sync_time = 0;
	spas[this->thr].dmu_objset_sync = 0;
	spas[this->thr].dsl_dir_sync_time = 0;
	spas[this->thr].dsl_dir_sync = 0;
	spas[this->thr].ddt_sync_time = 0;
	spas[this->thr].ddt_sync = 0;
	spas[this->thr].dsl_scan_sync_time = 0;
	spas[this->thr].dsl_scan_sync = 0;
	spas[this->thr].stage = 0;

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
 	printf("total running time:\t\t%d\n", this->total);
	printf("\n");
 	printf("misc1 time:\t\t\t%d\n", spas[this->thr].misc_ts - this->s);
	printf("\n");
 	printf("deferred freeing time:\t\t%d\n", spas[this->thr].deferred);
	printf("\n");
	printf("convergance passes:\t\t%d\n", spas[this->thr].dsl_pool_sync_count);
	printf("total dsl_pool_sync time:\t%d\n", spas[this->thr].dsl_pool_sync_time);
	printf("\tdatasets sync time:\t%d\n", spas[this->thr].dsl_dataset_sync2_time + spas[this->thr].dsl_dataset_sync_time);
	printf("\tsynctask time:\t\t%d\n", spas[this->thr].dsl_sync_task_sync_time);
	printf("\tmos time:\t\t%d\n", spas[this->thr].dmu_objset_sync_time);
	printf("\tdsl dir time:\t\t%d\n",  spas[this->thr].dsl_dir_sync_time);
	printf("vdev sync time:\t\t\t%d\n", spas[this->thr].vdev_sync_time);
	printf("\t(includes metaslab and spacemap processing)\n");
	printf("ddt sync time:\t\t\t%d\n", spas[this->thr].ddt_sync_time);
	printf("block freeing time:\t\t%d\n", spas[this->thr].free_time);
	printf("dsl scan time:\t\t\t%d\n", spas[this->thr].dsl_scan_sync_time);
	printf("\t(includes async destroy and deadlist processing time)\n");
	printf("\n");
	printf("total time to convergance:\t%d\n", spas[this->thr].converged - this->s);
	printf("uberblock rewrite:\t\t%d\n", spas[this->thr].tx_commit - spas[this->thr].converged);
	printf("misc2 time:\t\t\t%d\n", this->ts - spas[this->thr].tx_commit);

	printf("\n----------------------------------------\n\n");
}

fbt::dmu_tx_create_assigned:return
/spas[curthread].spa != 0 && spas[curthread].tx == 0/
{
	spas[curthread].misc_ts = timestamp;
	spas[curthread].tx = (dmu_tx_t *)args[1];
}

fbt::dmu_tx_commit:entry
/spas[curthread].tx == args[0]/
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
    spas[curthread].zio_wait != 0 &&
    spas[curthread].deferred > 0/
{
	spas[curthread].deferred_time = timestamp - spas[curthread].deferred;
	spas[curthread].zio_wait = 0;
	spas[curthread].deferred = 0;
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
    spas[curthread].zio_wait != 0 &&
    spas[curthread].free > 0/
{
	spas[curthread].free_time += timestamp - spas[curthread].free;
	spas[curthread].zio_wait = 0;
	spas[curthread].free > 0;
}

fbt::dsl_pool_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].dsl_pool_sync = timestamp;
	spas[curthread].stage = 1;
}

fbt::dsl_pool_sync:return
/spas[curthread].dsl_pool_sync != 0/
{
	spas[curthread].dsl_pool_sync_time += timestamp - spas[curthread].dsl_pool_sync;
	spas[curthread].dsl_pool_sync_count++;
	spas[curthread].stage = 0;
	spas[curthread].dsl_pool_sync = 0;
}


fbt::vdev_sync:entry
/spas[curthread].spa != 0/
{
	spas[curthread].vdev_sync = timestamp;
}

fbt::txg_list_add:entry
/spas[curthread].vdev_sync != 0 && args[0] == &spas[curthread].spa->spa_vdev_txg_list/
{
	spas[curthread].vdev_sync_time += timestamp - spas[curthread].vdev_sync;
	spas[curthread].vdev_sync = 0;
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

fbt::dmu_objset_is_dirty:return
/spas[curthread].spa != 0 && arg1 == 0/
{
	spas[curthread].converged = timestamp;
}

/* ============================= */

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 1/
{
	spas[curthread].dsl_dataset_sync = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 1 && spas[curthread].dsl_dataset_sync != 0/
{
	spas[curthread].dsl_dataset_sync_time += timestamp - spas[curthread].dsl_dataset_sync;
	spas[curthread].dsl_dataset_sync = 0;
	spas[curthread].stage++;
}

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 2/
{
	spas[curthread].dsl_dataset_sync2 = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 2 && spas[curthread].dsl_dataset_sync2 != 0/
{
	spas[curthread].dsl_dataset_sync2_time += timestamp - spas[curthread].dsl_dataset_sync2;
	spas[curthread].dsl_dataset_sync2 = 0;
	spas[curthread].stage++;
}

fbt::dsl_dir_sync:entry
/spas[curthread].spa != 0 && spas[curthread].stage == 3/
{
	spas[curthread].dsl_dir_sync = timestamp;
}

fbt::txg_list_remove:return
/spas[curthread].spa != 0 && spas[curthread].stage == 3 &&
    spas[curthread].dsl_dir_sync != 0 && arg1 == 0/
{
	spas[curthread].dsl_dir_sync_time += timestamp - spas[curthread].dsl_dir_sync;
	spas[curthread].dsl_dir_sync = 0;
}

fbt::zio_root:entry
/spas[curthread].dsl_pool_sync != 0 && args[0] == spas[curthread].spa &&
    spas[curthread].stage == 3/
{
	spas[curthread].dmu_objset_sync = timestamp;
}

fbt::zio_wait:return
/spas[curthread].dsl_pool_sync != 0 &&
    spas[curthread].stage == 3 && spas[curthread].dmu_objset_sync != 0/
{
	spas[curthread].dmu_objset_sync_time += timestamp - spas[curthread].dmu_objset_sync;
	spas[curthread].dmu_objset_sync = 0;
	spas[curthread].stage++;
}

fbt::dsl_sync_task_sync:entry
/spas[curthread].spa != 0 && spas[curthread].stage == 4/
{
	spas[curthread].dsl_sync_task_sync = timestamp;
}

fbt::dsl_sync_task_sync:return
/spas[curthread].spa != 0 && spas[curthread].stage == 4/
{
	spas[curthread].dsl_sync_task_sync_time += timestamp - spas[curthread].dsl_sync_task_sync;
	spas[curthread].stage++;
}

/* ============================= */

/*
profile:::tick-1sec
{
	printa(@counts);
	printa(@times);
}
 */
