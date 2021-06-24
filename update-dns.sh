#!/bin/sh
# exit script when command fails
set -e

if [ $# -ne 1 ]; then
	echo "Usage: $0 <git-directory>" >&2
	exit 1
fi

# navigate to directory given as parameter
cd $1

oldhash=$(git rev-parse HEAD)
git pull -q --ff-only

/srv/ffslfl-scripts/10-24-reverse.sh
/srv/ffslfl-scripts/fd07-96ae-572e-reverse.sh

if [ "$oldhash" != "$(git rev-parse HEAD)" ]; then
	/bin/systemctl reload bind9
fi
