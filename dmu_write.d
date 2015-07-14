#!/usr/sbin/dtrace -CqZs

/* Copyright ClusterHQ Inc. See LICENSE file for details. */

#pragma D option dynvarsize=80m
#pragma D option cleanrate=1000hz

#define WHERE		(self->zpl_write ? "ZPL" : \
			(self->ioc_recv ? "Receive" : \
			(self->space_map ? "SpaceMap" : \
			(self->history ? "History" : \
			(self->spa ? "Spa" : "Other")))))

#define ACCOUNT(b)	@counts[WHERE] = count() ; @bytes[WHERE] = sum(b)
#define IS_OTHER	(!self->zpl_write && !self->ioc_recv && !self->space_map && !self->history && !self->spa)

/*
fbt::dmu_read:entry, fbt::dmu_read_uio:entry
{
	@["read", func(caller)] = sum(arg3);
}
*/

/* ===== Caller detectors ===== */
fbt::zfs_freebsd_write:entry,
fbt::zfs_freebsd_putpages:entry
{
	self->zpl_write = 1;
}

fbt::zfs_freebsd_write:return,
fbt::zfs_freebsd_putpages:return
{
	self->zpl_write = 0;
}

fbt::zfs_ioc_recv:entry
{
	self->ioc_recv = 1;
}

fbt::zfs_ioc_recv:return
{
	self->ioc_recv = 0;
}

fbt::space_map_sync:entry
{
	self->space_map = 1;
}

fbt::space_map_sync:return
{
	self->space_map = 0;
}

fbt::spa_history_write:entry
{
	self->history = 1;
}

fbt::spa_history_write:return
{
	self->history = 0;
}

fbt::spa_sync_nvlist:entry,
fbt::bptree_add:entry,
fbt::bptree_iterate:entry,
fbt::bpobj_enqueue_subobj:entry
{
	self->spa = 1;
}

fbt::spa_sync_nvlist:return,
fbt::bptree_add:return,
fbt::bptree_iterate:return,
fbt::bpobj_enqueue_subobj:return
{
	self->spa = 0;
}

/* ===== Actual accounting ===== */

fbt::dmu_write:entry
{
	ACCOUNT(arg3);
}

fbt::dmu_write_uio_dbuf:entry
{
	ACCOUNT(arg2);
}

fbt::dmu_write_pages:entry
{
	ACCOUNT(arg3);
}

fbt::dmu_assign_arcbuf:entry
{
	ACCOUNT(args[2]->b_hdr->b_size);
}

fbt::dmu_write:entry,
fbt::dmu_write_uio_dbuf:entry,
fbt::dmu_write_pages:entry,
fbt::dmu_assign_arcbuf:entry
/IS_OTHER/
{
	@others[stack()] = count();
}

/* Need to handle -1 size which means truncate to a given offset. */
/*
fbt::dmu_free_range:entry, fbt::dmu_free_long_range:entry
{
	@["free", func(caller)] = sum(arg3);
}
*/

profile:::tick-$1s
{
	printf("===\n");
	printa("count_%s %@u\n", @counts);
	clear(@counts);
	printa("bytes_%s %@u\n", @bytes);
	clear(@bytes);
	printf("\n");
	printa(@others);
	trunc(@others);
}
