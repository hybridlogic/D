fbt::zfs_read:return, zft::zfs_write:return
/self->start && (timestamp- - self->start) => min_ns/
{
    this->iotime = (timestamp - self->start) / 1000000;
    this->dir = probefunc == "zfs_read" ? "R" : "W";
    printf("%-20Y %-16s %1s %4d %6d %s\n", walltimestamp,
            execname, this->dir, self->kb, this->iotime,
            self->path != NULL ? stringof(self->path) : "<null>");
}
fbt::zfs_read:return, fbt::zfs_write:return
{
    self->path = 0; self->kb = 0; self->start = 0;
}
