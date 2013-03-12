#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option defaultargs
#pragma D option switchrate=10hz

dsl_pool_t *dp;
/*struct dmu_buf **ba_buf_ptr;*/
dmu_buf_t **ba_buf_ptr;
struct thread *sync_thread;
uint64_t start;
uint64_t prev_ts;

uint64_t deadlist_start;
uint64_t deadlist_elapsed;
uint64_t deadlist_blocks;
int deadlist_err;
int deadlist_zio_wait;
uint64_t deadlist_start_blocks;
uint64_t deadlist_start_bytes;
uint64_t deadlist_start_subobjs;
uint64_t deadlist_end_blocks;
uint64_t deadlist_end_bytes;
uint64_t deadlist_end_subobjs;

uint64_t async_destroy_start;
uint64_t async_destroy_elapsed;
uint64_t async_destroy_blocks;
int async_destroy_err;
int async_destroy_zio_wait;
uint64_t async_destroy_start_count;
uint64_t async_destroy_start_bytes;
uint64_t async_destroy_end_count;
uint64_t async_destroy_end_bytes;

BEGIN
{
	sampling_count = $1;
	saimpling_limited = sampling_count > 0 ? 1 : 0;

	sync_thread = 0;
	dp = 0;
	deadlist_start = 0;
	async_destroy_start = 0;
	ba_buf_ptr = 0;
	hold_returned = 0;
	deadlist_zio_wait = 0;
	async_destroy_zio_wait = 0;
	start = 0;
	prev_ts = 0;
}

fbt::dsl_scan_sync:entry
{
	dp = args[0];
	scn = dp->dp_scan;
	start = timestamp;
	sync_thread = curthread;
}

fbt::dsl_scan_sync:return
/prev_ts != 0 && (deadlist_start != 0 || async_destroy_start != 0)/
{
	printf("time since previous scan (us):\t%u\n", (start - prev_ts) / 1000);
}

fbt::dsl_scan_sync:return
/deadlist_start != 0 || async_destroy_start != 0/
{
	printf("dsl_scan_sync timestamp:\t%u\n", start);
}

fbt::dsl_scan_sync:return
/dp != 0 && deadlist_start != 0/
{
	printf("deadlist had %u direct items / %u sub-objects / %u bytes\n",
	    deadlist_start_blocks, deadlist_start_subobjs, deadlist_start_bytes);
	printf("deadlist has %u items / %u sub-objects / %u bytes\n",
	    deadlist_end_blocks, deadlist_end_subobjs, deadlist_end_bytes);
	printf("deadlist processed blocks:\t%u\n", deadlist_blocks);
	printf("deadlist processing time (us):\t%u\n", deadlist_elapsed / 1000);
	printf("deadlist processing completed:\t%s\n", deadlist_err == -1 ? "no" : "yes");
	printf("deadlist ret:\t%d\n", deadlist_err);

	deadlist_elapsed = 0;
	deadlist_err = 0;
	deadlist_start_blocks = 0;
	deadlist_start_bytes = 0;
	deadlist_start_subobjs = 0;
	deadlist_end_blocks = 0;
	deadlist_end_bytes = 0;
	deadlist_end_subobjs = 0;
}

fbt::dsl_scan_sync:return
/dp != 0 && async_destroy_start != 0/
{
	printf("async destroy tree had %u items / %u bytes\n", async_destroy_start_count, async_destroy_start_bytes);
	printf("async destroy tree has %u items / %u bytes\n", async_destroy_end_count, async_destroy_end_bytes);
	printf("async destroy processed blocks:\t%u\n", async_destroy_blocks);
	printf("async destroy processing time (us):\t%u\n", async_destroy_elapsed / 1000);
	printf("async destroy processing completed:\t%s\n", async_destroy_err == -1 ? "no" : "yes");

	async_destroy_elapsed = 0;
	async_destroy_err = 0;
	async_destroy_start_count = 0;
	async_destroy_start_bytes = 0;
	async_destroy_end_count = 0;
	async_destroy_end_bytes = 0;
}

fbt::dsl_scan_sync:return
/dp != 0 && (deadlist_start != 0 || async_destroy_start != 0)/
{
	this->elapsed = timestamp - start;
	printf("dsl_scan_sync total time (us):\t%u\n", this->elapsed / 1000);
	printf("\n");
	deadlist_start = 0;
	async_destroy_start = 0;
}

fbt::dsl_scan_sync:return
/dp != 0/
{
	prev_ts = timestamp;
	dp = 0;
	sampling_count--;
}

fbt::dsl_scan_sync:return
/dp != 0 && saimpling_limited && sampling_count == 0/
{
	exit(0);
}

fbt::bpobj_iterate_impl:entry
/dp != 0 && args[0] == &dp->dp_free_bpobj/
{
	deadlist_start = timestamp;
	deadlist_start_blocks = dp->dp_free_bpobj.bpo_phys->bpo_num_blkptrs;
	deadlist_start_bytes = dp->dp_free_bpobj.bpo_phys->bpo_bytes;
	deadlist_start_subobjs = dp->dp_free_bpobj.bpo_phys->bpo_num_subobjs;
}

fbt::bpobj_iterate_impl:return
/deadlist_start != 0 && curthread == sync_thread/
{
	deadlist_zio_wait = 1;
	deadlist_err = arg1;
}

fbt::zio_wait:return
/deadlist_zio_wait/
{
	deadlist_elapsed = timestamp - deadlist_start;
	deadlist_blocks = scn->scn_visited_this_txg;
	deadlist_end_blocks = dp->dp_free_bpobj.bpo_phys->bpo_num_blkptrs;
	deadlist_end_bytes = dp->dp_free_bpobj.bpo_phys->bpo_bytes;
	deadlist_end_subobjs = dp->dp_free_bpobj.bpo_phys->bpo_num_subobjs;
	deadlist_zio_wait = 0;
}

fbt::bptree_iterate:entry
/args[1] == dp->dp_bptree_obj/
{
	async_destroy_start = timestamp;
}

fbt::bptree_iterate:return
/async_destroy_start != 0 && curthread == sync_thread/
{
	async_destroy_zio_wait = 1;
	async_destroy_err = arg1;
}

fbt::zio_wait:return
/async_destroy_zio_wait/
{
	async_destroy_elapsed = timestamp - async_destroy_start;
	async_destroy_blocks = scn->scn_visited_this_txg - deadlist_blocks;
	async_destroy_zio_wait = 0;
}

fbt::dmu_bonus_hold:entry
/async_destroy_start != 0 && curthread == sync_thread && args[1] == dp->dp_bptree_obj/
{
	ba_buf_ptr = args[3];
}

fbt::dmu_bonus_hold:return
/async_destroy_start != 0 && curthread == sync_thread && ba_buf_ptr != 0 && hold_returned == 0/
{
	hold_returned = 1;
	this->ba_phys = (bptree_phys_t *)(*ba_buf_ptr)->db_data;
	async_destroy_start_count = this->ba_phys->bt_end - this->ba_phys->bt_begin;
	async_destroy_start_bytes = this->ba_phys->bt_bytes;
}

fbt::dmu_buf_rele:entry
/async_destroy_start != 0 && curthread == sync_thread && ba_buf_ptr != 0 && (void*)args[0] == (void*)*ba_buf_ptr/
{
	this->ba_phys = (bptree_phys_t *)(*ba_buf_ptr)->db_data;
	async_destroy_end_count = this->ba_phys->bt_end - this->ba_phys->bt_begin;
	async_destroy_end_bytes = this->ba_phys->bt_bytes;
	ba_buf_ptr = 0;
}

