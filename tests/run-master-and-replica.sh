#!/bin/bash

set -e
set -x

IMAGE="$1"

date
mkdir data
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data:Z \
	-e PASSWORD=Secret123 "$IMAGE" \
	exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp $ca
if [ -n "$ca" ] ; then
	date
	sudo tests/generate-external-ca.sh data
	date
	docker run $privileged -h ipa.example.test \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
		-v $(pwd)/data:/data:Z \
		-e PASSWORD=Secret123 "$IMAGE" \
		exit-on-finished -U -r EXAMPLE.TEST --setup-dns --no-forwarders --no-ntp \
			--external-cert-file=/data/ipa.crt --external-cert-file=/data/ca.crt
fi
date
docker run $privileged -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data:Z \
	"$IMAGE" \
	exit-on-finished
date
uuidgen | sudo tee data/build-id
touch /tmp/freeipa-master.log
( docker run $privileged --name freeipa-master -h ipa.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data:/data:Z \
	"$IMAGE" | tee /tmp/freeipa-master.log ) &
(
set +x
while ! grep -q 'FreeIPA server started' /tmp/freeipa-master.log ; do
	sleep 10
done
)
docker ps
MASTER_IP=$( docker inspect --format '{{ .NetworkSettings.IPAddress }}' freeipa-master )
date
mkdir data-replica
docker run $privileged --name freeipa-replica -h replica.example.test \
	--sysctl net.ipv6.conf.all.disable_ipv6=0 \
	--tmpfs /run --tmpfs /tmp -v /dev/urandom:/dev/random:ro -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
	-v $(pwd)/data-replica:/data:Z \
	--link freeipa-master:ipa.example.test --dns=$MASTER_IP \
	-e PASSWORD=Secret123 "$IMAGE" \
	exit-on-finished ipa-replica-install -U --skip-conncheck --principal admin --setup-ca --no-ntp
docker ps
date
