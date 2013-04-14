#!/usr/sbin/dtrace -s

#pragma D option dynvarsize=80m
#pragma D option quiet


inline uint64_t METASLAB_WEIGHT_PRIMARY = 1ULL << 63;
inline uint64_t METASLAB_WEIGHT_SECONDARY = 1ULL << 62;
inline uint64_t METASLAB_ACTIVE_MASK = METASLAB_WEIGHT_PRIMARY | METASLAB_WEIGHT_SECONDARY;
inline uint64_t ONE_GB = 1ULL << 30;


/*int active[space_map_t *];*/
metaslab_class_t *normal_mc;


fbt::metaslab_alloc:entry
/args[1]->mc_spa->spa_normal_class == args[1]/
{
	/*
	this->mc = args[1];
	self->type = this->mc->mc_spa->spa_log_class == this->mc ?  "log" :
	    (this->mc->mc_spa->spa_normal_class == this->mc ? "normal" : "other");
	*/

	normal_mc = args[1];;
	self->ndvas = arg4;
	self->nfailed = self->ngood = 0;
	self->metaslab_block_picker = 0;
	@counts["requests"] = count();
	this->psize = arg2 / 512;
	@mins["alloc-size-512"] = min(this->psize);
	@maxs["alloc-size-512"] = max(this->psize);
	@avgs["alloc-size-512"] = avg(this->psize);
}

fbt::metaslab_alloc:return
/self->ndvas/
{
	this->too_large = arg1 == 0 ? 0 : 1;
	this->total = self->nfailed + self->ngood;
	@sums["blocks-requested"] = sum(self->ndvas);
	@sums["metaslab-visits"] = sum(this->total);
	@sums["overhead"] = sum(this->total + this->too_large - self->ndvas);
	@sums["retried-allocs"] = sum(self->nfailed);
	@sums["too-large-allocs"] = sum(this->too_large);
	self->ndvas = 0;
	self->nfailed = self->ngood = 0;
}

fbt::metaslab_activate:entry
/self->ndvas/
{
	this->msp = args[0];
	this->mg = this->msp->ms_group;
	/*self->mg_name = (string)this->mg->mg_vd->vdev_path;*/
	self->mg_id = this->mg->mg_vd->vdev_id;
	@weigths[self->mg_id, this->msp->ms_map->sm_start / ONE_GB] =
	    min((uint64_t)this->msp->ms_weight);
	@raw_weigths[self->mg_id, this->msp->ms_map->sm_start / ONE_GB] =
	    min((uint64_t)this->msp->ms_weight & ~METASLAB_ACTIVE_MASK);
}

fbt::metaslab_df_alloc:entry
/self->ndvas/
{
	self->sm = args[0];
	self->alloc_ts = timestamp;
	this->free_pct = self->sm->sm_space * 100 / self->sm->sm_size;
	@mins["free-pct"] = min(this->free_pct);
	@maxs["free-pct"] = max(this->free_pct);
	@avgs["free-pct"] = avg(this->free_pct);
	@freepct[self->mg_id, self->sm->sm_start / ONE_GB] = min(this->free_pct);
	@size[self->mg_id, self->sm->sm_start / ONE_GB] = min(self->sm->sm_size);
	@start[self->mg_id, self->sm->sm_start / ONE_GB] = min(self->sm->sm_start);
	@req[self->mg_id, self->sm->sm_start / ONE_GB] = count();
}

/* Not probed -- tail-call optimized with a call to metaslab_block_picker. */
fbt::metaslab_df_alloc:return
/self->sm/
{
	this->alloc = (timestamp - self->alloc_ts) / 1000;
	self->alloc_ts = 0;
	@mins["alloc-time-us"] = min(this->alloc);
	@maxs["alloc-time-us"] = max(this->alloc);
	@avgs["alloc-time-us"] = avg(this->alloc);
	this->dummy = arg1 == -1ULL ? self->nfailed++ : self->ngood++;
	self->sm = 0;
}

fbt::space_map_seg_compare:entry
/self->sm/
{
	@counts["first-fit-iterations"] = count();
}

