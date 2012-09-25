#!/usr/bin/bash
#
# Last modified: 9/21/2012
#
# Written by Andrew Galloway (andrew.galloway@nexenta.com)
# Inspiration from spasync.d from www.dtracebook.com
#
# Script purpose is to show you time spent in and between
# transaction group commits on a single pool, with KB and I/O
# thrown in for good measure.
#
# Can help determine if txg's are coming faster than they
# should, as well as determine how much throughput and
# I/O each txg is doing.
#
# Output will be like this:
#
# Begin            8197266  10000 ms           2012 Sep 25 01:10:02
# End              8197266      600 us                0 KB        1
#
# The only confusing part is the times - on a Begin, and left-justified,
# you have time since beginning of last txg. On an End line, and right-
# justified, you have the time spent doing the txg. You can tie txg's 
# together in the printout using the TXG ID field - they'll usually 
# print out in order (Begin, End, Begin, End, ...), but not 100% of 
# the time.
#
# END HEADER
# -----------------------------------

# sadly doesn't work on Nexenta today, as we have no en_US locale
# when we do some day, this should let you get comma seperators
# on time and KB and I/O
LC_NUMERIC="en_US"
SEP="'"

if [ $# -eq 0 ]; then
	echo "Must specify pool name."
	exit 1;
fi

dtrace='
#pragma D option quiet

inline string POOLNAME	= "'$1'";

dtrace:::BEGIN
{
	@bytes = sum(0);
	time_since = 0;

	printf("Action\t%16s  Time      \t%16s %8s\n", "TXG ID", "Begin Timestamp", " ");
	printf("      \t%16s            \t%16s %8s\n", " ", "Bytes", "IO");
	printf("------\t----------------  ----------\t---------------- --------\n");
}

fbt:zfs:spa_sync:entry
/args[0]->spa_name == POOLNAME/
{
	tracing = 1;
	self->txgid = arg1;
	self->tr = timestamp;
	self->pool = stringof(args[0]->spa_name);

	time_elapsed = (time_since > 0) ? ((timestamp - time_since) / 1000000) : 0;

	printf("Begin\t%16d  %'$SEP'-4d %-5s\t%25Y\n", self->txgid, time_elapsed, "ms", walltimestamp);

	time_since = timestamp;
}

io:::start
/tracing/
{
	@io = count();
	@bytes = sum(args[0]->b_bcount);
}

fbt:zfs:spa_sync:return
/tracing/
{
	normalize(@bytes, 1024);

	elapsed = (timestamp-self->tr) / 1000;
	time_type = "";

	time_type = (elapsed > 1000) ? "ms" : "us";
	elapsed = (elapsed > 1000) ? (elapsed / 1000) : (elapsed);

	printf("End\t%16d  %7d %s\t", self->txgid, elapsed, time_type);
	printa("%@'$SEP'13d KB %@'$SEP'8d\n", @bytes, @io);

	clear(@bytes); 
	clear(@io);
	tracing = 0;
}
'

/usr/sbin/dtrace -n "$dtrace" >&2
