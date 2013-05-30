#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option defaultargs
#pragma D option bufsize=200m
#pragma D option dynvarsize=256m
#pragma D option cleanrate=5000hz

profile:::profile-4001
{
    @stacks[pid, tid, execname, stack()] = count();
}
