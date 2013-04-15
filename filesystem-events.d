#!/usr/sbin/dtrace -s

/* See vfssnoop.d in the d-trace book if you want filenames */

#pragma D option quiet
#pragma D option defaultargs
#pragma D option switchrate=10hz
#pragma D option dynvarsize=256m
#pragma D option cleanrate=5000hz

vfs::vop_read:entry
/$$1 == "read"/
{
    self->b = args[1]->a_uio->uio_resid;
    self->iotype = "read";
}

vfs::vop_open:entry, vfs::vop_close:entry, vfs::vop_ioctl:entry,
vfs::vop_getattr:entry, vfs::vop_readdir:entry
/$$1 == "read"/
{
    self->b = 0;
    self->iotype = "read";
}

vfs::vop_write:entry
/$$1 == "write"/
{
    self->b = args[1]->a_uio->uio_resid;
    self->iotype = "write";
}

vfs::vop_read:return, vfs::vop_write:return,
vfs::vop_open:return, vfs::vop_close:return, vfs::vop_ioctl:return,
vfs::vop_getattr:return, vfs::vop_readdir:return
{
    self->vp = args[0];
    self->mount = self->vp != NULL ? self->vp->v_mount : 0;
    self->fi_mount = self->mount ? stringof(self->mount->mnt_stat.f_mntonname) : "<unknown>"; /* where we mount on */
}

vfs::vop_read:return, vfs::vop_open:return, vfs::vop_close:return,
vfs::vop_ioctl:return, vfs::vop_getattr:return, vfs::vop_readdir:return
/$$1 == "read"/
{
    @mountio[self->fi_mount] = sum(self->b);
}

vfs::vop_write:return
/$$1 == "write"/
{
    @mountio[self->fi_mount] = sum(self->b);
}
profile:::tick-1sec {
    printa("%s %@d\n", @mountio);
    printf("===\n");
    trunc(@mountio);
}
