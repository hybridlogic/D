#!/usr/sbin/dtrace -s

#pragma D option quiet

dsl_pool_t *dp;
dmu_buf_t **ba_buf_ptr;
struct thread *sync_thread;
uint64_t start;
uint64_t deadlist_start;
uint64_t async_destroy_start;
uint64_t deadlist_elapsed;
uint64_t deadlist_blocks;
int deadlist_err;
uint64_t async_destroy_elapsed;
uint64_t async_destroy_blocks;
int async_destroy_err;
uint64_t async_destroy_start_count;
uint64_t async_destroy_start_bytes;
uint64_t async_destroy_end_count;
uint64_t async_destroy_end_bytes;

BEGIN
{
	sync_thread = 0;
	dp = 0;
	deadlist_start = 0;
	async_destroy_start = 0;
	ba_buf_ptr = 0;
	hold_returned = 0;
}

fbt::dsl_scan_sync:entry
{
	dp = args[0];
	scn = dp->dp_scan;
	start = timestamp;
	sync_thread = curthread;
}

fbt::dsl_scan_sync:return
/dp != 0/
{
	elapsed = timestamp - start;
	printf("dsl_scan_sync total time (us):\t%u\n", elapsed / 1000);
	printf("deadlist processing time (us):\t%u\n", deadlist_elapsed / 1000);
	printf("deadlist processed blocks:\t%u\n", deadlist_blocks);
	printf("deadlist processing completed:\t%s\n", deadlist_err == -1 ? "no" : "yes");
	printf("async destroy processing time (us):\t%u\n", async_destroy_elapsed / 1000);
	printf("async destroy processed blocks:\t%u\n", async_destroy_blocks);
	printf("async destroy processing completed:\t%s\n", async_destroy_err == -1 ? "no" : "yes");
	printf("async destroy tree had %u items / %u bytes\n", async_destroy_start_count, async_destroy_start_bytes);
	printf("async destroy tree has %u items / %u bytes\n", async_destroy_end_count, async_destroy_end_bytes);
	exit(0);
}

fbt::bpobj_iterate_impl:entry
/args[0] == &dp->dp_free_bpobj/
{
	deadlist_start = timestamp;
}

fbt::zio_wait:return
/deadlist_start != 0 && curthread == sync_thread/
{
	deadlist_elapsed = timestamp - deadlist_start;
	deadlist_blocks = scn->scn_visited_this_txg;
	deadlist_err = arg1;
}

fbt::bptree_iterate:entry
/args[1] == dp->dp_bptree_obj/
{
	async_destroy_start = timestamp;
}

fbt::bptree_iterate:return
/async_destroy_start != 0 && curthread == sync_thread/
{
	async_destroy_elapsed = timestamp - async_destroy_start;
	async_destroy_blocks = scn->scn_visited_this_txg - deadlist_blocks;
	async_destroy_err = arg1;
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
/async_destroy_start != 0 && curthread == sync_thread && (void*)args[0] == (void*)*ba_buf_ptr/
{
	this->ba_phys = (bptree_phys_t *)(*ba_buf_ptr)->db_data;
	async_destroy_end_count = this->ba_phys->bt_end - this->ba_phys->bt_begin;
	async_destroy_end_bytes = this->ba_phys->bt_bytes;
	ba_buf = 0;
}