fbt::metaslab_segsize_compare:entry
/self->sm/
{
	@counts["best-fit-iterations"] = count();
}

fbt::metaslab_block_picker:entry
{
	self->metaslab_block_picker++;
}

fbt::metaslab_block_picker:return
{
	self->metaslab_block_picker--;
}

fbt::metaslab_block_picker:return
/self->sm && self->metaslab_block_picker == 0/
{
	this->alloc = (timestamp - self->alloc_ts) / 1000;
	self->alloc_ts = 0;
	@mins["alloc-time-us"] = min(this->alloc);
	@maxs["alloc-time-us"] = max(this->alloc);
	@avgs["alloc-time-us"] = avg(this->alloc);
	this->dummy = arg1 == -1ULL ? self->nfailed++ : self->ngood++;
	self->sm = 0;
	self->metaslab_block_picker = 0;
}

/* Not probed -- seems to be inlined. */
fbt::metaslab_pp_maxsize:return
/self->ndvas && self->sm/
{
	this->max_size = arg1 / 1024; /* KB */
	@mins["max-contiguous-kb"] = min(this->max_size);
	@maxs["max-contiguous-kb"] = max(this->max_size);
	@avgs["max-contiguous-kb"] = avg(this->max_size);
	@maxcontig[self->mg_id, self->sm->sm_start / ONE_GB] = min(this->max_size);
}

fbt::avl_last:entry
/self->sm && self->metaslab_block_picker == 0/
{
	self->avl_last = 1;
}

fbt::avl_last:return
/self->avl_last/
{
	self->avl_last = 0;
	this->ss = (space_seg_t *)arg1;
	this->max_size = this->ss != NULL ? (this->ss->ss_end - this->ss->ss_start) / 1024 : 0; /* KB */
	@mins["max-contiguous-kb"] = min(this->max_size);
	@maxs["max-contiguous-kb"] = max(this->max_size);
	@avgs["max-contiguous-kb"] = avg(this->max_size);
	@maxcontig[self->mg_id, self->sm->sm_start / ONE_GB] = min(this->max_size);
}

profile:::tick-$1s
{
	printf("==========\n");
	printf("aliquot\t%u\n", normal_mc->mc_aliquot);
	printf("used-pct\t%u\n", 100 * normal_mc->mc_alloc / normal_mc->mc_space);
	printf("deferred-pct\t%u\n", 100 * normal_mc->mc_deferred / normal_mc->mc_space);

	printa("%s\t%@u\n", @counts);
	printf("\n");
	trunc(@counts);

	printa("%s\t%@u\n", @sums);
	printf("\n");
	trunc(@sums);

	printf("minimums:\n");
	printa("%s\t%@u\n", @mins);
	printf("\n");
	trunc(@mins);

	printf("averages:\n");
	printa("%s\t%@u\n", @avgs);
	printf("\n");
	trunc(@avgs);

	printf("maximums:\n");
	printa("%s\t%@u\n", @maxs);
	printf("\n");
	trunc(@maxs);

	printf("requests per slab:\n");
	printa("%u:%u\t%@u\n", @req);
	printf("\n");
	trunc(@req);
	printf("free-pct per slab:\n");
	printa("%u:%u\t%@u\n", @freepct);
	printf("\n");
	trunc(@freepct);
	printf("max-contig-kb per slab:\n");
	printa("%u:%u\t%@u\n", @maxcontig);
	printf("\n");
	trunc(@maxcontig);
	printf("weigth per slab:\n");
	printa("%u:%u\t%@u\n", @weigths);
	printf("\n");
	trunc(@weigths);
	printf("raw weigth per slab:\n");
	printa("%u:%u\t%@u\n", @raw_weigths);
	printf("\n");
	trunc(@raw_weigths);
	printf("sizes per slab:\n");
	printa("%u:%u\t%@u\n", @size);
	printf("\n");
	trunc(@size);
	printf("starting offset per slab:\n");
	printa("%u:%u\t%@u\n", @start);
	printf("\n");
	trunc(@start);
}
