#!/usr/sbin/dtrace -s

/* Copyright ClusterHQ Inc. See LICENSE file for details. */

/* http://forums.freebsd.org/showthread.php?t=32649 */

#pragma D option quiet
#pragma D option switchrate=10hz
#pragma D option dynvarsize=16m
#pragma D option bufsize=8m

syscall:freebsd:pread:entry
{
        this->fp = curthread->td_proc->p_fd->fd_ofiles[arg0];
        this->vp = this->fp != 0 ? this->fp->f_vnode : 0;
        this->ts = vtimestamp;
        @c = count();
}

syscall:freebsd:pread:entry
/this->vp/
{
        this->ncp = &(this->vp->v_cache_dst) != NULL ? 
                this->vp->v_cache_dst.tqh_first : 0;
        this->fi_name = this->ncp ? (this->ncp->nc_name != 0 ? 
                stringof(this->ncp->nc_name) : "<unknown>") : "<unknown>";
        this->mount = this->vp->v_mount; /* ptr to vfs we are in */
        this->fi_fs = this->mount != 0 ? stringof(this->mount->mnt_stat.f_fstypename) 
                : "<unknown>"; /* filesystem */
        this->fi_mount = this->mount != 0 ? stringof(this->mount->mnt_stat.f_mntonname) 
                : "<unknown>";
}

syscall:freebsd:pread:entry
/* A short cut */
/this->vp == 0 || this->fi_fs == "devfs" || this->fi_fs == 0 || 
this->fi_fs == "<unknown>" || this->fi_name == "<unknown>"/
{
        this->ncp = 0;
}

syscall:freebsd:pread:entry
/this->ncp/
{
        this->dvp = this->ncp->nc_dvp != NULL ? 
               (&(this->ncp->nc_dvp->v_cache_dst) != NULL ? 
               this->ncp->nc_dvp->v_cache_dst.tqh_first : 0) : 0;
        self->name[1] = this->dvp != 0 ? (this->dvp->nc_name != 0 ? 
               stringof(this->dvp->nc_name) : "<unknown>") : "<unknown>";
}

syscall:freebsd:pread:entry
/self->name[1] == "<unknown>" || this->fi_fs == "devfs" || 
this->fi_fs == 0 || this->fi_fs == "<unknown>" || self->name[1] == "/" 
|| self->name[1] == 0/
{
        this->dvp = 0;
}

syscall:freebsd:pread:entry
/this->dvp/
{
        this->dvp = this->dvp->nc_dvp != NULL ? (&(this->dvp->nc_dvp->v_cache_dst) != NULL 
                ? this->dvp->nc_dvp->v_cache_dst.tqh_first : 0) : 0;
        self->name[2] = this->dvp != 0 ? (this->dvp->nc_name != 0 ? 
                stringof(this->dvp->nc_name) : "\0") : "\0";
}

syscall:freebsd:pread:entry
/this->dvp/
{
        this->dvp = this->dvp->nc_dvp != NULL ? (&(this->dvp->nc_dvp->v_cache_dst) != NULL 
                ? this->dvp->nc_dvp->v_cache_dst.tqh_first : 0) : 0;
        self->name[3] = this->dvp != 0 ? (this->dvp->nc_name != 0 ? 
                stringof(this->dvp->nc_name) : "\0") : "\0";
}

syscall:freebsd:pread:entry
/this->fi_mount/
{
        printf("%s/", this->fi_mount);
}

syscall:freebsd:pread:entry
/self->name[3]/
{
        printf("%s/", self->name[3]);
}

syscall:freebsd:pread:entry
/self->name[2]/
{
        printf("%s/", self->name[2]);
}

syscall:freebsd:pread:entry
/self->name[1]/
{
        printf("%s/%s\n", self->name[1], this->fi_name);
}

syscall:freebsd:pread:entry
{
        self->name[1] = 0;
        self->name[2] = 0;
        self->name[3] = 0;
}

tick-10s
{
        exit(0);
}

